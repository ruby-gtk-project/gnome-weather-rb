# frozen_string_literal: true

require 'gtk4'
require_relative 'location'
require_relative 'weather_provider'
require_relative 'util'

# WeatherInfo is the weather at one location.
#
# It stands in for GWeather.Info, the object every widget upstream is handed:
# the same accessors (temp, apparent, icon_name, conditions, humidity, wind,
# attribution, forecast_list), the same update()-then-'updated' cycle, and the
# same is_valid() meaning "there is something to draw".
#
# Two differences from libgweather's object, both forced by its absence:
#
#   * the fetch runs on a Ruby thread and lands back on the main loop through
#     GLib::Idle, since there is no GIO async call to lean on. Nothing touches
#     GTK off the main loop.
#   * a failed fetch still notifies its listeners, with no readings. Upstream
#     leaves the spinner turning when every provider fails; here the page falls
#     through to the "Forecast not Available" state the forecast boxes already
#     have, which is the better of the two when the machine is offline.
#
# A forecast entry is a WeatherInfo too, carrying one reading and no forecast
# list of its own, because that is how upstream's hourly and daily boxes treat
# the entries of get_forecast_list().
#
class WeatherInfo < GLib::Object
  type_register

  attr_reader :location, :reading, :forecast_list

  def initialize(location:, provider: nil, reading: nil, forecast: [])
    super()
    @location = location
    @provider = provider
    @reading = reading
    @forecast_list = forecast
    @listeners = {}
    @next_listener_id = 0
    @updating = false
  end

  # --- The GWeather.Info surface -------------------------------------------

  def valid? = !@reading.nil?

  def updating? = @updating

  def update_time = @reading&.time

  def temp = @reading&.temperature

  def apparent = @reading&.apparent

  # libgweather reports a minimum and a maximum for a forecast period and
  # nothing for an observation. An hourly reading is a single moment, so the
  # pair is absent and Util.temperature falls back to the summary — the same
  # path upstream takes for a provider that reports neither.
  def temp_min = nil

  def temp_max = nil

  def temp_min_string = Util.format_temperature(temp_min)

  def temp_max_string = Util.format_temperature(temp_max)

  def temp_summary = Util.format_temperature(temp)

  def icon_name = WeatherProvider.describe(code).first.then { |name| night_variant(name) }

  def conditions = WeatherProvider.describe(code)[1]

  def sky = WeatherProvider.describe(code)[2]

  def humidity
    @reading&.humidity.then do |value|
      value.nil? ? '' : format('%d %%', value.round)
    end
  end

  # Upstream's DayEntry.setWindInfo prefers the measured speed and falls back
  # to get_wind()'s prose; the same two cases are here, so the fallback has
  # something to be a fallback for.
  def wind
    @reading&.wind_speed.then do |speed|
      if speed
        format('%.1f m/s %s', speed, @reading.wind_direction_label).strip
      else
        'Unknown'
      end
    end
  end

  def wind_speed = @reading&.wind_speed

  def attribution = WeatherProvider::ATTRIBUTION

  # --- Updating -------------------------------------------------------------

  # Upstream's info.connect('updated', ...) / info.disconnect(id). Plain Ruby
  # callbacks rather than a registered GObject signal: the listeners are all
  # inside this process, and WeatherView and WorldModel both need to attach and
  # detach by id.
  # A `once: true` listener is removed as it fires, which is what upstream's
  # WorldModel.updateInfo does by hand: it connects to 'updated' only to learn
  # that this one fetch finished, and disconnects inside the handler.
  def connect_updated(once: false, &block)
    @next_listener_id += 1
    @listeners[@next_listener_id] = { block: block, once: once }
    @next_listener_id
  end

  def disconnect_updated(id)
    @listeners.delete(id)
  end

  # Fetches the weather, then notifies on the main loop. A fetch already in
  # flight is left to finish rather than raced, which is what upstream's
  # _loadingId guard does in WorldModel.updateInfo.
  def update
    unless @updating || @provider.nil?
      @updating = true
      start_fetch
    end
  end

  # The unit is chosen per request by the provider, so a unit change means a
  # fresh provider and a fresh fetch.
  def provider=(provider)
    @provider = provider
  end

  private

    def start_fetch
      Thread.new do
        fetch_quietly.then do |result|
          GLib::Idle.add do
            apply(result)
            false
          end
        end
      end
    end

    # Runs on the fetching thread, so a provider failure cannot escape into the
    # main loop; the nil it returns instead is what apply reads as "no data".
    def fetch_quietly
      @provider.fetch(@location)
    rescue StandardError, Timeout::Error => e
      warn "Could not fetch the weather for #{@location}: #{e.message}"
      nil
    end

    def apply(result)
      @updating = false

      if result
        @reading = result[:current]
        @forecast_list = result[:hourly].map { |reading| forecast_entry(reading) }
      end

      @listeners.to_a.each do |id, listener|
        if listener[:once]
          @listeners.delete(id)
        end

        listener[:block].call(self)
      end
    end

    def forecast_entry(reading)
      self.class.new(location: @location, reading: reading)
    end

    def code = @reading&.code || -1

    # libgweather ships a night variant of the clear and few-clouds icons and
    # picks it from the sun's position; Open-Meteo reports is_day, which is the
    # same question answered by the service.
    NIGHT_VARIANTS = {
      'weather-clear'      => 'weather-clear-night',
      'weather-few-clouds' => 'weather-few-clouds-night',
    }.freeze

    def night_variant(name)
      if @reading&.day? == false
        NIGHT_VARIANTS.fetch(name, name)
      else
        name
      end
    end
end
