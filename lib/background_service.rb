# frozen_string_literal: true

require 'gio2'
require 'glib2'
require_relative 'world_model'
require_relative 'settings'
require_relative 'search_provider'

# BackgroundService is the process GNOME Shell D-Bus-activates to search this
# app's locations without its window open.
#
# Ported from upstream's src/service/main.ts: a Gio.Application carrying
# IS_SERVICE and an inactivity timeout, hosting the search provider and a
# quit action, with no window of its own — vfunc_activate does nothing there,
# and on_activate here does the same.
#
# Upstream's WeatherBackgroundService keeps its own WorldModel, separate from
# the windowed app's; this port's two processes do the same, each with their
# own WorldModel reading the same Settings file. ActivateResult and
# LaunchSearch reach the windowed app the way upstream's activateAction does:
# a call to org.freedesktop.Application.ActivateAction on the main app's own
# well-known name, not a direct method call — this really is a second
# process, with no object in common.
class BackgroundService
  APP_ID = 'org.gnome.WeatherRb.SearchProvider'
  INACTIVITY_TIMEOUT = 60_000

  MAIN_APP_ID = 'org.gnome.WeatherRb'
  MAIN_APP_PATH = '/org/gnome/WeatherRb'

  def initialize(settings: nil)
    @settings = settings || Settings.new
  end

  def build
    app.tap do |application|
      application.signal_connect('startup') { on_startup }
      application.signal_connect('activate') { on_activate }
      application.signal_connect('shutdown') { model.save_settings_now }
    end
  end

  def app
    @app ||= Gio::Application.new(APP_ID, Gio::ApplicationFlags::IS_SERVICE).tap do |application|
      application.inactivity_timeout = INACTIVITY_TIMEOUT
    end
  end

  def model = @model ||= WorldModel.new(settings: @settings)

  def search_provider
    @search_provider ||= SearchProvider.new(
      model,
      on_activate_location: method(:activate_main_app_location),
      on_launch_search:     method(:launch_main_app_search),
    )
  end

  private

    # Upstream's vfunc_startup: load the model, add the quit action, export
    # the search provider. Upstream's debug branch (logging every city name
    # when not running from a resource bundle) has no equivalent here — this
    # port never runs from a GResource bundle, so it would always be true and
    # would just be startup log noise.
    def on_startup
      GLib.application_name = 'Weather'
      model.load
      add_quit_action
      export_search_provider
    end

    # A background service: nothing to present. Matches upstream's
    # vfunc_activate, which is intentionally empty.
    def on_activate = nil

    def add_quit_action
      Gio::SimpleAction.new('quit', nil).tap do |action|
        action.signal_connect('activate') { app.quit }
        app.add_action(action)
      end
    end

    # Upstream's vfunc_dbus_register: the Ruby bindings cannot override that
    # virtual function, so the export happens here instead, off the
    # connection the application has already registered on by 'startup'.
    def export_search_provider
      search_provider.export(app.dbus_connection, app.dbus_object_path)
    end

    # Upstream's onShowLocation path, reached through
    # WeatherSearchProvider#activateAction: this port's app has no
    # byte-compatible stand-in for gweather_location_serialize() (see
    # lib/location.rb), so the two processes agree on a flat (name, country,
    # latitude, longitude) tuple instead — the same shape App#action_show_location
    # expects, documented in lib/main.rb.
    def activate_main_app_location(location)
      call_main_app_action(
        'show-location',
        format('("%s", "%s", %s, %s)', escape(location.name), escape(location.country_name), location.latitude, location.longitude),
      )
    end

    def launch_main_app_search(text) = call_main_app_action('show-search', "\"#{escape(text)}\"")

    def escape(value) = value.to_s.gsub('\\') { '\\\\' }.gsub('"') { '\\"' }

    # ActivateAction's own signature is (s action_name, av parameter, a{sv}
    # platform_data). parameter is "zero or one value of type v"; since the
    # action on the other end declares its own parameter_type as 'v' too (see
    # lib/main.rb), the payload is wrapped twice — once for the action's own
    # 'v' parameter type, once more for ActivateAction's 'av' transport —
    # which is what upstream's `new GLib.Variant('v', ...)` produces for a
    # GJS variant explicitly typed 'v'. GVariant text's `<<value>>` is that
    # double wrap.
    def call_main_app_action(action_name, value_text)
      app.dbus_connection&.call(
        MAIN_APP_ID,
        MAIN_APP_PATH,
        'org.freedesktop.Application',
        'ActivateAction',
        GLib::Variant.parse(format('("%s", [<<%s>>], @a{sv} {})', action_name, value_text), '(sava{sv})'),
        nil,
        Gio::DBusCallFlags::NONE,
        -1,
        nil,
      ) { |connection, result| connection.call_finish(result) }
    rescue StandardError, GLib::Error => e
      warn "Could not reach the main application: #{e.message}"
    end
end
