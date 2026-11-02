# frozen_string_literal: true

require 'json'
require 'fileutils'

# Settings holds the same keys as upstream's org.gnome.Weather GSettings
# schema (data/org.gnome.Weather.gschema.xml):
#
#   locations        av  the saved locations, newest first
#   window-width     i   the main window's width  (-1: let GTK decide)
#   window-height    i   the main window's height (-1: let GTK decide)
#   window-maximized b   whether the window was maximized
#
# plus temperature-unit, which upstream does not keep in its own schema — it
# reads and writes org.gnome.GWeather4's key so the whole desktop agrees on the
# unit. This port has no GWeather, so the preference lives here.
#
# Upstream's values are GSettings, which needs a compiled schema installed into
# the system's glib-2.0/schemas directory. Requiring an install step to run the
# app from a checkout is worse than the alternative, so the same keys, defaults
# and semantics are backed by a small JSON file under XDG_CONFIG_HOME instead —
# the same trade the gnome-contacts port made.
#
# A location is stored as the hash Location#serialize returns, which is this
# port's stand-in for the GVariant gweather_location_serialize() produces.
#
class Settings
  # Upstream's WorldModel.load truncates the list to ten on read; the same
  # limit is applied here, in the model, for the same reason.
  MAX_LOCATIONS = 10

  UNITS = %w[default centigrade fahrenheit].freeze

  DEFAULTS = {
    'locations'        => [],
    'window-width'     => 1050,
    'window-height'    => 650,
    'window-maximized' => false,
    'temperature-unit' => 'default',
  }.freeze

  def initialize(path: nil)
    @path = path || default_path
    @values = DEFAULTS.merge(read)
    @listeners = {}
  end

  def [](key) = @values.fetch(key.to_s, DEFAULTS[key.to_s])

  def []=(key, value)
    @values[key.to_s] = value
    write
    notify(key.to_s)
    value
  end

  def location = @path

  # Named accessors for the keys the app reads most, so callers do not repeat
  # the string keys.
  DEFAULTS.each_key do |key|
    method_name = key.tr('-', '_')
    define_method(method_name) { self[key] }
    define_method(:"#{method_name}=") { |value| self[key] = value }
  end

  def window_maximized? = self['window-maximized'] == true

  # Upstream's application.ts watches 'changed::temperature-unit' to keep its
  # radio action in step with the rest of the desktop; the same callback shape
  # is offered here.
  def watch(key, &block)
    @listeners[key.to_s] ||= []
    @listeners[key.to_s] << block
    block
  end

  # The unit the provider is asked for. 'default' follows the locale the way
  # gweather_temperature_unit_to_real() does: Fahrenheit in the United States,
  # Celsius everywhere else.
  def real_temperature_unit
    if self['temperature-unit'] == 'default'
      fahrenheit_locale? ? 'fahrenheit' : 'centigrade'
    else
      self['temperature-unit']
    end
  end

  # Restores the window geometry recorded by the previous run.
  def apply_to(window)
    window.set_default_size(self['window-width'], self['window-height'])
    if window_maximized?
      window.maximize
    end
  end

  # Records the window geometry, skipping the size while maximized so the
  # restored size is the one the user actually chose.
  def remember(window)
    @values['window-maximized'] = window.maximized?

    unless window.maximized?
      @values['window-width'] = window.default_width
      @values['window-height'] = window.default_height
    end

    write
  end

  private

    def fahrenheit_locale?
      %w[LC_ALL LC_MEASUREMENT LANG].any? do |name|
        ENV.fetch(name, '').start_with?('en_US')
      end
    end

    def notify(key)
      @listeners.fetch(key, []).each { |block| block.call(self[key]) }
    end

    def default_path
      File.join(
        ENV.fetch('XDG_CONFIG_HOME', File.expand_path('~/.config')),
        'ruby-weather',
        'settings.json',
      )
    end

    def read
      File.exist?(@path) ? JSON.parse(File.read(@path)) : {}
    rescue JSON::ParserError => e
      warn "Error parsing #{@path}: #{e.message}"
      {}
    end

    def write
      FileUtils.mkdir_p(File.dirname(@path))
      File.write(@path, JSON.pretty_generate(@values))
    end
end
