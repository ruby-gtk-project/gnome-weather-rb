# frozen_string_literal: true

require 'adwaita'
require_relative 'util'

# HourEntry is one hour of the hourly forecast: a time, an icon and a
# temperature.
#
# Ported from the HourEntry class in upstream's src/app/hourlyForecast.ts and
# the template it loads, data/hour-entry.ui. The fixed width and height matter
# beyond this widget: HourlyForecastBox draws its temperature curve against the
# same numbers.
#
# Upstream asks for the icon libgweather named plus "-small", a size it ships
# itself in data/icons. This port installs no icons, so it asks the Adwaita
# theme for the "-symbolic" variant of the same name.
#
class HourEntry < Adwaita::Bin
  WIDTH = 75
  HEIGHT = 200
  MARGIN = 18
  SPACING = 18
  ICON_SIZE = 32

  def initialize(time_text, info)
    super()
    @time_text = time_text
    @info = info
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
        container.append(time_label)
        container.append(image)
        container.append(temperature_label)
      end

      time_label.label = @time_text.to_s
      image.icon_name = "#{@info.icon_name}-symbolic"
      temperature_label.label = Util.temp_string(@info)
    end
  end

  # Memoized widget methods

  def box = @box ||= Gtk::Box.new(:vertical, SPACING)

  def time_label = @time_label ||= Gtk::Label.new

  def image
    @image ||= Gtk::Image.new.tap do |widget|
      widget.valign = :start
      widget.vexpand = true
      widget.pixel_size = ICON_SIZE
      widget.add_css_class('forecast-graphic')
    end
  end

  def temperature_label
    @temperature_label ||= Gtk::Label.new.tap do |label|
      label.valign = :end
      label.add_css_class('forecast-temperature-label')
    end
  end
end
