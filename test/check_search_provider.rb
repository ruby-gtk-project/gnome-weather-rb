# frozen_string_literal: true

# Plain checks on SearchProvider's logic: ranking, subsearch narrowing,
# result metas, and the activate/launch callbacks — the half of
# lib/search_provider.rb that has nothing to do with D-Bus marshaling.
#
# No main loop and no widgets, but still a display: Location is a GLib::Object,
# which requiring gtk4 fails outright without one.
#
#   nix develop --command xvfb-run -a ruby test/check_search_provider.rb

require 'gtk4'

require_relative '../lib/location'
require_relative '../lib/weather_info'
require_relative '../lib/search_provider'

# A WorldModel double: SearchProvider only ever calls #all and #at_index, so a
# plain array stands in rather than the real model's settings-backed machinery.
FakeModel = Struct.new(:infos) do
  def all = infos
  def at_index(index) = infos[index]
  def loading? = false
  def on_loading_changed(&block) = block
end

def info_for(name, country, code: 0)
  WeatherInfo.new(
    location: Location.new(name: name, country_name: country, latitude: 0.0, longitude: 0.0),
    reading:  Reading.new(
      time:           Time.now,
      temperature:    14.0,
      apparent:       12.5,
      humidity:       60,
      wind_speed:     3.2,
      wind_direction: 90,
      code:           code,
      day:            true,
    ),
  )
end

model = FakeModel.new(
  [
    info_for('London', 'United Kingdom'),
    info_for('Paris', 'France'),
    info_for('Rome', 'Italy'),
    info_for('Ealing', 'United Kingdom'),
    info_for('Londonderry', 'United Kingdom'),
  ],
)

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

activated = nil
launched = nil
provider = SearchProvider.new(
  model,
  on_activate_location: ->(location) { activated = location },
  on_launch_search:     ->(text) { launched = text },
)

check('a name match finds both London and Londonderry') { provider.initial_result_set(['london']) == ['0', '4'] }
check('an empty search returns nothing') { provider.initial_result_set([]) == [] }
check('a country-only match still finds every matching place, in order') do
  provider.initial_result_set(['united', 'kingdom']) == ['0', '3', '4']
end
check('a name match ranks before a country-only match, even out of index order') do
  ranking_model = FakeModel.new(
    [
      info_for('Zurich', 'Ontario'),    # index 0: country-only match for "on"
      info_for('London', 'England'),    # index 1: name match for "on"
      info_for('Londonderry', 'United Kingdom'), # index 2: name match for "on"
    ],
  )
  SearchProvider.new(ranking_model).initial_result_set(['on']) == ['1', '2', '0']
end
check('every term must match, so a nonsense term finds nothing') do
  provider.initial_result_set(['london', 'zzz']) == []
end
check('subsearch narrows the previous results') do
  provider.subsearch_result_set(['0', '1'], ['london']) == ['0']
end

metas = provider.result_metas(['1'])
check('result_metas has one entry for Paris') { metas.length == 1 }
check('the meta carries the id') { metas.first['id'] == '1' }
check('the meta names the city') { metas.first['name'] == 'Paris' }
check('the meta describes the conditions and temperature') { metas.first['description'] == 'Clear, 14°' }
check('the meta carries a themed icon variant, matching the widget\'s icon name') do
  icon = metas.first['icon']
  icon.is_a?(GLib::Variant) && icon.to_s == "('themed', <['weather-clear-symbolic', 'weather-clear']>)"
end

check('a query run while the model is loading waits for notify::loading to clear') do
  loading_model = Struct.new(:infos) do
    attr_accessor :loading_flag
    def all = infos
    def at_index(index) = infos[index]
    def loading? = loading_flag
    def on_loading_changed(&block)
      (@listeners ||= []) << block
      block
    end

    def finish_loading!
      self.loading_flag = false
      @listeners.each { |l| l.call(false) }
    end
  end.new(model.infos)
  loading_model.loading_flag = true

  waiting_provider = SearchProvider.new(loading_model)
  result = nil
  waiting_provider.initial_result_set(['london']) { |ids| result = ids }
  still_nil_while_loading = result.nil?
  loading_model.finish_loading!
  still_nil_while_loading && result == ['0', '4']
end

provider.activate_result('1', [], 0)
check('ActivateResult calls back with the Paris location') { activated&.name == 'Paris' }

provider.launch_search(['lon', 'don'], 0)
check('LaunchSearch calls back with the joined terms') { launched == 'lon don' }

puts
puts "#{$checks - $failures.length} of #{$checks} checks passed"
$failures.each { |failure| puts "  failed: #{failure}" }
exit($failures.empty? ? 0 : 1)
