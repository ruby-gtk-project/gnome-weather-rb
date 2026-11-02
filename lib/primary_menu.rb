# frozen_string_literal: true

require 'adwaita'

# PrimaryMenu is the menu behind the hamburger button in both header bars.
#
# Ported from the <menu id="primary-menu"> block of upstream's data/window.ui:
# a section of temperature-unit radio items bound to app.temperature-unit, and
# a section with the About item bound to win.about.
#
# The radio behaviour comes from the action rather than the items: a stateful
# Gio::SimpleAction whose state is one of the targets below renders the matching
# item ticked, which is why the app's action carries a string state.
#
class PrimaryMenu
  UNITS = {
    '_Celsius'    => 'centigrade',
    '_Fahrenheit' => 'fahrenheit',
  }.freeze

  ACTION = 'app.temperature-unit'

  def build
    menu.tap do |model|
      model.append_section('Temperature Unit', unit_section)
      model.append_section(nil, about_section)
    end
  end

  def menu = @menu ||= Gio::Menu.new

  def unit_section
    @unit_section ||= Gio::Menu.new.tap do |section|
      UNITS.each do |label, target|
        section.append_item(unit_item(label, target))
      end
    end
  end

  def about_section
    @about_section ||= Gio::Menu.new.tap do |section|
      section.append_item(Gio::MenuItem.new('_About Weather', 'win.about'))
    end
  end

  private

    def unit_item(label, target)
      Gio::MenuItem.new(label, nil).tap do |item|
        item.set_action_and_target_value(ACTION, GLib::Variant.new(target))
      end
    end
end
