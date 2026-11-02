# frozen_string_literal: true

require 'adwaita'
require_relative 'thermometer'
require_relative 'util'

# DayEntry is one day of the daily forecast: the weekday, the date, the day's
# conditions, a thermometer for its range, and a button opening the five-by-five
# detail popover.
#
# Ported from the DayEntry class in upstream's src/app/dailyForecast.ts and the
# template it loads, data/day-entry.ui — the popover's grid is built here in
# Ruby rather than loaded from the .ui file.
#
# The popover is upstream's layout exactly: a row per period (night, morning,
# afternoon, evening) and a column per measurement (conditions, temperature,
# humidity, wind), with icons heading the measurement columns. The temperature
# column is headed by a degree sign rather than an icon, because upstream heads
# it with the temperature-symbolic icon it ships in data/icons and this port
# installs no icons.
#
# Upstream fills the labels from vfunc_root, once the widget is in a window;
# here they are filled in #build, which is the same moment in practice — the
# entry is built as the forecast box appends it.
#
class DayEntry < Adwaita::Bin
  WIDTH = 100
  HEIGHT = 200
  MARGIN = 18
  ICON_SIZE = 32

  # Upstream's day-popover grid: the four periods, in the order it lists them.
  PERIODS = %i[night morning afternoon evening].freeze

  PERIOD_LABELS = {
    night:     'Night',
    morning:   'Morning',
    afternoon: 'Afternoon',
    evening:   'Evening',
  }.freeze

  # Translators: this is the time format for day and month name according to
  # the current locale
  DATE_FORMAT = '%b %e'

  def initialize(datetime:, range:, infos:)
    super()
    @datetime = datetime
    @range = range
    @infos = infos
    set_size_request(WIDTH, HEIGHT)
    self.hexpand = true
    self.vexpand = true
    self.margin_top = MARGIN
    self.margin_bottom = MARGIN
  end

  def build
    tap do |entry|
      entry.child = box

      box.tap do |container|
        container.append(name_label)
        container.append(date_label)
        container.append(image)
        container.append(thermometer.build)
        container.append(more_button)

        more_button.popover = more_menu
      end

      name_label.label = @datetime.strftime('%a')
      date_label.label = @datetime.strftime(DATE_FORMAT).strip
      image.icon_name = "#{@infos[:day].icon_name}-symbolic"
      thermometer.range = @range

      PERIODS.each { |period| fill_period(period) }
    end
  end

  # Memoized widget methods

  def box = @box ||= Gtk::Box.new(:vertical, 0)

  def name_label
    @name_label ||= Gtk::Label.new.tap do |label|
      label.margin_top = 8
      label.add_css_class('caption-heading')
    end
  end

  def date_label
    @date_label ||= Gtk::Label.new.tap do |label|
      label.margin_top = 8
      label.add_css_class('caption')
    end
  end

  def image
    @image ||= Gtk::Image.new.tap do |widget|
      widget.valign = :start
      widget.pixel_size = ICON_SIZE
      widget.add_css_class('forecast-graphic')
    end
  end

  def thermometer = @thermometer ||= Thermometer.new

  def more_button
    @more_button ||= Gtk::MenuButton.new.tap do |button|
      button.halign = :center
      button.valign = :center
      button.icon_name = 'view-more-symbolic'
      button.add_css_class('forecast-button')
      button.add_css_class('image-button')
      button.add_css_class('circular')
      button.add_css_class('flat')
    end
  end

  def more_menu
    @more_menu ||= Gtk::Popover.new.tap do |popover|
      popover.add_css_class('day-popover')
      popover.child = detail_grid
    end
  end

  def detail_grid
    @detail_grid ||= Gtk::Grid.new.tap do |grid|
      grid.row_spacing = 8
      grid.column_spacing = 16
      grid.margin_top = 16
      grid.margin_bottom = 16
      grid.margin_start = 16
      grid.margin_end = 16

      grid.attach(
        temperature_heading,
        2,
        0,
        1,
        1,
      )
      grid.attach(
        heading_icon('weather-showers-scattered-symbolic'),
        3,
        0,
        1,
        1,
      )
      grid.attach(
        heading_icon('weather-windy-symbolic'),
        4,
        0,
        1,
        1,
      )

      PERIODS.each_with_index do |period, index|
        grid.attach(
          period_label(period),
          0,
          index + 1,
          1,
          1,
        )
        grid.attach(
          period_image(period),
          1,
          index + 1,
          1,
          1,
        )
        grid.attach(
          period_temperature(period),
          2,
          index + 1,
          1,
          1,
        )
        grid.attach(
          period_humidity(period),
          3,
          index + 1,
          1,
          1,
        )
        grid.attach(
          period_wind(period),
          4,
          index + 1,
          1,
          1,
        )
      end
    end
  end

  def temperature_heading
    @temperature_heading ||= Gtk::Label.new('°').tap do |label|
      label.add_css_class('caption-heading')
      label.tooltip_text = 'Temperature'
    end
  end

  def period_label(period)
    period_widgets(:label)[period] ||= Gtk::Label.new(PERIOD_LABELS[period]).tap do |label|
      label.halign = :end
      label.add_css_class('caption')
    end
  end

  def period_image(period)
    period_widgets(:image)[period] ||= Gtk::Image.new
  end

  def period_temperature(period)
    period_widgets(:temperature)[period] ||= Gtk::Label.new
  end

  def period_humidity(period)
    period_widgets(:humidity)[period] ||= Gtk::Label.new
  end

  def period_wind(period)
    period_widgets(:wind)[period] ||= Gtk::Label.new
  end

  private

    # The popover has four of each widget, one per period, so the memoization
    # is per period rather than per method.
    def period_widgets(kind)
      @period_widgets ||= {}
      @period_widgets[kind] ||= {}
    end

    def heading_icon(icon_name)
      Gtk::Image.new.tap { |image| image.icon_name = icon_name }
    end

    def fill_period(period)
      @infos[period].then do |info|
        period_image(period).icon_name = "#{info.icon_name}-symbolic"
        period_temperature(period).label = Util.temp_string(info)
        period_humidity(period).label = info.humidity
        period_wind(period).label = info.wind
      end
    end
end
