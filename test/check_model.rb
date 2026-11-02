# frozen_string_literal: true

# Plain checks on the non-widget half of the port: the settings file, the
# location database, the provider's parsing and the world model's bookkeeping.
#
# No main loop and no widgets, but still a display: Location is a GLib::Object
# so that the search list can be a Gio::ListStore, and requiring gtk4 fails
# outright without one.
#
#   nix develop --command xvfb-run -a ruby test/check_model.rb

require 'json'
require 'tmpdir'

ENV['XDG_CONFIG_HOME'] = Dir.mktmpdir('weather-check')

require_relative '../lib/settings'
require_relative '../lib/location'
require_relative '../lib/util'
require_relative '../lib/weather_provider'
require_relative '../lib/weather_info'
require_relative '../lib/world_model'
require_relative 'fake_provider'

$failures = []
$checks = 0

def check(description)
  $checks += 1
  yield.then do |ok|
    puts(ok ? "  ok   #{description}" : "  FAIL #{description}")
    unless ok
      $failures << description
    end
  end
rescue StandardError => e
  puts "  FAIL #{description} (#{e.class}: #{e.message})"
  $failures << description
end

puts 'Util'
check('casefold and unaccent') { Util.normalize_casefold_and_unaccent('Zürich') == 'zurich' }
check('empty input is an empty string') { Util.normalize_casefold_and_unaccent(nil) == '' }
check('temperatures round to a degree sign') { Util.format_temperature(12.6) == '13°' }
check('a missing temperature formats as nothing') { Util.format_temperature(nil) == '' }
check('ease-out-cubic starts at zero') { Util.ease_out_cubic(0).zero? }
check('ease-out-cubic ends at one') { Util.ease_out_cubic(1) == 1 }
check('the five times of day are the right hours') do
  Time.new(
    2026,
    11,
    2,
    15,
    30,
    0,
    0,
  ).then do |time|
    [Util.night(time), Util.morning(time), Util.day(time), Util.afternoon(time), Util.evening(time)]
      .map(&:hour) == [2, 7, 12, 17, 22]
  end
end

puts 'Location'
check('the database has cities in it') { Location.world.length > 100 }
check('every city has coordinates') do
  Location.world.all? { |city| city.latitude.abs <= 90 && city.longitude.abs <= 180 }
end
check('a location survives a round trip') do
  Location.world.first.then do |city|
    Location.deserialize(JSON.parse(JSON.generate(city.serialize))).same_as?(city)
  end
end
check('rubbish does not deserialize') { Location.deserialize({ 'nope' => 1 }).nil? }
check('a search key folds the country in too') do
  Location.world.find { |city| city.name == 'Zürich' }.search_key.include?('zurich switzerland')
end
check('name and country reads both fields') do
  Util.name_and_country(Location.world.find { |city| city.name == 'London' }) ==
    ['London', 'United Kingdom']
end

puts 'Settings'
settings = Settings.new(path: File.join(Dir.mktmpdir, 'settings.json'))
check('defaults are upstream\'s') { settings['window-width'] == 1050 && settings['window-height'] == 650 }
check('locations start empty') { settings.locations.empty? }
check('a write is readable back from disk') do
  settings.locations = [Location.world.first.serialize]
  Settings.new(path: settings.location).locations.length == 1
end
check('a watcher sees a change') do
  seen = []
  settings.watch('temperature-unit') { |unit| seen << unit }
  settings['temperature-unit'] = 'fahrenheit'
  seen == ['fahrenheit']
end
check('the real unit resolves a named unit') { settings.real_temperature_unit == 'fahrenheit' }

puts 'WeatherProvider'
provider = WeatherProvider.new(unit: 'fahrenheit')
check('the request asks for the chosen unit') do
  provider.url_for(Location.world.first).query.include?('temperature_unit=fahrenheit')
end
check('the request asks for the location timezone') do
  provider.url_for(Location.world.first).query.include?('timezone=auto')
