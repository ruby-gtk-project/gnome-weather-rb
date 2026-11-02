# frozen_string_literal: true

require 'adwaita'

# Styles carries the app's stylesheet.
#
# Ported from upstream's data/style.css, data/style-dark.css and
# data/style-hc.css. Upstream ships them as resources and lets libadwaita pick
# the variant through Adw.StyleManager's "dark" and "high-contrast" stylesheet
# slots; the same selection happens here, by loading the base sheet once and
# swapping the variant sheet whenever the style manager's state changes.
#
# The nine @define-colors matter beyond their own selectors: the temperature
# chart in HourlyForecastBox and the thermometer gradient in Thermometer read
# weather_temp_chart_*_color and weather_thermometer_*_color back out of the
# style context, exactly as upstream does.
#
class Styles
  BASE = <<~CSS
    @define-color weather_temp_chart_fill_color rgba(248, 228, 92, 0.5);
    @define-color weather_temp_chart_stroke_color rgba(246, 211, 45, 1.0);

    @define-color weather_thermometer_warm_color @yellow_4;
    @define-color weather_thermometer_cold_color @blue_4;

    @define-color weather_thermometer_high_color @yellow_5;
    @define-color weather_thermometer_low_color @blue_5;
    @define-color weather_forecast_color #ae7b03;

    #places-label {
        font-weight: bold;
    }

    #temperature-label {
        font-size: 32pt;
        font-weight: 900;
        margin-left: 9px;
    }

    .content-view.cell {
        font-weight: bold;
    }

    #locationEntry {
        margin: 6px;
    }

    .weather-popover {
        margin-top: 6px;
    }

    .forecast-card {
        transition: border-radius 100ms ease-out;
    }

    .forecast-card separator {
        background-color: var(--card-shade-color);
    }

    #conditions-grid,
    #attributionGrid {
        margin-left: 18px;
        margin-right: 18px;
    }

    #weather-page .small .forecast-card {
        margin-left: 0;
        margin-right: 0;
        border-radius: 0;
    }

    .forecast-temperature-label {
        font-weight: bold;
        color: @weather_forecast_color;
    }

    WeatherThermometer {
        margin-bottom: 12px;
    }

    WeatherThermometer > label.high {
        font-weight: bold;
        color: @weather_thermometer_high_color;
    }

    WeatherThermometer > label.low {
        font-weight: bold;
        color: @weather_thermometer_low_color;
    }

    .forecast-button {
        margin: 0 12px;
    }

    .forecast-graphic {
        margin: 18px;
    }

    button.osd.circular {
        border-radius: 9999px;
        min-width: 24px;
        min-height: 24px;
    }

    button.osd.circular > image {
        padding: 12px;
    }

    image.circular {
        min-width: 34px;
        min-height: 34px;
        padding: 0;
        border-radius: 9999px;
    }
  CSS

  DARK = <<~CSS
    @define-color weather_temp_chart_fill_color alpha(#cd9309, 0.25);
    @define-color weather_temp_chart_stroke_color @yellow_4;
    @define-color weather_forecast_color @yellow_4;

    @define-color weather_thermometer_warm_color @yellow_5;
    @define-color weather_thermometer_cold_color @blue_5;

    @define-color weather_thermometer_high_color @yellow_2;
    @define-color weather_thermometer_low_color @blue_2;
  CSS

  HIGH_CONTRAST = <<~CSS
    .forecast-card separator {
        background-color: var(--border-color);
    }
  CSS

  # The variant sheet sits one step above the base sheet so its @define-colors
  # win, and both sit at APPLICATION priority, above the platform theme.
  BASE_PRIORITY = Gtk::StyleProvider::PRIORITY_APPLICATION
  VARIANT_PRIORITY = Gtk::StyleProvider::PRIORITY_APPLICATION + 1

  def build
    Gdk::Display.default.then do |display|
      display.tap do
        Gtk::StyleContext.add_provider_for_display(display, base_provider, BASE_PRIORITY)
        Gtk::StyleContext.add_provider_for_display(display, variant_provider, VARIANT_PRIORITY)

        style_manager.tap do |manager|
          manager.signal_connect('notify::dark') { load_variant }
          manager.signal_connect('notify::high-contrast') { load_variant }
        end

        load_variant
      end
    end
  end

  # Upstream has no equivalent: libadwaita does this switch itself for the
  # stylesheets handed to it as resources. Loading the variant by hand is what
  # replaces that, and it has to run again whenever the state changes.
  def load_variant
    variant_provider.load(data: variant_css)
  end

  def variant_css
    if style_manager.high_contrast?
      "#{style_manager.dark? ? DARK : ''}#{HIGH_CONTRAST}"
    else
      style_manager.dark? ? DARK : ''
    end
  end

  def style_manager = @style_manager ||= Adwaita::StyleManager.default

  def base_provider
    @base_provider ||= Gtk::CssProvider.new.tap do |provider|
      provider.load(data: BASE)
    end
  end

  def variant_provider = @variant_provider ||= Gtk::CssProvider.new
end
