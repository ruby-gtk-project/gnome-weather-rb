# frozen_string_literal: true

require 'adwaita'

# Util holds the small helpers the rest of the port shares.
#
# Ported from upstream's src/misc/util.ts. The helpers that exist there to work
# around GJS or GtkBuilder — loadUI, arrayEqual, getSettings — have no job in
# Ruby and are not carried over; everything that formats a value or picks a
# time of day is here, with the same names in snake_case.
#
module Util
  module_function

  # Upstream's getWeatherConditions: "-" means "nothing significant to
  # report", in which case the sky description is the interesting string.
  def weather_conditions(info)
    info.conditions.then do |conditions|
      if conditions == '-'
        info.sky
      else
        conditions
      end
    end
  end

  # Upstream's normalizeCasefoldAndUnaccent, the function that has travelled
  # all over GNOME: decompose to NFKD, casefold, then drop the combining
  # diacritical marks so "Zürich" matches a search for "zurich".
  #
  #   Basic range: [0x0300,0x036F]
  #   Supplement:  [0x1DC0,0x1DFF]
  #   For Symbols: [0x20D0,0x20FF]
  #   Half marks:  [0xFE20,0xFE2F]
  #
  COMBINING_MARKS = /[̀-ͯ᷀-᷿⃐-⃿︠-︯]/

  def normalize_casefold_and_unaccent(string)
    string.to_s.unicode_normalize(:nfkd).downcase.gsub(COMBINING_MARKS, '')
  end

  # Upstream's getTemperature: the minimum/maximum pair when the provider gave
  # both, and the one-line summary when it did not.
  #
  # TRANSLATORS: this is the temperature string, minimum and maximum. The two
  # values are already formatted, so it would be something like "7 °C / 19 °C"
  def temperature(info)
    (info.temp_min && info.temp_max).then do |both|
      if both
        format('%s / %s', info.temp_min_string, info.temp_max_string)
      else
        info.temp_summary
      end
    end
  end

  # Upstream's formatTemperature: a rounded value and a degree sign, with no
  # unit — the unit is a global preference, not a per-value decoration.
  def format_temperature(value)
    value.nil? ? '' : format('%d°', value.round)
  end

  def temp_string(info) = format_temperature(info.temp)

  def date_time(info) = info.update_time

  def temp(info) = info.temp

  # Upstream's easeOutCubic, the easing the forecast scroll animation uses.
  def ease_out_cubic(value)
    (value - 1).then { |t| (t * t * t) + 1 }
  end

  # Upstream's getNight/getMorning/getDay/getAfternoon/getEvening: the five
  # times of day the daily forecast picks its readings closest to, as hours of
  # the day the given time falls on.
  NIGHT = 2
  MORNING = 7
  DAY = 12
  AFTERNOON = 17
  EVENING = 22

  def night(time) = at_hour(time, NIGHT)
  def morning(time) = at_hour(time, MORNING)
  def day(time) = at_hour(time, DAY)
  def afternoon(time) = at_hour(time, AFTERNOON)
  def evening(time) = at_hour(time, EVENING)

  def at_hour(time, hour)
    Time.new(
      time.year,
      time.month,
      time.day,
      hour,
      0,
      0,
      time.utc_offset,
    )
  end

  # Upstream's getNameAndCountry: the location's own name, plus the name of the
  # first ancestor at country level or above. This port's locations carry their
  # country directly rather than through a parent chain, so the walk upstream
  # does collapses into reading the two fields.
  def name_and_country(location)
    location.country_name.to_s.empty? ? [location.name] : [location.name, location.country_name]
  end
end
