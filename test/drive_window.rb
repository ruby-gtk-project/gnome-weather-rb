# frozen_string_literal: true

# Drives the main window: search for a city, watch the weather page fill in,
# switch forecast pages, open the About dialog, refresh, and change the
# temperature unit.
#
# The weather comes from FakeProvider, so this runs with no network.
#
#   nix develop --command xvfb-run -a ruby test/drive_window.rb

require 'tmpdir'

ENV['XDG_CONFIG_HOME'] = Dir.mktmpdir('weather-drive')

require_relative '../lib/main'
require_relative 'fake_provider'
require_relative 'gtk_driver'

settings = Settings.new
app = App.new(settings: settings)

# The model the app builds is memoized, so handing it a fake provider means
# building it here first with the same settings the app will use.
model = WorldModel.new(
  settings:         settings,
  provider_factory: ->(unit) { FakeProvider.new(unit: unit) },
)
app.instance_variable_set(:@model, model)

GtkDriver.drive(app, shots: 'tmp/shots', interval: 700) do |d, _app|
  d.window { app.window.window }

  d.step('the welcome page is showing') do
    d.check('welcome page visible') { app.window.stack.visible_child == app.window.search_view }
    d.check('no saved locations yet') { model.length.zero? }
    d.shot('01-welcome')
  end

  d.step('type a city into the places popover') do
    app.window.search_popover.location_entry.text = 'london'
  end

  d.step('the search list offers matches') do
    app.window.search_popover.location_entry.then do |entry|
      d.check('at least one match') { entry.selection_model.n_items.positive? }
      d.check('the match is London') { entry.selection_model.get_item(0).name == 'London' }
      d.check('search page is showing') do
        app.window.search_popover.stack.visible_child == app.window.search_popover.search_scroll_window
      end
    end
  end

  d.step('pick the first match') do
    app.window.search_popover.location_entry.selection_model.selected = 0
  end

  d.step('the weather page takes over') do
    d.check('weather page visible') { app.window.stack.visible_child == app.window.city_box }
    d.check('the location was saved') { model.length == 1 }
    d.check('refresh is revealed') { app.window.refresh_revealer.reveal_child? }
  end

  d.step('the forecast arrives') do
    app.window.city_view.then do |view|
      d.check('info page is showing') { view.stack.visible_child_name == WeatherView::INFO }
      d.check('the place is named') { view.info_page.places_label.label.start_with?('London') }
      d.check('a temperature is shown') { view.info_page.temperature_label.label.end_with?('°') }
      d.check('an attribution is shown') { view.info_page.attribution_label.label.include?('Open-Meteo') }
      d.check('the update time is shown') { view.info_page.updated_time_label.label.include?('Updated') }
    end
    d.shot('02-hourly')
  end

  d.step('the hourly page has hours in it') do
    app.window.city_view.info_page.forecast_hourly.then do |hourly|
      d.check('hourly entries were built') { hourly.has_forecast_info? }
      d.check('an hour entry is the first child') { hourly.box.first_child.is_a?(HourEntry) }
      d.check('the first hour reads Now') { hourly.box.first_child.time_label.label == 'Now' }
      d.shot('03-hourly-card', hourly)
    end
  end

  d.step('switch to the daily page') do
    app.window.city_view.forecast_stack.visible_child_name = 'daily'
  end

  d.step('the daily page has days in it') do
    app.window.city_view.info_page.forecast_daily.then do |daily|
      d.check('a day entry is the first child') { daily.first_child.is_a?(DayEntry) }
      d.check('the day is named') { !daily.first_child.name_label.label.empty? }
      d.check('the thermometer has a range') { daily.first_child.thermometer.range.is_a?(TemperatureRange) }
      d.shot('04-daily-card', daily)
    end
    d.shot('05-daily')
  end

  d.step('open the day detail popover') do
    app.window.city_view.info_page.forecast_daily.first_child.more_button.popup
  end

  d.step('the detail popover is filled in') do
    app.window.city_view.info_page.forecast_daily.first_child.then do |day|
      d.check('night temperature set') { day.period_temperature(:night).label.end_with?('°') }
      d.check('morning wind set') { day.period_wind(:morning).label.include?('m/s') }
      d.check('evening humidity set') { day.period_humidity(:evening).label.include?('%') }
      d.shot('06-day-popover', day.more_menu.child)
    end
  end

  d.step('open the About dialog') do
    app.window.window.activate_action('about', nil)
  end

  d.step('the About dialog opened') do
    d.check('a dialog is on screen') { !app.window.window.visible_dialog.nil? }
    d.shot('07-about')
  end

  d.step('close the About dialog') do
    app.window.window.visible_dialog&.close
  end

  d.step('refresh the location') do
    app.window.window.activate_action('refresh', nil)
    d.check('back to the spinner') do
      app.window.city_view.stack.visible_child_name == WeatherView::LOADING
    end
  end

  d.step('the refresh lands') do
    d.check('info page is showing again') do
      app.window.city_view.stack.visible_child_name == WeatherView::INFO
    end
  end

  d.step('switch to Fahrenheit') do
    app.app.activate_action('temperature-unit', GLib::Variant.new('fahrenheit'))
  end

  d.step('the unit was recorded') do
    d.check('setting written') { settings['temperature-unit'] == 'fahrenheit' }
    # ruby-gnome unwraps the action's state variant, so this is a String.
    d.check('action state followed') do
      app.app.lookup_action('temperature-unit').state.to_s == 'fahrenheit'
    end
  end

  d.step('open the places popover from the weather page') do
    app.window.city_view.info_page.world_view.popup
  end

  d.step('the saved location is listed') do
    app.window.city_view.info_page.world_view.locations_list_box.then do |list|
      d.check('one saved row') { !list.get_row_at_index(0).nil? }
      d.check('the row names the city') do
        list.get_row_at_index(0).child.name_label.label == 'London'
      end
      d.shot('08-places', list)
    end
  end
end
