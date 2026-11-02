# frozen_string_literal: true

require 'adwaita'
require_relative 'hour_entry'
require_relative 'util'

# HourlyForecastBox is the hourly page of the forecast card: a row of hours
# with a temperature curve drawn behind them.
#
# Ported from the HourlyForecastBox class in upstream's
# src/app/hourlyForecast.ts. The preprocessing (drop readings more than half an
# hour old, drop anything past twenty-four hours) and the curve (a Catmull-like
# spline through the hourly temperatures, stroked then filled down to the
# bottom edge) are the same.
#
# Upstream draws the curve by overriding vfunc_snapshot and calling the parent
# implementation afterwards, so the children land on top of it. The Ruby
# bindings expose no vfunc overrides, so the same stacking is built out of a
# Gtk::Overlay: the Gtk::DrawingArea holding the curve is the overlay's child
# and the row of hours is the overlay on top of it. That is why the drawing
# area is given an explicit size — it has to be the one that sizes the overlay,
# and the size is computable from the entry geometry the curve already assumes.
#
class HourlyForecastBox < Gtk::Overlay
  ONE_HOUR = 3600
  TWENTY_FOUR_HOURS = 24 * ONE_HOUR

  # The geometry upstream's snapshot works in.
  ENTRY_WIDTH = HourEntry::WIDTH
  SEPARATOR_WIDTH = 1
  LINE_WIDTH = 2
  ENTRY_IMAGE_Y = 56
  ENTRY_IMAGE_HEIGHT = 32
  ENTRY_TEMPERATURE_LABEL_HEIGHT = 19
  SPACING = 18
  SMOOTHNESS = 0.4

  HEIGHT = HourEntry::HEIGHT + (2 * HourEntry::MARGIN)

  # The width the card asks for when there is no forecast to draw. The overlay
  # measures its child, which is the chart, so an empty chart still has to be
  # wide enough for the "Forecast not Available" label the overlay carries —
  # upstream's scrolled window asks for the same 308px minimum.
  EMPTY_WIDTH = 308

  STROKE_COLOR = 'weather_temp_chart_stroke_color'
  FILL_COLOR = 'weather_temp_chart_fill_color'

  # Upstream reads org.gnome.desktop.interface's clock-format to choose between
  # a 24-hour and an AM/PM time. Reading that schema needs no install step —
  # it ships with GSettings' desktop schemas — but it is absent on a machine
  # without them, so a missing schema falls back to 24-hour time.
  CLOCK_SCHEMA = 'org.gnome.desktop.interface'

  # Translators: this is a time format without date used for AM/PM
  TWELVE_HOUR_FORMAT = '%l:%M %p'
  TWENTY_FOUR_HOUR_FORMAT = '%R'

  def initialize
    super()
    @hourly_info = []
    self.name = 'hourly-forecast-box'
  end

  def build
    tap do |overlay|
      overlay.child = chart
      overlay.add_overlay(box)

      chart.set_draw_func { |_area, context, width, height| draw(context, width, height) }
    end
  end

  def has_forecast_info? = !@hourly_info.empty?

  # Upstream's update(info): take the current conditions plus the forecast
  # list, drop what belongs to another hour or another day, and lay out one
  # entry per remaining reading with a separator between them.
  def update(info)
    preprocess(info).then do |hourly_info|
      @hourly_info = hourly_info

      if hourly_info.empty?
        box.prepend(unavailable_label)
      else
        hourly_info.each_with_index do |reading_info, index|
          box.append(HourEntry.new(time_label_for(reading_info, index.zero?), reading_info).build)

          if index < hourly_info.length - 1
            box.append(separator)
          end
        end
      end

      resize_chart
    end
  end

  def clear
    @hourly_info = []

    while box.first_child
      box.remove(box.first_child)
    end

    resize_chart
  end

  # Memoized widget methods

  def box
    @box ||= Gtk::Box.new(:horizontal, 0).tap do |container|
      container.halign = :start
      container.valign = :fill
    end
  end

  def chart
    @chart ||= Gtk::DrawingArea.new.tap do |area|
      area.content_height = HEIGHT
    end
  end

  def unavailable_label
    @unavailable_label ||= Gtk::Label.new('Forecast not Available').tap do |label|
      label.use_markup = true
      label.hexpand = true
      label.vexpand = true
      label.margin_top = SPACING
      label.margin_bottom = SPACING
    end
  end

  private

    def separator = Gtk::Separator.new(:vertical)

    # The drawing area is what the overlay measures, so it has to grow with the
    # number of hours on show. One entry per reading, one separator between
    # each pair — the widths the curve already assumes.
    def resize_chart
      @hourly_info.length.then do |count|
        if count.zero?
          chart.content_width = EMPTY_WIDTH
        else
          chart.content_width = (count * ENTRY_WIDTH) + ((count - 1) * SEPARATOR_WIDTH)
        end

        chart.queue_draw
      end
    end

    # Upstream's preprocess: the previous hour's forecast stays on show until
    # thirty minutes in, and nothing beyond twenty-four hours is shown at all.
    def preprocess(info)
      ([info] + info.forecast_list).select do |entry|
        entry.update_time.then do |time|
          if time
            difference = time - now_at(info)
            difference > -(ONE_HOUR / 2) && difference < TWENTY_FOUR_HOURS
          else
            false
          end
        end
      end
    end

    # Upstream finds the location's timezone through the nearest city in the
    # GWeather database; the readings here already carry the location's own UTC
    # offset, so "now, where that location is" is this instant in that offset.
    def now_at(info)
      info.update_time.then do |time|
        time ? Time.now.getlocal(time.utc_offset) : Time.now
      end
    end

    def time_label_for(info, is_now)
      if is_now
        'Now'
      else
        info.update_time&.strftime(time_format).to_s.strip
      end
    end

    def time_format
      if clock_format == '12h'
        TWELVE_HOUR_FORMAT
      else
        TWENTY_FOUR_HOUR_FORMAT
      end
    end

    def clock_format
      @clock_format ||= read_clock_format
    end

    def read_clock_format
      Gio::SettingsSchemaSource.default.lookup(CLOCK_SCHEMA, true).then do |schema|
        if schema
          Gio::Settings.new(CLOCK_SCHEMA).get_string('clock-format')
        else
          '24h'
        end
      end
    rescue StandardError, GLib::Error
      '24h'
    end

    # --- The curve ---------------------------------------------------------

    # Upstream's vfunc_snapshot, in cairo rather than a Gtk.Snapshot: the
    # temperatures are normalised into the graph band, a smooth curve is laid
    # through them, stroked in the chart's stroke colour, then closed along the
    # bottom edge and filled.
    def draw(context, width, height)
      temperatures.then do |temps|
        if temps.length > 1
          y_coords(temps, height).then do |coords|
            trace(
              context,
              coords,
              width,
              height,
            )

            context.set_source_rgba(*rgba(STROKE_COLOR))
            context.line_width = LINE_WIDTH
            context.stroke_preserve

            context.line_to(width, height)
            context.line_to(0, height)
            context.set_source_rgba(*rgba(FILL_COLOR))
            context.fill
          end
        end
      end
    end

    def temperatures = @hourly_info.map { |info| Util.temp(info) }.compact

    # Upstream normalises to [0, 1] across the shown range, and halves the raw
    # values when every hour reads the same, which keeps the flat line off the
    # top of the band.
    def values(temps)
      [temps.min, temps.max].then do |min_temp, max_temp|
        if min_temp == max_temp
          temps.map { |t| t / 2.0 }
        else
          temps.map { |t| (t - min_temp) / (max_temp - min_temp).to_f }
        end
      end
    end

    def graph_min_y = (LINE_WIDTH / 2.0) + ENTRY_IMAGE_Y + ENTRY_IMAGE_HEIGHT + SPACING

    def graph_max_y(height)
      height - (LINE_WIDTH / 2.0) - SPACING - ENTRY_TEMPERATURE_LABEL_HEIGHT - SPACING
    end

    def y_coords(temps, height)
      (graph_max_y(height) - graph_min_y).then do |graph_height|
        values(temps).map { |value| graph_min_y + ((1 - value) * graph_height) }
      end
    end

    # The spline: each point gets the gradient of the chord between its
    # neighbours, and the control points sit along that gradient, a fixed
    # fraction of the gap away.
    def trace(context, coords, width, _height)
      (ENTRY_WIDTH + SEPARATOR_WIDTH).then do |points_gap|
        gradients = coords.each_index.map { |i| gradient_at(coords, i, points_gap) }
        x = -points_gap / 2.0

        context.move_to(x, coords.first)

        (coords.length + 1).times do |i|
          curve_segment(
            context,
            coords,
            gradients,
            i,
            x,
            points_gap,
          )
          x += points_gap
        end

        context.line_to(width, coords.last)
      end
    end

    def gradient_at(coords, index, points_gap)
      if index.positive?
        previous = coords[index - 1]
      else
        previous = coords[index]
      end
      if index < coords.length - 1
        following = coords[index + 1]
      else
        following = coords[index]
      end
      (following - previous) / (2.0 * points_gap)
    end

    def curve_segment(context, coords, gradients, index, x, points_gap)
      if index.positive?
        previous_y = coords[index - 1]
      else
        previous_y = coords[index]
      end
      if index.positive?
        previous_gradient = gradients[index - 1]
      else
        previous_gradient = 0
      end
      if index < coords.length
        current_y = coords[index]
      else
        current_y = coords[index - 1]
      end
      if index < coords.length
        current_gradient = gradients[index]
      else
        current_gradient = 0
      end

      distance_in = control_distance(gradients, index - 1, points_gap)
      distance_out = control_distance(gradients, index, points_gap)

      context.curve_to(
        x + distance_in,
        previous_y + (previous_gradient * distance_in),
        x + points_gap - distance_out,
        current_y - (current_gradient * distance_out),
        x + points_gap,
        current_y,
      )
    end

    # The control points are pulled in along the chord, so a steep gradient
    # shortens the horizontal reach rather than overshooting the next point.
    def control_distance(gradients, index, points_gap)
      gradients[index].then do |gradient|
        if index.negative? || gradient.nil?
          points_gap * SMOOTHNESS
        else
          Math.cos(Math.atan(gradient)) * points_gap * SMOOTHNESS
        end
      end
    end

    def rgba(name)
      style_context.lookup_color(name).then do |found, color|
        if found
          [color.red, color.green, color.blue, color.alpha]
        else
          [0.5, 0.5, 0.5, 0.5]
        end
      end
    end
end
