# frozen_string_literal: true

require 'adwaita'
require_relative 'daily_forecast_box'
require_relative 'hourly_forecast_box'
require_relative 'util'
require_relative 'world_content_view'

# WeatherWidget is the weather page: the current conditions, the places button,
# the hourly/daily forecast card with its scroll arrows, and the attribution
# footer.
#
# Ported from the WeatherWidget class in upstream's src/app/city.ts and the
# template it loads, data/weather-widget.ui.
#
# The scroll animation is an Adwaita::TimedAnimation driving the scrolled
# window's adjustment, rather than upstream's hand-rolled tick callback over
# the same ease-out-cubic curve: the curve, the 400ms duration and the
# page-at-a-time target are the same, and libadwaita owns the frame clock.
#
# Two icon substitutions, both because this port installs no icon theme of its
# own and upstream's are shipped in data/icons: the conditions image and the
# forecast icons ask for the "-symbolic" variant where upstream asks for
# "-large" and "-small", and the hourly tab is headed with alarm-symbolic
# where upstream uses its own weather-hourly-symbolic.
#
class WeatherWidget < Adwaita::Bin
  SCROLLING_ANIMATION_TIME = 400

  UPDATED_TIME_TIMEOUT = 60

  MAXIMUM_SIZE = 1010
  # Ensures ~18px of margin on the right side
  TIGHTENING_THRESHOLD = 992

  CONDITIONS_ICON_SIZE = 84
  MIN_CARD_WIDTH = 308

  def initialize(model, on_show_info: nil)
    super()
    @model = model
    @on_show_info = on_show_info
    @updated_time = nil
    @updated_time_timeout_id = nil
    self.name = 'weather-page'
    self.layout_manager = clamp_layout
  end

  def build
    tap do |widget|
      widget.child = box

      box.tap do |container|
        container.append(conditions_grid)
        container.append(forecast_overlay)
        container.append(attribution_box)

        conditions_grid.tap do |grid|
          grid.attach(
            conditions_image,
            0,
            0,
            1,
            2,
          )
          grid.attach(
            places_button,
            1,
            0,
            1,
            1,
          )
          grid.attach(
            temperature_box,
            1,
            1,
            1,
            1,
          )

          places_button.tap do |button|
            button.child = places_label
            button.popover = world_view.build
          end

          temperature_box.tap do |temperatures|
            temperatures.append(temperature_label)
            temperatures.append(apparent_label)
          end
        end

        forecast_overlay.tap do |overlay|
          overlay.child = forecast_stack
          overlay.add_overlay(end_button)
          overlay.add_overlay(start_button)

          forecast_stack.tap do |stack|
            stack.add_titled_with_icon(
              hourly_scroll_window,
              'hourly',
              '_Hourly',
              'alarm-symbolic',
            )
                 .use_underline = true
            stack.add_titled_with_icon(
              daily_scroll_window,
              'daily',
              '_Daily',
              'x-office-calendar-symbolic',
            )
                 .use_underline = true

            hourly_scroll_window.child = hourly_viewport
            hourly_viewport.child = forecast_hourly.build

            daily_scroll_window.child = daily_viewport
            daily_viewport.child = forecast_daily.build
          end

          start_button.signal_connect('clicked') { scroll_by_page(-1) }
          end_button.signal_connect('clicked') { scroll_by_page(+1) }
        end

        attribution_box.tap do |footer|
          footer.append(updated_time_label)
          footer.append(attribution_label)
        end
      end

      [hourly_adjustment, daily_adjustment].each do |adjustment|
        adjustment.signal_connect('changed') { sync_left_right_buttons }
        adjustment.signal_connect('value-changed') { sync_left_right_buttons }
      end

      # Switching pages rewinds the newly shown page to its start edge, which
      # is the right-hand edge in a right-to-left locale.
      forecast_stack.signal_connect('notify::visible-child') do
        visible_adjustment.then do |adjustment|
          if adjustment
            if ltr?
              adjustment.value = adjustment.lower
            else
              adjustment.value = adjustment.upper
            end

            sync_left_right_buttons
          end
        end
      end

      widget.signal_connect('unmap') { stop_updated_time_timeout }

      sync_left_right_buttons
    end
  end

  def forecast_stack
    @forecast_stack ||= Adwaita::ViewStack.new
  end

  # Upstream's clear(): the forecast boxes are emptied before the next info is
  # poured into them, so an update never appends to the previous one.
  def clear
    forecast_hourly.clear
    forecast_daily.clear
  end

  # Upstream's update(info).
  def update(info)
    # Upstream calls places_button.set_label here, which replaces the styled
    # child label the template gave the button — and with it the #places-label
    # rule that makes the city name bold. Writing the label's own text keeps
    # the wrapping and the style.
    places_label.label = Util.name_and_country(info.location).join(', ')
    world_view.refilter

    conditions_image.icon_name = "#{info.icon_name}-symbolic"
    temperature_label.label = Util.format_temperature(info.temp)
    update_apparent(info)

    forecast_hourly.update(info)
    forecast_daily.update(info)

    restart_updated_time_timeout
    attribution_label.label = info.attribution
  end

  # Memoized widget methods

  def clamp_layout
    @clamp_layout ||= Adwaita::ClampLayout.new.tap do |layout|
      layout.maximum_size = MAXIMUM_SIZE
      layout.tightening_threshold = TIGHTENING_THRESHOLD
    end
  end

  def box
    @box ||= Gtk::Box.new(:vertical, 20).tap do |container|
      container.margin_top = 18
      container.margin_bottom = 18
    end
  end

  def conditions_grid
    @conditions_grid ||= Gtk::Grid.new.tap do |grid|
      grid.name = 'conditions-grid'
      grid.column_spacing = 10
    end
  end

  def conditions_image
    @conditions_image ||= Gtk::Image.new.tap do |image|
      image.halign = :start
      image.valign = :center
      image.pixel_size = CONDITIONS_ICON_SIZE
      image.add_css_class('icon-dropshadow')
    end
  end

  def places_button
    @places_button ||= Gtk::MenuButton.new.tap do |button|
      button.halign = :start
      button.valign = :start
      button.always_show_arrow = true
      button.add_css_class('text-button')
      button.add_css_class('flat')
    end
  end

  def places_label
    @places_label ||= Gtk::Label.new('Places').tap do |label|
      label.name = 'places-label'
      label.wrap = true
      label.wrap_mode = :word_char
    end
  end

  def temperature_box
    @temperature_box ||= Gtk::Box.new(:horizontal, 8).tap do |container|
      container.halign = :start
      container.valign = :start
      container.baseline_position = :bottom
    end
  end

  def temperature_label
    @temperature_label ||= Gtk::Label.new.tap do |label|
      label.name = 'temperature-label'
      label.halign = :start
      label.valign = :baseline
    end
  end

  def apparent_label
    @apparent_label ||= Gtk::Label.new.tap do |label|
      label.halign = :start
      label.valign = :baseline
      label.add_css_class('caption')
    end
  end

  def forecast_overlay = @forecast_overlay ||= Gtk::Overlay.new

  def hourly_adjustment = @hourly_adjustment ||= Gtk::Adjustment.new(
    0,
    0,
    0,
    0,
    0,
    0,
  )

  def daily_adjustment = @daily_adjustment ||= Gtk::Adjustment.new(
    0,
    0,
    0,
    0,
    0,
    0,
  )

  def hourly_scroll_window = @hourly_scroll_window ||= forecast_scroll_window(hourly_adjustment)

  def daily_scroll_window = @daily_scroll_window ||= forecast_scroll_window(daily_adjustment)

  def hourly_viewport = @hourly_viewport ||= forecast_viewport

  def daily_viewport = @daily_viewport ||= forecast_viewport

  def forecast_hourly = @forecast_hourly ||= HourlyForecastBox.new

  def forecast_daily = @forecast_daily ||= DailyForecastBox.new

  def start_button = @start_button ||= scroll_button('go-previous-symbolic', :start)

  def end_button = @end_button ||= scroll_button('go-next-symbolic', :end)

  def attribution_box
    @attribution_box ||= Gtk::Box.new(:vertical, 6).tap do |footer|
      footer.name = 'attributionGrid'
    end
  end

  def updated_time_label
    @updated_time_label ||= Gtk::Label.new.tap do |label|
      label.halign = :start
      label.add_css_class('caption')
    end
  end

  # Ellipsized so that on small layouts the attribution does not push the
  # bottom navigation off the window.
  def attribution_label
    @attribution_label ||= Gtk::Label.new.tap do |label|
      label.use_markup = true
      label.wrap = true
      label.xalign = 0
      label.ellipsize = :end
      label.add_css_class('dim-label')
      label.add_css_class('caption')
    end
  end

  def world_view
    @world_view ||= WorldContentView.new(
      @model,
      align:        :start,
      on_show_info: @on_show_info,
    )
  end

  private

    def forecast_scroll_window(adjustment)
      Gtk::ScrolledWindow.new.tap do |window|
        window.vscrollbar_policy = :never
        window.hscrollbar_policy = :external
        window.overflow = :hidden
        window.hadjustment = adjustment
        window.min_content_width = MIN_CARD_WIDTH
        window.add_css_class('forecast-card')
        window.add_css_class('card')
      end
    end

    def forecast_viewport
      Gtk::Viewport.new(nil, nil).tap do |viewport|
        viewport.hscroll_policy = :natural
        viewport.vscroll_policy = :natural
      end
    end

    def scroll_button(icon_name, side)
      Gtk::Button.new.tap do |button|
        button.icon_name = icon_name
        button.halign = side
        button.valign = :center
        button.add_css_class('osd')
        button.add_css_class('circular')

        if side == :start
          button.margin_start = 28
        else
          button.margin_end = 28
        end
      end
    end

    # --- Scrolling ----------------------------------------------------------

    def visible_child = forecast_stack.visible_child

    def visible_adjustment = visible_child&.hadjustment

    def ltr? = forecast_stack.direction != :rtl

    # Upstream's syncLeftRightButtons: each arrow is shown only while there is
    # something in its direction to scroll to, and the arrows swap sides in a
    # right-to-left locale.
    def sync_left_right_buttons
      visible_adjustment.then do |adjustment|
        if adjustment
          (adjustment.value > adjustment.lower).then do |leftmost|
            (adjustment.value < adjustment.upper - adjustment.page_size).then do |rightmost|
              if ltr?
                start_button.visible = leftmost
              else
                start_button.visible = rightmost
              end
              if ltr?
                end_button.visible = rightmost
              else
                end_button.visible = leftmost
              end
            end
          end
        end
      end
    end

    # One page in the given direction, with the direction flipped for a
    # right-to-left locale, exactly as upstream's two button handlers do.
    def scroll_by_page(direction)
      visible_adjustment.then do |adjustment|
        if adjustment
          (ltr? ? direction : -direction).then do |sign|
            animate_scroll(adjustment, adjustment.value + (sign * adjustment.page_size))
          end
        end
      end
    end

    def animate_scroll(adjustment, target)
      scroll_animation(adjustment).tap do |animation|
        animation.value_from = adjustment.value
        animation.value_to = target.clamp(adjustment.lower, adjustment.upper - adjustment.page_size)
        animation.play
      end
    end

    # One animation per page, since each drives its own adjustment.
    def scroll_animation(adjustment)
      @scroll_animations ||= {}
      @scroll_animations[adjustment.object_id] ||= build_scroll_animation(adjustment)
    end

    def build_scroll_animation(adjustment)
      Adwaita::TimedAnimation.new(
        self,
        adjustment.value,
        adjustment.value,
        SCROLLING_ANIMATION_TIME,
        Adwaita::PropertyAnimationTarget.new(adjustment, 'value'),
      ).tap do |animation|
        animation.easing = :ease_out_cubic
      end
    end

    # --- "Updated N minutes ago" -------------------------------------------

    def update_apparent(info)
      info.apparent.then do |apparent|
        if apparent
          apparent_label.label = format('Feels like %d°', apparent.round)
        else
          apparent_label.label = ''
        end

        apparent_label.visible = !apparent.nil? && apparent.round != info.temp.to_f.round
      end
    end

    def restart_updated_time_timeout
      stop_updated_time_timeout
      @updated_time = Time.now
      updated_time_label.label = format_updated_time

      @updated_time_timeout_id = GLib::Timeout.add_seconds(UPDATED_TIME_TIMEOUT) do
        updated_time_label.label = format_updated_time
        true
      end
    end

    def stop_updated_time_timeout
      @updated_time_timeout_id.then do |id|
        if id
          GLib::Source.remove(id)
          @updated_time_timeout_id = nil
        end
      end
    end

    # Upstream's formatUpdatedTime ladder, down to the plural forms.
    def format_updated_time
      @updated_time.then do |updated|
        if updated
          elapsed_description(Time.now - updated)
        else
          ''
        end
      end
    end

    def elapsed_description(seconds)
      (seconds / 60).then do |minutes|
        if seconds < 60
          'Updated just now.'
        else
          longer_elapsed_description(minutes)
        end
      end
    end

    def longer_elapsed_description(minutes)
      (minutes / 60).then do |hours|
        if minutes < 60
          pluralized('Updated %d minute ago.', 'Updated %d minutes ago.', minutes)
        else
          daily_elapsed_description(hours)
        end
      end
    end

    def daily_elapsed_description(hours)
      (hours / 24).then do |days|
        if hours < 24
          pluralized('Updated %d hour ago.', 'Updated %d hours ago.', hours)
        else
          weekly_elapsed_description(days)
        end
      end
    end

    def weekly_elapsed_description(days)
      if days < 7
        pluralized('Updated %d day ago.', 'Updated %d days ago.', days)
      elsif days < 30
        pluralized('Updated %d week ago.', 'Updated %d weeks ago.', days / 7)
      else
        pluralized('Updated %d month ago.', 'Updated %d months ago.', days / 30)
      end
    end

    def pluralized(singular, plural, count)
      count.floor.then do |n|
        format(n == 1 ? singular : plural, n)
      end
    end
end
