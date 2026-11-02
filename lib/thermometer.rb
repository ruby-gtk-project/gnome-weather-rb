# frozen_string_literal: true

require 'adwaita'
require_relative 'util'

# TemperatureRange is the day's range inside the week's range.
#
# Ported from the class of the same name in upstream's src/app/thermometer.ts.
TemperatureRange = Data.define(
  :daily_low,
  :daily_high,
  :weekly_low,
  :weekly_high,
)

# Thermometer draws one day's temperature range as a rounded gradient bar,
# positioned inside the week's range, with the day's high and low written above
# and below it.
#
# Ported from upstream's src/app/thermometer.ts, which is two widgets: a
# Thermometer laying out two labels and a scale, and a ThermometerScale drawing
# the bar in its snapshot vfunc.
#
# Two deliberate differences, both because the Ruby bindings expose neither
# vfunc overrides nor a widget's CSS name:
#
#   * the layout is a Gtk::Box and the bar a Gtk::DrawingArea, rather than a
#     widget measuring and allocating its three children by hand. The
#     consequence is visible: upstream slides the high and low labels along the
#     scale so each sits at its own temperature, while here they stay at the
#     ends of the bar. The bar itself is drawn with the same geometry.
#   * the stylesheet selects `.weather-thermometer`, where upstream can select
#     the `WeatherThermometer` element name it registered.
#
# The two gradient colours are looked up from the style context, so the dark
# and high-contrast stylesheets reach the bar exactly as upstream.
#
class Thermometer < Gtk::Box
  SPACING = 18

  # ThermometerScale.minHeight and .radius upstream.
  MIN_HEIGHT = 64
  RADIUS = 12

  WARM_COLOR = 'weather_thermometer_warm_color'
  COLD_COLOR = 'weather_thermometer_cold_color'

  def initialize(range: nil)
    super(:vertical, SPACING)
    @range = range
    add_css_class('weather-thermometer')
  end

  def build
    tap do |thermometer|
      thermometer.append(high_label)
      thermometer.append(scale)
      thermometer.append(low_label)

      scale.set_draw_func { |_area, context, width, height| draw(context, width, height) }

      thermometer.range = @range
    end
  end

  def range = @range

  def range=(range)
    @range = range
    high_label.label = Util.format_temperature(range&.daily_high)
    low_label.label = Util.format_temperature(range&.daily_low)
    scale.queue_draw
  end

  # Memoized widget methods

  def high_label
    @high_label ||= Gtk::Label.new.tap do |label|
      label.add_css_class('high')
      label.add_css_class('body')
    end
  end

  def low_label
    @low_label ||= Gtk::Label.new.tap do |label|
      label.add_css_class('low')
      label.add_css_class('body')
    end
  end

  def scale
    @scale ||= Gtk::DrawingArea.new.tap do |area|
      area.vexpand = true
      area.hexpand = true
      area.set_size_request(2 * RADIUS, MIN_HEIGHT)
    end
  end

  private

    # Upstream's ThermometerScale.vfunc_snapshot: a rounded rectangle covering
    # the day's span of the week's range, filled with a gradient running warm
    # at the top of the widget to cold at the bottom.
    def draw(context, width, height)
      @range.then do |range|
        if drawable?(range) && height >= MIN_HEIGHT
          factor = (height - (2 * RADIUS)) / (range.weekly_high - range.weekly_low).to_f
          gradient_width = 2 * RADIUS
          gradient_height = factor * (range.daily_high - range.daily_low)
          x = (width - gradient_width) / 2.0
          y = RADIUS + (factor * (range.weekly_high - range.daily_high))

          rounded_rectangle(
            context,
            x,
            y - RADIUS,
            gradient_width,
            gradient_height + (2 * RADIUS),
          )
          context.set_source(gradient(x + (gradient_width / 2.0), height))
          context.fill
        end
      end
    end

    # A range with a value missing, or with a week that never varied, has no
    # bar to draw: the scale factor would be a division by zero.
    def drawable?(range)
      range.is_a?(TemperatureRange) &&
        range.to_h.values.all? { |value| value.is_a?(Numeric) } &&
        range.weekly_high > range.weekly_low
    end

    # Cairo::LinearPattern, not Cairo::LinearGradient: the Ruby cairo bindings
    # name the pattern classes after the cairo_pattern_create_* calls.
    def gradient(x, height)
      Cairo::LinearPattern.new(
        x,
        0,
        x,
        height,
      ).tap do |pattern|
        pattern.add_color_stop_rgba(0.0, *rgba(WARM_COLOR))
        pattern.add_color_stop_rgba(1.0, *rgba(COLD_COLOR))
      end
    end

    # Gdk::Cairo is not bound, so a looked-up colour is unpacked by hand rather
    # than handed to gdk_cairo_set_source_rgba().
    def rgba(name)
      style_context.lookup_color(name).then do |found, color|
        if found
          [color.red, color.green, color.blue, color.alpha]
        else
          [0.5, 0.5, 0.5, 1.0]
        end
      end
    end

    def rounded_rectangle(context, x, y, width, height)
      context.new_path
      context.arc(
        x + RADIUS,
        y + RADIUS,
        RADIUS,
        Math::PI,
        1.5 * Math::PI,
      )
      context.arc(
        x + width - RADIUS,
        y + RADIUS,
        RADIUS,
        1.5 * Math::PI,
        2 * Math::PI,
      )
      context.arc(
        x + width - RADIUS,
        y + height - RADIUS,
        RADIUS,
        0,
        0.5 * Math::PI,
      )
      context.arc(
        x + RADIUS,
        y + height - RADIUS,
        RADIUS,
        0.5 * Math::PI,
        Math::PI,
      )
      context.close_path
    end
end
