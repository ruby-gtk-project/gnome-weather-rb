# frozen_string_literal: true

# Drives lib/background_service.rb and lib/search_provider.rb for real: both
# processes' D-Bus surfaces, in one process sharing one GLib main loop (the
# windowed app and the service are two distinct Gio::Application objects
# with distinct application ids, which can coexist on one connection the way
# two real OS processes would on the bus).
#
# A real client calls org.gnome.Shell.SearchProvider2 on the service over the
# session bus, and the service's ActivateResult reaches the real windowed
# app's show-location action over org.freedesktop.Application.ActivateAction
# — the same two hops GNOME Shell and gnome-weather make in production.
#
#   nix develop --command xvfb-run -a ruby test/drive_background_service.rb

require 'tmpdir'

ENV['XDG_CONFIG_HOME'] = Dir.mktmpdir('weather-service-drive')

require_relative '../lib/main'
require_relative '../lib/background_service'
require_relative 'fake_provider'

settings = Settings.new

app = App.new(settings: settings)
app.instance_variable_set(
  :@model,
  WorldModel.new(settings: settings, provider_factory: ->(unit) { FakeProvider.new(unit: unit) }),
)

service = BackgroundService.new(settings: settings)
service.instance_variable_set(
  :@model,
  WorldModel.new(settings: settings, provider_factory: ->(unit) { FakeProvider.new(unit: unit) }),
)
service.model.add_new_location(Location.world.find { |city| city.name == 'London' })
service.model.add_new_location(Location.world.find { |city| city.name == 'Paris' })

$checks = 0
$failures = []

def check(description)
  $checks += 1
  yield.then do |ok|
    puts(ok ? "  ok   #{description}" : "  FAIL #{description}")
    unless ok
      $failures << description
    end
    ok
  end
rescue StandardError => e
  puts "  FAIL #{description} (#{e.class}: #{e.message})"
  $failures << description
  false
end

loop = GLib::MainLoop.new(nil, false)

built_app = app.build
built_app.signal_connect('activate') { nil }

built_service = service.build
built_service.signal_connect('activate') { nil }

# register(nil) fires 'startup' on its own for a primary instance (the signal
# App#build and BackgroundService#build already connected), which does both
# processes' D-Bus exports without blocking this script in either app's own
# run loop.
built_app.register(nil)
built_service.register(nil)

client_connection = Gio::Application.new('org.example.SearchProviderClient', Gio::ApplicationFlags::DEFAULT_FLAGS)
                                    .tap { |a| a.register(nil) }
                                    .dbus_connection

SERVICE_NAME = BackgroundService::APP_ID
SERVICE_PATH = '/org/gnome/WeatherRb/SearchProvider'

# Each step is async (a blocking call_sync from this same thread would
# deadlock the very loop that has to deliver its own reply), so the sequence
# is a chain of completion callbacks rather than a straight line of calls.
def async_call(connection, name, path, interface, method_name, parameters, reply_type, &on_done)
  connection.call(name, path, interface, method_name, parameters, reply_type, Gio::DBusCallFlags::NONE, -1, nil) do |c, r|
    on_done.call(c.call_finish(r))
  end
end

GLib::Timeout.add(500) do
  async_call(
    client_connection,
    SERVICE_NAME,
    SERVICE_PATH,
    'org.gnome.Shell.SearchProvider2',
    'GetInitialResultSet',
    GLib::Variant.parse('(["paris"],)', '(as)'),
    GLib::VariantType.new('(as)'),
  ) do |initial_result|
    # call_finish hands back the reply tuple already deep-unpacked to native
    # Ruby by these bindings, not a GLib::Variant to pick apart by hand.
    ids = initial_result.first
    # WorldModel#all puts the most recently selected location first (Paris,
    # added after London), so Paris is index 0, not 1.
    check('GetInitialResultSet over the real bus found one result') { ids == ['0'] }

    # GetResultMetas's own reply (aa{sv}, a dictionary nested in an array) is
    # not exercised over this real connection: these bindings cannot
    # deep-unpack a GVariant dictionary back to Ruby at all (confirmed with
    # a minimal reproduction — any aa{sv}/a{sv} reply crashes call_finish with
    # "TODO: GVariant({sv}) -> Ruby"), which would break every search
    # provider's GetResultMetas caller in this same way, not just this one.
    # test/check_search_provider.rb exercises #result_metas directly instead,
    # the same content this method puts into that reply.
    async_call(
      client_connection,
      SERVICE_NAME,
      SERVICE_PATH,
      'org.gnome.Shell.SearchProvider2',
      'ActivateResult',
      GLib::Variant.parse('("0", [], 0)', '(sasu)'),
      nil,
    ) { nil }
  end

  false
end

GLib::Timeout.add(3500) do
  check('ActivateResult reached the windowed app over ActivateAction') do
    app.window.stack.visible_child == app.window.city_box && app.window.city_view.info&.location&.name == 'Paris'
  end

  loop.quit
  false
end

GLib::Timeout.add(10_000) { loop.quit; false }
loop.run

puts
puts "#{$checks - $failures.length} of #{$checks} checks passed"
$failures.each { |failure| puts "  failed: #{failure}" }
puts($failures.empty? ? 'DRIVE OK' : 'DRIVE FAILED')
exit($failures.empty? ? 0 : 1)
