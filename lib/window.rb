# frozen_string_literal: true

require 'adwaita'
require_relative 'about_dialog'
require_relative 'primary_menu'
require_relative 'weather_view'
require_relative 'world_content_view'

# Window is the main window: a two-page stack holding the welcome page and the
# weather page, each with its own header bar.
#
# Ported from upstream's src/app/window.ts and data/window.ui. The welcome page
# is an Adw.StatusPage with the places popover hanging off its button; the
# weather page is the forecast view between a header bar carrying the refresh
# button and the view switcher, and a bottom bar carrying the switcher again
# for narrow windows.
#
# The two window actions are upstream's: win.about opens the About dialog, and
# win.refresh refetches the location on screen.
#
# Adwaita::ApplicationWindow rather than Gtk::ApplicationWindow, for the reason
# the gnome-contacts port documents: the Gtk window draws its own titlebar,
# which would sit above the Adwaita header bars and give the window a second
# close button.
#
class Window
  DEFAULT_WIDTH = 1050
  DEFAULT_HEIGHT = 650

  ICON_NAME = 'weather-few-clouds-symbolic'

  ACTIONS = {
    'about'   => [],
    'refresh' => ['F5', '<Control>r'],
  }.freeze

  def initialize(app, model, settings, version:)
    @app = app
    @model = model
    @settings = settings
    @version = version
  end

  def build
    window.tap do |win|
      win.content = stack

      stack.tap do |pages|
        pages.add_child(search_view)
        pages.add_child(city_box)

        search_view.tap do |view|
          view.add_top_bar(search_header_bar)
          view.content = search_status_page

          search_header_bar.pack_end(menu_button)
          search_status_page.child = search_button
          search_button.popover = search_popover.build
        end

        city_box.tap do |view|
          view.add_top_bar(header_bar)
          view.content = city_bin
          view.add_bottom_bar(forecast_stack_switcher_bar)

          header_bar.pack_start(refresh_revealer)
          header_bar.title_widget = forecast_stack_switcher
          header_bar.pack_end(city_menu_button)

          refresh_revealer.child = refresh_button
          city_bin.child = city_view.build
        end
      end

      forecast_stack_switcher.stack = city_view.forecast_stack
      forecast_stack_switcher_bar.stack = city_view.forecast_stack
      forecast_stack_switcher.bind_property(
        'title-visible',
        forecast_stack_switcher_bar,
        'reveal',
        :sync_create,
      )

      setup_actions

      win.signal_connect('close-request') do
        @settings.remember(win)
        @model.save_settings_now
        false
      end

      stack.visible_child = search_view
    end
  end

  def present = window.present

  # Upstream's showDefault: the most recently saved location if there is one,
  # and the welcome page if there is not.
  def show_default
    refresh_revealer.reveal_child = false

    @model.recent.then do |most_recent|
      if most_recent
        show_info(most_recent)
      else
        show_search
      end
    end
  end

  def show_search(_text = nil)
    refresh_revealer.reveal_child = true
    stack.visible_child = search_view
  end

  def show_info(info)
    if info
      refresh_revealer.reveal_child = true
      city_view.info = info
      stack.visible_child = city_box
    else
      show_default
    end
  end

  def update = city_view.update

  # Memoized widget methods

  def window
    @window ||= Adwaita::ApplicationWindow.new(@app).tap do |win|
      win.title = 'Weather'
      win.icon_name = ICON_NAME
      win.set_default_size(DEFAULT_WIDTH, DEFAULT_HEIGHT)
      @settings.apply_to(win)
    end
  end

  def stack
    @stack ||= Gtk::Stack.new.tap do |pages|
      pages.transition_type = :crossfade
    end
  end

  # --- The welcome page ----------------------------------------------------

  def search_view = @search_view ||= Adwaita::ToolbarView.new

  def search_header_bar
    @search_header_bar ||= Adwaita::HeaderBar.new.tap do |bar|
      bar.show_title = false
    end
  end

  def search_status_page
    @search_status_page ||= Adwaita::StatusPage.new.tap do |page|
      page.title = 'Welcome to Weather!'
      page.description = 'To get started, select a location.'
      page.icon_name = ICON_NAME
    end
  end

  def search_button
    @search_button ||= Gtk::MenuButton.new.tap do |button|
      button.label = 'Search for a city or country'
      button.hexpand = false
      button.halign = :center
      button.width_request = 146
    end
  end

  def search_popover
    @search_popover ||= WorldContentView.new(
      @model,
      align:        :center,
      on_show_info: method(:show_info),
    )
  end

  # --- The weather page ----------------------------------------------------

  def city_box = @city_box ||= Adwaita::ToolbarView.new

  def header_bar
    @header_bar ||= Adwaita::HeaderBar.new.tap do |bar|
      bar.centering_policy = :strict
    end
  end

  def refresh_revealer
    @refresh_revealer ||= Gtk::Revealer.new.tap do |revealer|
      revealer.transition_type = :crossfade
    end
  end

  def refresh_button
    @refresh_button ||= Gtk::Button.new.tap do |button|
      button.valign = :center
      button.tooltip_text = 'Refresh'
      button.action_name = 'win.refresh'
      button.icon_name = 'view-refresh-symbolic'
    end
  end

  def forecast_stack_switcher
    @forecast_stack_switcher ||= Adwaita::ViewSwitcherTitle.new.tap do |switcher|
      switcher.title = 'Weather'
    end
  end

  def forecast_stack_switcher_bar = @forecast_stack_switcher_bar ||= Adwaita::ViewSwitcherBar.new

  def city_bin = @city_bin ||= Adwaita::Bin.new

  def city_view
    @city_view ||= WeatherView.new(@model, on_show_info: method(:show_info))
  end

  # --- The menu ------------------------------------------------------------

  def primary_menu = @primary_menu ||= PrimaryMenu.new

  def menu_button
    @menu_button ||= Gtk::MenuButton.new.tap do |button|
      button.valign = :center
      button.icon_name = 'open-menu-symbolic'
      button.menu_model = primary_menu.build
    end
  end

  def city_menu_button
    @city_menu_button ||= Gtk::MenuButton.new.tap do |button|
      button.valign = :center
      button.icon_name = 'open-menu-symbolic'
      button.tooltip_text = 'Main Menu'
      button.primary = true
      button.menu_model = primary_menu.build
    end
  end

  private

    def setup_actions
      ACTIONS.each do |name, accels|
        Gio::SimpleAction.new(name, nil).tap do |action|
          action.signal_connect('activate') { send(:"action_#{name}") }
          window.add_action(action)

          if accels.any?
            @app.set_accels_for_action("win.#{name}", accels)
          end
        end
      end
    end

    def action_about
      AboutDialog.new(
        version:     @version,
        attribution: city_view.info&.attribution,
      ).present(window)
    end

    def action_refresh = update
end
