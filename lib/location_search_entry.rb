# frozen_string_literal: true

require 'adwaita'
require_relative 'location'
require_relative 'location_row'
require_relative 'util'

# LocationSearchEntry is the search field at the top of the places popover,
# together with the list of matches it drives.
#
# Ported from upstream's src/app/entry.ts, which is three objects in one file:
# a Gio.ListModel holding every city, a Gtk.Filter matching the typed text
# against it, and the Adw.Bin pairing the entry with a Gtk.ListView.
#
# The model/filter/selection chain is the same here:
#
#   ListStore (every city) -> FilterListModel -> SingleSelection -> ListView
#
# with two substitutions. The custom Gtk.Filter subclass is a
# Gtk::CustomFilter, because the Ruby bindings cannot override vfunc_match; and
# the city list is loaded from Location::CITIES rather than walked out of the
# GWeather location tree. The load still happens on an idle callback, as
# upstream does, so a cold start is not held up by it.
#
# The search is accent- and case-insensitive: both sides go through
# Util.normalize_casefold_and_unaccent, so "zurich" finds "Zürich". Upstream
# compares lower-cased names only.
#
class LocationSearchEntry
  def initialize
    @query = ''
    @loaded = false
  end

  def build
    entry.tap do |widget|
      widget.signal_connect('search-changed') do |source|
        filter_for(source.text)
        @on_search_updated&.call(source.text)
      end

      selection_model.signal_connect('notify::selected') do |model|
        model.selected_item.then do |location|
          if location.is_a?(Location)
            @on_location&.call(location)
          end
        end
      end

      GLib::Idle.add do
        load_locations
        false
      end
    end
  end

  # Upstream's 'search-updated' signal: the popover swaps its stack between the
  # saved list and the search results on it.
  def on_search_updated(&block)
    @on_search_updated = block
  end

  # Upstream's notify::location: a row in the search results was picked.
  def on_location_selected(&block)
    @on_location = block
  end

  # Upstream's setListView: the view belongs to the popover's .ui file, so the
  # entry is handed it and installs its own model and factory on it.
  def attach(list_view)
    list_view.tap do |view|
      view.factory = factory
      view.model = selection_model
    end
  end

  def text = entry.text

  def text=(value)
    entry.text = value.to_s
  end

  def grab_focus = entry.grab_focus

  # Memoized widget methods

  def entry
    @entry ||= Gtk::SearchEntry.new.tap do |widget|
      widget.name = 'locationEntry'
      widget.hexpand = true
      widget.placeholder_text = 'Search for a city'
    end
  end

  def list_store = @list_store ||= Gio::ListStore.new(Location)

  # An empty query matches nothing, exactly as upstream's vfunc_match does: the
  # search list is only ever shown once something has been typed.
  def location_filter
    @location_filter ||= Gtk::CustomFilter.new do |location|
      @query.empty? ? false : location.search_key.include?(@query)
    end
  end

  def filter_model
    @filter_model ||= Gtk::FilterListModel.new(list_store, location_filter).tap do |model|
      model.incremental = true
    end
  end

  # GTK reports "nothing selected" as GTK_INVALID_LIST_POSITION, a very large
  # unsigned integer rather than nil; starting there with autoselect off is what
  # keeps the first match from being chosen before the user picks it.
  INVALID_POSITION = 0xFFFFFFFF

  def selection_model
    @selection_model ||= Gtk::SingleSelection.new(filter_model).tap do |model|
      model.autoselect = false
      model.can_unselect = true
      model.selected = INVALID_POSITION
    end
  end

  def factory
    @factory ||= Gtk::SignalListItemFactory.new.tap do |f|
      f.signal_connect('setup') { |_, item| item.child = LocationRow.new.build }

      f.signal_connect('bind') do |_, item|
        item.item.then do |location|
          item.child.tap do |row|
            row.location_name = location.name
            row.country_name = Util.name_and_country(location)[1].to_s
          end
        end
      end
    end
  end

  private

    def filter_for(text)
      @query = Util.normalize_casefold_and_unaccent(text)
      location_filter.changed(:different)
    end

    def load_locations
      unless @loaded
        @loaded = true
        Location.world.each { |location| list_store.append(location) }
      end
    end
end
