# frozen_string_literal: true

require 'adwaita'
require_relative 'location_row'
require_relative 'location_search_entry'
require_relative 'util'

# WorldContentView is the places popover: the search field, the list of
# matches, and the list of places already saved.
#
# Ported from upstream's src/app/world.ts together with the tree it loads from
# data/places-popover.ui — the .ui file is built here in Ruby instead, which is
# why one class covers both.
#
# The popover appears twice in the app: hanging off the welcome page's
# "Search for a city or country" button (centre-aligned) and off the places
# button on the weather page (start-aligned), which is what `align` picks.
#
class WorldContentView < Gtk::Popover
  WIDTH = 320
  HEIGHT = 300
  LIST_WIDTH = 300

  def initialize(model, align: :center, on_show_info: nil)
    super()
    @model = model
    @on_show_info = on_show_info
    self.hexpand = false
    self.vexpand = false
    self.halign = align
    self.has_arrow = false
    add_css_class('weather-popover')
    add_css_class('menu')
  end

  def build
    tap do |popover|
      popover.child = box

      box.tap do |container|
        container.append(location_entry.build)
        container.append(stack)

        stack.tap do |pages|
          pages.add_child(search_scroll_window)
          pages.add_child(locations_scroll_window)

          search_scroll_window.child = search_list_view
          locations_scroll_window.child = viewport
          viewport.child = locations_list_box
        end
      end

      location_entry.tap do |entry|
        entry.attach(search_list_view)

        # An emptied field goes back to the saved list; anything else shows the
        # matches for what was typed.
        entry.on_search_updated do |text|
          if text.to_s.empty?
            stack.visible_child = locations_scroll_window
          else
            stack.visible_child = search_scroll_window
          end
        end

        entry.on_location_selected do |location|
          entry.text = ''
          location_changed(location)
          stack.visible_child = locations_scroll_window
          popdown_later
        end
      end

      locations_list_box.tap do |list|
        list.bind_model(@model.list_store) { |info| build_location(info) }
        list.set_placeholder(empty_search_grid)

        # The row's position, not the row object, is what identifies the info:
        # the list box is bound to the same store the model's ordering is
        # written into, and a Ruby wrapper GTK hands back for a row is not
        # guaranteed to be the object the bind block returned.
        list.signal_connect('row-activated') do |_, row|
          @model.at_index(row.index).then do |info|
            if info
              @model.set_selected_location(info)
            end

            popdown_later
          end
        end
      end

      @model.on_selected_location_changed { |info| @on_show_info&.call(info) }

      popover.signal_connect('show') { location_entry.grab_focus }

      stack.visible_child = locations_scroll_window
    end
  end

  # Upstream's refilter: the saved rows show a tick for the location on screen,
  # so the weather page asks for them to be rebuilt after it changes.
  def refilter
    locations_list_box.bind_model(@model.list_store) { |info| build_location(info) }
  end

  # Memoized widget methods

  def box
    @box ||= Gtk::Box.new(:vertical, 0).tap do |container|
      container.set_size_request(WIDTH, HEIGHT)
    end
  end

  def stack
    @stack ||= Gtk::Stack.new.tap do |pages|
      pages.hexpand = true
      pages.vexpand = true
      pages.set_size_request(LIST_WIDTH, -1)
    end
  end

  def search_scroll_window
    @search_scroll_window ||= Gtk::ScrolledWindow.new.tap do |window|
      window.hscrollbar_policy = :never
      window.vexpand = true
      window.add_css_class('undershoot-top')
    end
  end

  def search_list_view
    @search_list_view ||= Gtk::ListView.new.tap do |view|
      view.name = 'search-list-view'
      view.hscroll_policy = :minimum
    end
  end

  def locations_scroll_window
    @locations_scroll_window ||= Gtk::ScrolledWindow.new.tap do |window|
      window.hscrollbar_policy = :never
      window.add_css_class('undershoot-top')
    end
  end

  def viewport = @viewport ||= Gtk::Viewport.new(nil, nil)

  def locations_list_box
    @locations_list_box ||= Gtk::ListBox.new.tap do |list|
      list.name = 'locations-list-box'
      list.hexpand = true
      list.selection_mode = :none
      list.show_separators = false
    end
  end

  def location_entry = @location_entry ||= LocationSearchEntry.new

  # The placeholder the saved list shows before anything has been saved.
  def empty_search_grid
    @empty_search_grid ||= Gtk::Grid.new.tap do |grid|
      grid.name = 'search-city-grid'
      grid.margin_top = 25
      grid.margin_bottom = 25
      grid.halign = :center
      grid.valign = :center
      grid.row_homogeneous = true
      grid.attach(
        empty_search_image,
        0,
        0,
        1,
        1,
      )
      grid.attach(
        empty_search_label,
        0,
        1,
        1,
        1,
      )
    end
  end

  def empty_search_image
    @empty_search_image ||= Gtk::Image.new.tap do |image|
      image.icon_name = 'edit-find-symbolic'
      image.icon_size = :large
      image.halign = :center
      image.valign = :center
    end
  end

  def empty_search_label
    @empty_search_label ||= Gtk::Label.new('Search for a city').tap do |label|
      label.halign = :center
      label.valign = :center
      label.add_css_class('dim-label')
    end
  end

  private

    def location_changed(location)
      if location
        @model.add_new_location(location).then { |info| @on_show_info&.call(info) }
      end
    end

    # Upstream defers both popdowns through an idle callback, to let the stack
    # re-render before the popover goes away.
    def popdown_later
      GLib::Idle.add do
        popdown
        false
      end
    end

    # The row the saved list shows for one location. Upstream hangs the info
    # off the Gtk.ListBoxRow it builds; here the row's position in the list
    # does that job, so the row carries nothing but its widgets.
    def build_location(info)
      Gtk::ListBoxRow.new.tap do |list_row|
        list_row.child = location_row_for(info)
      end
    end

    def location_row_for(info)
      Util.name_and_country(info.location).then do |name, country_name|
        LocationRow.new(
          name:             name,
          country_name:     country_name.to_s,
          selected:         @model.selected_location?(info),
          current_location: @model.current_location?(info),
          removable:        !@model.selected_location?(info) && !@model.current_location?(info),
        ).build.tap do |row|
          row.on_remove { @model.remove_location(info) }
        end
      end
    end
end
