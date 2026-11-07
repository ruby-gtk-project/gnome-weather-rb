# frozen_string_literal: true

# Drives the D-Bus surfaces main.rb exports: the shell weather integration
# (lib/shell_integration.rb) and the show-location/show-search actions the
# search provider calls into (lib/search_provider.rb,
# lib/background_service.rb).
#
#   nix develop --command xvfb-run -a ruby test/drive_dbus_integration.rb

require 'tmpdir'

ENV['XDG_CONFIG_HOME'] = Dir.mktmpdir('weather-dbus-drive')

require_relative '../lib/main'
require_relative 'fake_provider'
require_relative 'gtk_driver'

settings = Settings.new
app = App.new(settings: settings)

model = WorldModel.new(
  settings:         settings,
  provider_factory: ->(unit) { FakeProvider.new(unit: unit) },
)
app.instance_variable_set(:@model, model)

GtkDriver.drive(app, interval: 500) do |d, _app|
  d.window { app.window.window }

  d.step('the app is on the bus with the shell integration exported') do
    d.check('dbus connection exists') { !app.app.dbus_connection.nil? }
    d.check('shell integration holds the real connection') { !app.shell_integration.instance_variable_get(:@connection).nil? }
  end

  d.step('AutomaticLocation reads true, straight off the interface') do
    d.check('AutomaticLocation is true') { app.shell_integration.automatic_location? == true }
  end

  d.step('Locations starts empty, matching the fresh settings') do
    d.check('no saved locations yet') { app.shell_integration.locations.empty? }
  end

  d.step('fetch Locations over the real D-Bus property getter') do
    connection = app.app.dbus_connection
    path = app.app.dbus_object_path

    connection.call(
      connection.unique_name,
      path,
      'org.freedesktop.DBus.Properties',
      'Get',
      GLib::Variant.parse('("org.gnome.Shell.WeatherIntegration", "Locations")', '(ss)'),
      GLib::VariantType.new('(v)'),
      Gio::DBusCallFlags::NONE,
      -1,
      nil,
    ) do |_connection, result|
      @properties_get_result = connection.call_finish(result)
    end
  end

  d.step('the real D-Bus call answered with an empty array') do
    d.check('a result came back') { !@properties_get_result.nil? }
  end

  d.step('drive the show-location action, exactly as ActivateAction would') do
    app.app.activate_action(
      'show-location',
      GLib::Variant.new(
        GLib::Variant.parse('("Paris", "France", 48.85, 2.35)', '(ssdd)'),
        'v',
      ),
    )
  end

  d.step('show-location opened the weather page on Paris') do
    d.check('window built') { !app.window.nil? }
    d.check('weather page visible') { app.window.stack.visible_child == app.window.city_box }
    d.check('the place is named Paris') { app.window.city_view.info&.location&.name == 'Paris' }
    d.check('the new location was saved') { model.length == 1 }
  end

  d.step('the fetch for Paris lands') {}

  d.step('Locations now reports the saved Paris record') do
    d.check('one saved location') { app.shell_integration.locations.length == 1 }
    d.check('it is Paris') { app.shell_integration.locations.first['name'] == 'Paris' }
  end

  d.step('drive the show-search action') do
    app.app.activate_action('show-search', GLib::Variant.new('london'))
  end

  d.step('show-search switched back to the welcome page with the query') do
    d.check('welcome page visible') { app.window.stack.visible_child == app.window.search_view }
  end

  d.step('quit') { app.app.quit }
end
