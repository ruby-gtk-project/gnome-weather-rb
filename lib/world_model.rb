# frozen_string_literal: true

require 'gtk4'
require_relative 'location'
require_relative 'weather_info'
require_relative 'weather_provider'
require_relative 'settings'

# WorldModel owns the locations the app knows about and their weather.
#
# Ported from upstream's src/shared/world.ts. Same responsibilities: the saved
# locations, a current location from geolocation, the selected one, a cap of ten
# remembered places, a "loading" flag while any fetch is in flight, and a
# settings write debounced to an idle callback.
#
# Upstream's WorldModel implements Gio.ListModel itself, so the popover can
# bind_model straight to it. The Ruby bindings cannot implement a GInterface's
# vfuncs, so the model keeps a Gio::ListStore in step with its own array and
# hands that store out as #list_store; the ordering upstream computes in
# getAll() is applied to the store on every change.
#
# As in the gnome-contacts port, the Ruby arrays are the source of truth and
# nothing is ever read back out of the list store: a GTK wrapper handed back
# after the store dropped its reference can point at freed memory, and that
# crashes rather than raising.
#
class WorldModel
  MAX_LOCATIONS = Settings::MAX_LOCATIONS

  attr_reader :list_store, :settings

  # provider_factory exists so a test can hand the model a provider that
  # answers from a fixture rather than from the network; the app leaves it out
  # and gets the real one.
  def initialize(settings: nil, provider_factory: nil)
    @settings = settings || Settings.new
    @provider_factory = provider_factory || ->(unit) { WeatherProvider.new(unit: unit) }
    @infos = []
    @all_infos = []
    @current_location_info = nil
    @selected_location = nil
    @loading_count = 0
    @loading_listeners = []
    @selected_listeners = []
    @save_queued = false
    @list_store = Gio::ListStore.new(WeatherInfo)

    @settings.watch('temperature-unit') { rebuild_providers }
  end

  # --- The list the popover shows -------------------------------------------

  def length = @all_infos.length

  # Upstream's getAll: the current location and the selected location come
  # first, in that order, and neither appears twice.
  def all
    @infos.reject { |info| current_location?(info) || selected_location?(info) }.then do |rest|
      rest.tap do |infos|
        if @current_location_info
          infos.unshift(@current_location_info)
        end

        if @selected_location && @current_location_info != @selected_location
          infos.unshift(@selected_location)
        end

        @all_infos = infos
      end
    end
  end

  def at_index(index) = all[index]

  def current_location = @current_location_info

  def recent = @infos.first

  # --- Loading state --------------------------------------------------------

  def loading? = @loading_count.positive?

  # Upstream's notify::loading. The application marks itself busy on it and the
  # window uses it to decide when a freshly opened window is ready.
  def on_loading_changed(&block)
    @loading_listeners << block
    block
  end

  # Upstream's 'selected-location-changed' signal, which the popover connects to
  # in order to send the window to the newly chosen place.
  def on_selected_location_changed(&block)
    @selected_listeners << block
    block
  end

  # --- Loading and saving ---------------------------------------------------

  # Upstream's load(): read the saved locations, truncate the list to ten,
  # rebuild an info for each one newest-last so the newest ends up first, and
  # select the last one built.
  def load
    saved_records.then do |records|
      records.reverse_each.map { |record| Location.deserialize(record) }
             .compact
             .map { |location| add_location_internal(location) }
             .last
             .then do |info|
        if info
          set_selected_location(info)
        end

        invalidate
      end
    end
  end

  def saved_records
    @settings.locations.then do |records|
      if records.length > MAX_LOCATIONS
        records.first(MAX_LOCATIONS).compact.tap { |kept| @settings.locations = kept }
      else
        records.compact
      end
    end
  end

  # Upstream's updateInfo: start a fetch, counting it while it runs so the
  # loading flag reflects how many are outstanding.
  def update_info(info)
    unless info.updating?
      update_loading_count(+1)
      info.connect_updated(once: true) { update_loading_count(-1) }
      info.update
    end
  end

  def set_selected_location(info)
    add_new_location(info.location).tap do |new_info|
      @selected_location = new_info
      @selected_listeners.each { |block| block.call(new_info) }
    end
  end

  def selected_location?(info) = !@selected_location.nil? && @selected_location.equal?(info)

  def current_location?(info) = !@current_location_info.nil? && @current_location_info.equal?(info)

  def add_new_location(new_location)
    add_location_internal(new_location).tap do |info|
      @selected_location = info
      invalidate
      queue_save_settings
    end
  end

  # Upstream's addCurrentLocation, called by the geolocation controller: the
  # place becomes the current location, and an existing entry for it is reused
  # rather than duplicated.
  def current_location_changed(location)
    if location
      existing = @infos.find { |info| info.location.same_as?(location) }

      if existing
        @current_location_info = existing
      else
        @current_location_info = build_info(location)
        add_info_internal(@current_location_info)
      end

      invalidate
    end
  end

  def remove_location(old_info)
    if old_info
      @infos.delete(old_info)

      if @current_location_info.equal?(old_info)
        @current_location_info = nil
      end

      if @selected_location.equal?(old_info)
        @selected_location = nil
      end

      invalidate
      queue_save_settings
    end
  end

  def build_info(location)
    WeatherInfo.new(
      location: location,
      provider: provider,
    )
  end

  def provider = @provider_factory.call(@settings.real_temperature_unit)

  # Upstream's saveSettingsNow, called from vfunc_shutdown: a write still
  # sitting on the idle queue has to happen before the process goes away.
  def save_settings_now
    if @save_queued
      @save_queued = false
      save_settings_internal
    end
  end

  private

    def add_location_internal(new_location)
      @infos.find { |info| info.location.same_as?(new_location) }.then do |existing|
        if existing
          existing
        else
          build_info(new_location).tap { |info| add_info_internal(info) }
        end
      end
    end

    def add_info_internal(info)
      @infos.unshift(info)
      update_info(info)

      if @infos.length > MAX_LOCATIONS
        remove_location(@infos.last)
      end
    end

    # Upstream calls items_changed on itself here. The store is rebuilt instead,
    # which is what a bind_model'd list box needs to see the new order.
    def invalidate
      all.then do |infos|
        @list_store.remove_all
        infos.each { |info| @list_store.append(info) }
      end
    end

    def update_loading_count(delta)
      loading?.then do |was_loading|
        @loading_count += delta
        unless was_loading == loading?
          @loading_listeners.each { |block| block.call(loading?) }
        end
      end
    end

    def queue_save_settings
      unless @save_queued
        @save_queued = true

        GLib::Idle.add do
          @save_queued = false
          save_settings_internal
          false
        end
      end
    end

    # The current location is left out: it comes from geolocation on every run,
    # so saving it would turn a place the user passed through into a place they
    # asked to keep.
    def save_settings_internal
      @all_infos.reject { |info| current_location?(info) }
                .map { |info| info.location.serialize }
                .then { |records| @settings.locations = records }
    end

    # A unit change has to reach the providers, since the unit is part of each
    # request. Upstream has nothing to do here — libgweather reads the unit out
    # of GSettings itself when it formats a value.
    def rebuild_providers
      @infos.each do |info|
        info.provider = provider
        update_info(info)
      end
    end
end