end
check('a WMO code maps to an icon and a condition') do
  WeatherProvider.describe(95) == ['weather-storm', 'Thunderstorm', 'Overcast']
end
check('an unknown code falls back') { WeatherProvider.describe(1234).first == 'weather-severe-alert' }

body = {
  'utc_offset_seconds' => 7200,
  'current'            => {
    'time'                 => '2026-11-02T15:00',
    'temperature_2m'       => 14.2,
    'apparent_temperature' => 12.8,
    'relative_humidity_2m' => 71,
    'wind_speed_10m'       => 4.5,
    'wind_direction_10m'   => 270,
    'weather_code'         => 61,
    'is_day'               => 1,
  },
  'hourly'             => {
    'time'                 => ['2026-11-02T15:00', '2026-11-02T16:00'],
    'temperature_2m'       => [14.2, 13.1],
    'apparent_temperature' => [12.8, 11.9],
    'relative_humidity_2m' => [71, 73],
    'wind_speed_10m'       => [4.5, 4.1],
    'wind_direction_10m'   => [270, 280],
    'weather_code'         => [61, 3],
    'is_day'               => [1, 0],
  },
}

parsed = provider.send(:parse, body)
check('the current reading is parsed') { parsed[:current].temperature == 14.2 }
check('the timestamp keeps the location offset') { parsed[:current].time.utc_offset == 7200 }
check('the hourly series is parsed') { parsed[:hourly].length == 2 }
check('a night hour is marked as night') { parsed[:hourly].last.day? == false }
check('a bearing becomes a compass point') { parsed[:current].wind_direction_label == 'W' }

puts 'WeatherInfo'
info = WeatherInfo.new(location: Location.world.first, reading: parsed[:current])
check('a reading makes the info valid') { info.valid? }
check('the icon comes from the code') { info.icon_name == 'weather-showers-scattered' }
check('a night clear sky gets the night icon') do
  WeatherInfo.new(
    location: Location.world.first,
    reading:  parsed[:hourly].last,
  ).icon_name == 'weather-overcast'
end
check('humidity reads as a percentage') { info.humidity == '71 %' }
check('wind reads as a speed and a bearing') { info.wind == '4.5 m/s W' }
check('conditions follow the code') { Util.weather_conditions(info) == 'Light rain' }

puts 'WorldModel'
model_settings = Settings.new(path: File.join(Dir.mktmpdir, 'settings.json'))
model = WorldModel.new(
  settings:         model_settings,
  provider_factory: ->(unit) { FakeProvider.new(unit: unit) },
)

london = Location.world.find { |city| city.name == 'London' }
paris = Location.world.find { |city| city.name == 'Paris' }

model.add_new_location(london)
check('adding a location fills the model') { model.length == 1 }
check('the same location is not added twice') do
  model.add_new_location(london)
  model.length == 1
end
check('the newest location is the recent one') do
  model.add_new_location(paris)
  model.recent.location.name == 'Paris'
end
check('the selected location sorts first') { model.all.first.location.name == 'Paris' }
check('the list store follows the model') { model.list_store.n_items == model.length }
check('removing a location empties it again') do
  model.remove_location(model.recent)
  model.length == 1
end
check('the model stops at ten locations') do
  Location.world.first(20).each { |city| model.add_new_location(city) }
  model.length <= WorldModel::MAX_LOCATIONS
end
check('saving writes the locations to settings') do
  model.save_settings_now
  model_settings.locations.length == model.length
end
check('a saved model reloads its locations') do
  WorldModel.new(
    settings:         model_settings,
    provider_factory: ->(unit) { FakeProvider.new(unit: unit) },
  ).tap(&:load).length == model.length
end

puts
puts "#{$checks - $failures.length} of #{$checks} checks passed"
$failures.each { |failure| puts "  failed: #{failure}" }
exit($failures.empty? ? 0 : 1)
