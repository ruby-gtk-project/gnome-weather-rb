# frozen_string_literal: true

require 'json'
require 'net/http'
require 'uri'

# Reading is one moment of weather: the shape every label in the app reads.
#
# It stands in for the values GWeather.Info exposes through its getter pairs
# (get_value_temp, get_value_apparent, get_humidity, get_value_wind…), with the
# "did the provider actually report this" flag those pairs return replaced by
# nil for a missing value.
Reading = Data.define(
  :time,
  :temperature,
  :apparent,
  :humidity,
  :wind_speed,
  :wind_direction,
  :code,
  :day,
)

# Reopened rather than configured in the Data.define block: constants assigned
# inside that block bind to the enclosing lexical scope, not to Reading.
class Reading
  def day? = day

  # The compass point a wind bearing falls in. GWeather renders bearings
  # through gweather_wind_direction_to_string(); the eight points below are the
  # resolution a forecast bearing deserves.
  POINTS = %w[N NE E SE S SW W NW].freeze

  def wind_direction_label
    wind_direction.nil? ? '' : POINTS[((wind_direction % 360) / 45.0).round % 8]
  end
end

# WeatherProvider fetches observations and forecasts.
#
# This file has no single counterpart upstream either: it replaces the provider
# half of libgweather. Upstream's WorldModel builds a GWeather.Info with
# METAR | MET_NO | OWM enabled and calls update() on it; libgweather then talks
# to those services and emits 'updated'. With no GWeather typelib available to
# the Ruby bindings, the port talks to a forecast service itself.
#
# Open-Meteo is the service, because it needs no API key and publishes both the
# current conditions and an hourly series — the two things the app draws. Its
# weather codes are WMO codes, which CODES below maps onto the icon names and
# condition strings libgweather would have returned.
#
class WeatherProvider
  ENDPOINT = 'https://api.open-meteo.com/v1/forecast'

  # Seven days of hourly readings: the daily page shows six days plus the rest
  # of today, and the hourly page the next twenty-four hours.
  FORECAST_DAYS = 7

  TIMEOUT = 15

  CURRENT_FIELDS = %w[
    temperature_2m
    apparent_temperature
    relative_humidity_2m
    wind_speed_10m
    wind_direction_10m
    weather_code
    is_day
  ].freeze

  HOURLY_FIELDS = %w[
    temperature_2m
    apparent_temperature
    relative_humidity_2m
    wind_speed_10m
    wind_direction_10m
    weather_code
    is_day
  ].freeze

  UNITS = {
    'centigrade' => 'celsius',
    'fahrenheit' => 'fahrenheit',
  }.freeze

  # WMO weather code -> the icon name, significant conditions and sky state
  # libgweather reports for it.
  #
  # The conditions string is "-" for the codes that describe nothing but the
  # sky, which is exactly the convention Util.weather_conditions keys off: for
  # those, the sky string is the interesting one.
  CODES = {
    0  => ['weather-clear', '-', 'Clear'],
    1  => ['weather-few-clouds', '-', 'Mainly clear'],
    2  => ['weather-few-clouds', '-', 'Partly cloudy'],
    3  => ['weather-overcast', '-', 'Overcast'],
    45 => ['weather-fog', 'Fog', 'Overcast'],
    48 => ['weather-fog', 'Freezing fog', 'Overcast'],
    51 => ['weather-showers-scattered', 'Light drizzle', 'Overcast'],
    53 => ['weather-showers-scattered', 'Drizzle', 'Overcast'],
    55 => ['weather-showers-scattered', 'Heavy drizzle', 'Overcast'],
    56 => ['weather-showers-scattered', 'Light freezing drizzle', 'Overcast'],
    57 => ['weather-showers-scattered', 'Freezing drizzle', 'Overcast'],
    61 => ['weather-showers-scattered', 'Light rain', 'Overcast'],
    63 => ['weather-showers', 'Rain', 'Overcast'],
    65 => ['weather-showers', 'Heavy rain', 'Overcast'],
    66 => ['weather-showers', 'Light freezing rain', 'Overcast'],
    67 => ['weather-showers', 'Freezing rain', 'Overcast'],
    71 => ['weather-snow', 'Light snow', 'Overcast'],
    73 => ['weather-snow', 'Snow', 'Overcast'],
    75 => ['weather-snow', 'Heavy snow', 'Overcast'],
    77 => ['weather-snow', 'Snow grains', 'Overcast'],
    80 => ['weather-showers-scattered', 'Light rain showers', 'Broken clouds'],
    81 => ['weather-showers', 'Rain showers', 'Broken clouds'],
    82 => ['weather-showers', 'Heavy rain showers', 'Broken clouds'],
    85 => ['weather-snow', 'Light snow showers', 'Broken clouds'],
    86 => ['weather-snow', 'Snow showers', 'Broken clouds'],
    95 => ['weather-storm', 'Thunderstorm', 'Overcast'],
    96 => ['weather-storm', 'Thunderstorm with hail', 'Overcast'],
    99 => ['weather-storm', 'Heavy thunderstorm with hail', 'Overcast'],
  }.freeze

  UNKNOWN_CODE = ['weather-severe-alert', 'Unknown', 'Unknown'].freeze

  # Open-Meteo's terms ask for this credit, and upstream has a label for it
  # already: GWeather.Info#get_attribution fills the same one with whichever
  # service answered.
  ATTRIBUTION = 'Weather data by <a href="https://open-meteo.com/">Open-Meteo.com</a>, ' \
                'licensed <a href="https://creativecommons.org/licenses/by/4.0/">CC BY 4.0</a>'

  def self.describe(code) = CODES.fetch(code, UNKNOWN_CODE)

  def initialize(unit: 'centigrade', endpoint: ENDPOINT)
    @unit = unit
    @endpoint = endpoint
  end

  # Returns {utc_offset:, current:, hourly:} for the location, and raises
  # anything net/http raises — the caller (WeatherInfo#update) runs this off the
  # main loop and turns a failure into an empty forecast, the way upstream shows
  # "Forecast not Available" when a provider has nothing.
  def fetch(location)
    parse(request(location))
  end

  def url_for(location)
    URI(@endpoint).tap do |uri|
      uri.query = URI.encode_www_form(
        latitude:         format('%.4f', location.latitude),
        longitude:        format('%.4f', location.longitude),
        timezone:         'auto',
        forecast_days:    FORECAST_DAYS,
        temperature_unit: UNITS.fetch(@unit, 'celsius'),
        wind_speed_unit:  'ms',
        current:          CURRENT_FIELDS.join(','),
        hourly:           HOURLY_FIELDS.join(','),
      )
    end
  end

  private

    def request(location)
      url_for(location).then do |uri|
        Net::HTTP.start(
          uri.host,
          uri.port,
          use_ssl:      true,
          open_timeout: TIMEOUT,
          read_timeout: TIMEOUT,
        ) do |http|
          http.get(uri.request_uri).then do |response|
            unless response.is_a?(Net::HTTPSuccess)
              raise IOError, "#{uri.host} answered #{response.code}"
            end

            JSON.parse(response.body)
          end
        end
      end
    end

    def parse(body)
      body['utc_offset_seconds'].to_i.then do |offset|
        {
          utc_offset: offset,
          current:    current_reading(body['current'], offset),
          hourly:     hourly_readings(body['hourly'], offset),
        }
      end
    end

    def current_reading(current, offset)
      current.then do |values|
        if values
          Reading.new(
            time:           parse_time(values['time'], offset),
            temperature:    values['temperature_2m']&.to_f,
            apparent:       values['apparent_temperature']&.to_f,
            humidity:       values['relative_humidity_2m']&.to_f,
            wind_speed:     values['wind_speed_10m']&.to_f,
            wind_direction: values['wind_direction_10m']&.to_f,
            code:           values['weather_code']&.to_i,
            day:            values['is_day'].to_i == 1,
          )
        end
      end
    end

    def hourly_readings(hourly, offset)
      hourly.then do |values|
        if values && values['time']
          values['time'].each_index.map do |i|
            Reading.new(
              time:           parse_time(values['time'][i], offset),
              temperature:    values.dig('temperature_2m', i)&.to_f,
              apparent:       values.dig('apparent_temperature', i)&.to_f,
              humidity:       values.dig('relative_humidity_2m', i)&.to_f,
              wind_speed:     values.dig('wind_speed_10m', i)&.to_f,
              wind_direction: values.dig('wind_direction_10m', i)&.to_f,
              code:           values.dig('weather_code', i)&.to_i,
              day:            values.dig('is_day', i).to_i == 1,
            )
          end
        else
          []
        end
      end
    end

    # Open-Meteo's timestamps are wall-clock time at the location
    # ("2026-11-02T13:00") and the offset that wall clock runs at comes back
    # alongside them. Pinning the offset onto the Time is what lets the daily
    # forecast group readings by the location's day rather than this machine's.
    def parse_time(stamp, offset)
      stamp.then do |text|
        if text
          Time.new(
            text[0, 4].to_i,
            text[5, 2].to_i,
            text[8, 2].to_i,
            text[11, 2].to_i,
            text[14, 2].to_i,
            0,
            offset,
          )
        end
      end
    end
end
