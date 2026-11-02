# frozen_string_literal: true

require 'adwaita'

require_relative 'gnome/weather/rb/version'
require_relative 'settings'
require_relative 'styles'
require_relative 'world_model'
require_relative 'window'

# App is the main application class.
#
# Ported from upstream's src/app/application.ts and src/app/main.ts: the
# application object, the model it loads at startup, the actions it publishes,
# and the window it opens on activation.
#
# What upstream does and this port does not, yet:
#
#   * dbus_register/dbus_unregister, which export the shell weather
#     integration — src/app/shell.ts is not ported yet
#   * the show-location and show-search actions, which exist for the shell
#     search provider to call into a running instance — src/service is not
#     ported yet
#
# Adwaita::Application is broken in the Ruby bindings, so the application
# object is a Gtk::Application and only the window is Adwaita's. Everything
# upstream puts in vfunc_startup/vfunc_activate/vfunc_shutdown hangs off the
# matching signal here.
#
class App
  APP_ID = 'org.gnome.WeatherRb'
  VERSION = Gnome::Weather::Rb::VERSION

  APP_ACTIONS = {
    'quit' => ['<Control>q'],
  }.freeze

  WINDOW_CLOSE_ACCELS = ['<Control>w'].freeze

  TEMPERATURE_UNIT = 'temperature-unit'

  def initialize(settings: nil)
    @settings = settings || Settings.new
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
      Gtk::Application.new(APP_ID, :default_flags)
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
    )
  end

  private

    # Upstream's vfunc_startup: the stylesheet, the saved locations, the busy
    # cursor while they load, and the actions.
    def on_startup
      GLib.application_name = 'Weather'
      Gtk::Window.default_icon_name = Window::ICON_NAME

      styles.build
      setup_actions

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
      window.tap do |win|
        win.build
        win.show_default
        win.present
      end
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

    def action_quit = app.quit
end
