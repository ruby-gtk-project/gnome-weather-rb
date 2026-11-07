# frozen_string_literal: true

require_relative '../lib/weather_provider'

# FakeProvider answers from a canned forecast instead of the network, so the
# tests can drive the app on a machine with no connection and get the same
# readings every run.
#
# The shape is exactly what WeatherProvider#fetch returns: an offset, a current
# reading, and an hourly series.
class FakeProvider
  OFFSET = 3600
  HOURS = 72

  # fail_for names places whose fetch raises instead of answering, so a test
  # can exercise the "could not load" path WeatherInfo falls back to (see
  # lib/weather_info.rb's #fetch_quietly) without touching the real network.
  def initialize(unit: 'centigrade', offset: OFFSET, hours: HOURS, fail_for: [])
    @unit = unit
    @offset = offset
    @hours = hours
    @fail_for = fail_for
  end

  def fetch(location)
    if @fail_for.include?(location.name)
      raise "simulated network failure for #{location.name}"
    end

    {
      utc_offset: @offset,
      current:    reading(0),
      hourly:     (0...@hours).map { |hour| reading(hour) },
    }
  end

  private

    def start
      @start ||= Time.now.getlocal(@offset).then do |now|
        Time.new(
          now.year,
          now.month,
          now.day,
          now.hour,
          0,
          0,
          @offset,
        )
      end
    end

    # A sine-ish day so the chart and the thermometers have something with a
    # shape to draw, and so each day's range differs from the week's.
    def reading(hour)
      Reading.new(
        time:           start + (hour * 3600),
        temperature:    temperature(hour),
        apparent:       temperature(hour) - 1.5,
        humidity:       60 + ((hour % 7) * 2),
        wind_speed:     3.2 + ((hour % 5) * 0.4),
        wind_direction: (hour * 37) % 360,
        code:           [0, 1, 2, 3, 61, 80, 95].fetch(hour % 7),
        day:            ((start + (hour * 3600)).hour).between?(7, 19),
      )
    end

    def temperature(hour)
      12 + (8 * Math.sin((hour / 24.0) * 2 * Math::PI)) + (hour / 24.0)
    end
end
