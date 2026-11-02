# frozen_string_literal: true

require 'adwaita'
require_relative 'weather_widget'

# WeatherView is the shell around the weather page: a spinner while a location
# is loading, and the page itself once there is something to draw.
#
# Ported from the WeatherView class in upstream's src/app/city.ts and the
# template it loads, data/city.ui.
#
# The cycle is upstream's: setting #info swaps to the loading page, attaches to
# that info's update notification, and either draws straight away when the info
# already holds readings or asks it to fetch them.
#
class WeatherView < Adwaita::Bin
  LOADING = 'loading'
  INFO = 'info'

  def initialize(model, on_show_info: nil)
    super()
    @model = model
    @on_show_info = on_show_info
    @update_id = nil
    self.hexpand = true
    self.vexpand = true
  end

  def build
    tap do |view|
      view.child = stack

      stack.tap do |pages|
        pages.add_named(spinner, LOADING)
        pages.add_named(info_page.build, INFO)
      end

      view.signal_connect('unmap') { disconnect_info }
    end
  end

  def info = @info

  def info=(info)
    disconnect_info
    info_page.clear
    @info = info

    if info
      stack.visible_child_name = LOADING
      @update_id = info.connect_updated { |updated| on_update(updated) }

      if info.valid?
        on_update(info)
      else
        @model.update_info(info)
      end
    end
  end

  # Upstream's update(): the refresh action. The page goes back to the spinner
  # and the info is asked to fetch again.
  def update
    stack.visible_child_name = LOADING
    info_page.clear

    if @info
      @model.update_info(@info)
    end
  end

  def forecast_stack = info_page.forecast_stack

  # Memoized widget methods

  def stack
    @stack ||= Gtk::Stack.new.tap do |pages|
      pages.transition_type = :crossfade
    end
  end

  def spinner = @spinner ||= Adwaita::Spinner.new

  def info_page
    @info_page ||= WeatherWidget.new(@model, on_show_info: @on_show_info)
  end

  private

    def on_update(info)
      info_page.clear
      info_page.update(info)
      stack.visible_child_name = INFO
    end

    def disconnect_info
      @update_id.then do |id|
        if id
          @info&.disconnect_updated(id)
          @update_id = nil
        end
      end
    end
end
