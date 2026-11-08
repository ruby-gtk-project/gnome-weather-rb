# frozen_string_literal: true

require 'glib2'
require 'adwaita'

require_relative 'gnome/weather/rb/version'
require_relative 'settings'
require_relative 'styles'
require_relative 'location'
require_relative 'world_model'
require_relative 'window'
require_relative 'shell_integration'

# App is the main application class.
#
# Ported from upstream's src/app/application.ts and src/app/main.ts: the
# application object, the model it loads at startup, the actions it publishes,
# and the window it opens on activation.
#
# The show-location and show-search actions exist for lib/search_provider.rb
# (running in the separate service process of lib/background_service.rb) to
# call into a running instance of this app over org.freedesktop.Application's
# ActivateAction, exactly as upstream's searchProvider.ts does.
#
# show-location's parameter is a tuple of (name, country, latitude,
# longitude) rather than upstream's serialized GWeather.Location: this port's
# Location has no byte-compatible stand-in for gweather_location_serialize(),
# documented in lib/location.rb and lib/shell_integration.rb, so the search
# provider and this action agree on their own flat shape instead. A GVariant
# dictionary (a{sv}, the shape a plain hash would need) cannot be unpacked
# back into Ruby by these bindings when it arrives as an action parameter —
# only a tuple of scalars round-trips — which is the other reason the shape
# is flat rather than a dictionary.
#
# Adwaita::Application is broken in the Ruby bindings, so the application
# object is a Gtk::Application and only the window is Adwaita's. Everything
# upstream puts in vfunc_startup/vfunc_activate/vfunc_shutdown hangs off the
# matching signal here.
#
class App
  APP_ID = 'org.gnome.WeatherRb'

  # Upstream's Devel profile, built by meson as a second application id
  # (`@app_id@.Devel`) with its own desktop file and icon; window.ts reads
  # `pkg.name?.endsWith('Devel')` off that build-time id to add the 'devel'
  # CSS class the Devel icon's own style depends on. This port has no meson
  # profile build to substitute an id at packaging time, so the choice is
  # made at process start instead, off GNOME_WEATHER_APP_ID — unset, or any
  # other value, keeps the normal id.
  DEVEL_APP_ID = "#{APP_ID}.Devel"

  VERSION = Gnome::Weather::Rb::VERSION

  APP_ACTIONS = {
    'quit' => ['<Control>q'],
  }.freeze

  WINDOW_CLOSE_ACCELS = ['<Control>w'].freeze

  TEMPERATURE_UNIT = 'temperature-unit'

  def initialize(settings: nil, devel: ENV['GNOME_WEATHER_APP_ID'] == DEVEL_APP_ID)
    @settings = settings || Settings.new
    @app_id = devel ? DEVEL_APP_ID : APP_ID
  end

  def build
    app.tap do
      app.signal_connect('startup') { on_startup }
      app.signal_connect('activate') { on_activate }
      app.signal_connect('shutdown') { model.save_settings_now }
    end
  end

  def app
    @app ||= begin
      Adwaita.init
      Gtk::Application.new(@app_id, :default_flags)
    end
  end

  def model = @model ||= WorldModel.new(settings: @settings)

  def styles = @styles ||= Styles.new

  def window
    @window ||= Window.new(
      app,
      model,
      @settings,
      version: VERSION,
      app_id:  @app_id,
    )
  end

  def shell_integration = @shell_integration ||= ShellIntegration.new(@settings)

  private

    # Upstream's vfunc_startup: the stylesheet, the saved locations, the busy
    # cursor while they load, and the actions.
    def on_startup
      GLib.application_name = 'Weather'
      Gtk::Window.default_icon_name = Window::ICON_NAME

      styles.build
      setup_actions
      export_shell_integration

      app.mark_busy
      model.on_loading_changed do |loading|
        if loading
          app.mark_busy
        else
          app.unmark_busy
        end
      end
      model.load
      app.unmark_busy
    end

    def on_activate
      ensure_window_built
      window.show_default
      window.present
    end

    def ensure_window_built
      unless @window_built
        window.build
        @window_built = true
      end
    end

    # Upstream's vfunc_dbus_register: the Ruby bindings cannot override that
    # virtual function, so the export happens here instead, off the
    # connection the application has already registered on by 'startup'.
    def export_shell_integration
      shell_integration.export(app.dbus_connection, app.dbus_object_path)
    end

    def setup_actions
      APP_ACTIONS.each do |name, accels|
        Gio::SimpleAction.new(name, nil).tap do |action|
          action.signal_connect('activate') { send(:"action_#{name}") }
          app.add_action(action)
          app.set_accels_for_action("app.#{name}", accels)
        end
      end

      app.set_accels_for_action('window.close', WINDOW_CLOSE_ACCELS)

      add_temperature_unit_action
      add_show_location_action
      add_show_search_action
    end

    # Upstream's showLocationAction: the shell search provider's
    # ActivateResult reaches here, over org.freedesktop.Application.
    def add_show_location_action
      Gio::SimpleAction.new('show-location', GLib::VariantType.new('v')).tap do |action|
        action.signal_connect('activate') { |_, parameter| action_show_location(parameter) }
        app.add_action(action)
      end
    end

    # Upstream's showSearchAction: the shell search provider's LaunchSearch.
    def add_show_search_action
      Gio::SimpleAction.new('show-search', GLib::VariantType.new('s')).tap do |action|
        action.signal_connect('activate') { |_, parameter| action_show_search(parameter) }
        app.add_action(action)
      end
    end

    # Upstream's temperature-unit action, hand-coded there as it is here: a
    # stateful string action, because g_settings_create_action() cannot express
    # the 'default' value and the binding it would need is not introspectable.
    #
    # The difference is where the value lives. Upstream writes
    # org.gnome.GWeather4's key so the whole desktop follows; this port has no
    # GWeather, so the unit is one of its own settings.
    def add_temperature_unit_action
      Gio::SimpleAction.new(
        TEMPERATURE_UNIT,
        GLib::VariantType.new('s'),
        GLib::Variant.new(@settings[TEMPERATURE_UNIT]),
      ).tap do |action|
        # ruby-gnome hands the action parameter over already unwrapped, so this
        # is a Ruby String rather than a GLib::Variant.
        action.signal_connect('activate') { |_, parameter| set_temperature_unit(parameter.to_s) }
        app.add_action(action)
        @settings.watch(TEMPERATURE_UNIT) { |unit| action.state = GLib::Variant.new(unit) }
      end
    end

    def set_temperature_unit(unit)
      if Settings::UNITS.include?(unit)
        @settings[TEMPERATURE_UNIT] = unit
      end
    end

    # Upstream's onShowLocation. parameter deep-unpacks to a plain Ruby Array
    # already — these bindings unwrap a 'v' parameter carrying a tuple of
    # scalars down to native Ruby, with no GLib::Variant left to unpack by
    # hand.
    def action_show_location(parameter)
      Array(parameter).then do |(name, country, latitude, longitude)|
        model.add_new_location(
          Location.new(name: name.to_s, country_name: country.to_s, latitude: latitude, longitude: longitude),
        ).then do |info|
          ensure_window_built
          window.show_info(info)
          window.present
        end
      end
    end

    # Upstream's onShowSearch.
    def action_show_search(parameter)
      ensure_window_built
      window.show_search(parameter.to_s)
      window.present
    end

    def action_quit = app.quit
end
