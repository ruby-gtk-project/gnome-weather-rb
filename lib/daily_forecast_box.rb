# frozen_string_literal: true

require 'adwaita'
require 'date'
require_relative 'day_entry'
require_relative 'thermometer'
require_relative 'util'

# DailyForecastBox is the daily page of the forecast card: one entry per day,
# starting tomorrow.
#
# Ported from the DailyForecastBox class in upstream's
# src/app/dailyForecast.ts. The preprocessing is the same: skip forward to
# tomorrow, group the forecast readings by the day they fall on, take the
# week's highest and lowest temperature across all of them (which is what every
# thermometer is scaled against), and give each day's entry the reading nearest
# each of the five times of day.
#
# One day on its own is treated as no forecast at all, exactly as upstream
# does — a single column cannot show a trend.
#
class DailyForecastBox < Gtk::Box
  SPACING = 18

  def initialize
    super(:horizontal, 0)
    self.name = 'daily-forecast-box'
    self.halign = :start
  end

  def build = self

  def update(info)
    preprocess(info.forecast_list).then do |forecast|
      if forecast[:days].length > 1
        forecast[:days].each do |day|
          append(build_day_entry(day, forecast[:week_high], forecast[:week_low]))
          append(separator)
        end
      else
        prepend(unavailable_label)
      end
    end
  end

  def clear
    while first_child
      remove(first_child)
    end
  end

  # Memoized widget methods

  def unavailable_label
    @unavailable_label ||= Gtk::Label.new('Forecast not Available').tap do |label|
      label.use_markup = true
      label.hexpand = true
      label.vexpand = true
      label.margin_start = SPACING
      label.margin_end = SPACING
      label.margin_top = SPACING
      label.margin_bottom = SPACING
    end
  end

  private

    def separator = Gtk::Separator.new(:vertical)

    # Upstream's preprocess: readings before tomorrow are dropped, the rest are
    # grouped into days, and the week's extremes come from everything kept.
    def preprocess(infos)
      infos.select { |info| info.update_time }.then do |readings|
        tomorrow_onwards(readings).then do |kept|
          kept.group_by { |info| info.update_time.to_date }
              .sort_by { |date, _| date }
              .map { |date, day_infos| day_group(date, day_infos) }
              .then do |days|
                {
                  days:      days,
                  week_high: temperatures(kept).max,
                  week_low:  temperatures(kept).min,
                }
              end
        end
      end
    end

    def tomorrow_onwards(readings)
      readings.first.then do |first|
        if first
          (first.update_time.to_date + 1).then do |tomorrow|
            readings.select { |info| info.update_time.to_date >= tomorrow }
          end
        else
          []
        end
      end
    end

    def temperatures(infos) = infos.map { |info| Util.temp(info) }.compact

    # The offset travels with the group: the readings are timestamped in the
    # location's own offset, and the five times of day have to be read in that
    # offset rather than this machine's.
    def day_group(date, day_infos)
      {
        day:    date,
        offset: day_infos.first.update_time.utc_offset,
        infos:  day_infos,
      }
    end

    # Upstream's buildDayEntry: the day's own range, and the reading closest to
    # each of the five times of day — midday standing in for "the day" as a
    # whole, which is the reading the entry's icon comes from.
    def build_day_entry(day_infos, week_high, week_low)
      day_infos[:infos].then do |infos|
        noon_of(day_infos[:day], day_infos[:offset]).then do |datetime|
          DayEntry.new(
            datetime: datetime,
            range:    range_for(infos, week_high, week_low),
            infos:    period_infos(infos, datetime),
          ).build
        end
      end
    end

    def range_for(infos, week_high, week_low)
      temperatures(infos).then do |temps|
        TemperatureRange.new(
          daily_low:   temps.min || week_low,
          daily_high:  temps.max || week_high,
          weekly_low:  week_low,
          weekly_high: week_high,
        )
      end
    end

    # Midday on the given date, in the timezone the readings carry, so the
    # five period times are that location's times of day.
    def noon_of(date, offset)
      Time.new(
        date.year,
        date.month,
        date.day,
        Util::DAY,
        0,
        0,
        offset,
      )
    end

    def period_infos(infos, datetime)
      {
        day:       nearest(infos, Util.day(datetime)),
        night:     nearest(infos, Util.night(datetime)),
        morning:   nearest(infos, Util.morning(datetime)),
        afternoon: nearest(infos, Util.afternoon(datetime)),
        evening:   nearest(infos, Util.evening(datetime)),
      }
    end

    def nearest(infos, time)
      infos.min_by { |info| (info.update_time - time).abs }
    end
end
