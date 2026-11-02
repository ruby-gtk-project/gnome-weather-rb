# frozen_string_literal: true

require 'adwaita'

# LocationRow is one place in the places popover, in either of its lists.
#
# Ported from upstream's src/app/locationRow.ts and src/app/locationRow.ui: the
# city name over its country, a tick when it is the location on screen, a
# location pin when it came from geolocation, and a close button when it is a
# saved place the user may drop.
#
# Two deliberate differences from upstream:
#
#   * the name setter is #location_name= rather than #name=. Gtk::Widget
#     already has a "name" property — the one CSS selects on — and upstream's
#     subclass shadows it; shadowing it here would quietly break the
#     stylesheet's #countryLabel selector for anything nested under a row.
#   * 'remove' is a Ruby callback rather than a registered GObject signal,
#     since only the popover listens and it does so in-process.
#
class LocationRow < Gtk::Box
  WIDTH = 320

  # Upstream ships its own checkmark-symbolic in data/icons; this port installs
  # no icons, so the row uses the Adwaita theme's equivalent.
  SELECTED_ICON = 'object-select-symbolic'
  CURRENT_ICON = 'find-location-symbolic'
  REMOVE_ICON = 'window-close-symbolic'

  def initialize(name: '', country_name: '', selected: false, current_location: false, removable: false)
    super(:horizontal, 12)
    set_size_request(WIDTH, -1)
    @name = name
    @country_name = country_name
    @selected = selected
    @current_location = current_location
    @removable = removable
  end

  def build
    tap do |row|
      row.append(name_box)
      row.append(location_icon)
      row.append(remove_button)

      name_box.tap do |box|
        box.append(labels)
        box.append(selected_icon)

        labels.tap do |column|
          column.append(name_label)
          column.append(country_label)
        end
      end

      remove_button.signal_connect('clicked') { @on_remove&.call }

      row.location_name = @name
      row.country_name = @country_name
      row.selected = @selected
      row.current_location = @current_location
      row.removable = @removable
    end
  end

  # Upstream's `remove` signal, emitted from the close button's handler.
  def on_remove(&block)
    @on_remove = block
  end

  def location_name=(name)
    name_label.label = name.to_s
  end

  def country_name=(name)
    country_label.label = name.to_s
  end

  def selected=(is_selected)
    selected_icon.visible = is_selected
  end

  def current_location=(is_current)
    location_icon.visible = is_current
  end

  def removable=(is_removable)
    remove_button.visible = is_removable
  end

  # Memoized widget methods

  def name_box
    @name_box ||= Gtk::Box.new(:horizontal, 12).tap do |box|
      box.hexpand = true
    end
  end

  def labels
    @labels ||= Gtk::Box.new(:vertical, 0).tap do |box|
      box.halign = :start
    end
  end

  def name_label
    @name_label ||= Gtk::Label.new.tap do |label|
      label.justify = :left
      label.halign = :start
      label.ellipsize = :end
      label.add_css_class('body')
    end
  end

  def country_label
    @country_label ||= Gtk::Label.new.tap do |label|
      label.name = 'countryLabel'
      label.justify = :left
      label.halign = :start
      label.ellipsize = :end
      label.add_css_class('caption')
    end
  end

  def selected_icon
    @selected_icon ||= Gtk::Image.new.tap do |image|
      image.icon_name = SELECTED_ICON
      image.visible = false
    end
  end

  def location_icon
    @location_icon ||= Gtk::Image.new.tap do |image|
      image.icon_name = CURRENT_ICON
      image.visible = false
      image.add_css_class('circular')
    end
  end

  def remove_button
    @remove_button ||= Gtk::Button.new.tap do |button|
      button.icon_name = REMOVE_ICON
      button.valign = :center
      button.visible = false
      button.tooltip_text = 'Remove'
      button.add_css_class('circular')
      button.add_css_class('flat')
    end
  end
end
