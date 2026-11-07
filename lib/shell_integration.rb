# frozen_string_literal: true

require 'gio2'
require 'glib2'

# ShellIntegration exports org.gnome.Shell.WeatherIntegration, the interface
# GNOME Shell's own weather widget reads to show the user's saved locations
# without keeping a copy of its own.
#
# Ported from upstream's src/app/shell.ts, together with the interface it
# exports, data/ShellWeatherIntegration.xml:
#
#   AutomaticLocation b   read-only, always true
#   Locations         av  read-only, the saved locations
#
# Upstream backs both off org.gnome.Weather's GSettings and watches
# 'changed::locations' to announce a change with PropertiesChanged. This
# port's Settings is the JSON-backed stand-in documented in lib/settings.rb,
# so the same announcement is driven off Settings#watch instead of a GSettings
# signal — same interface, same trigger, different plumbing underneath.
#
# Each saved location goes out as the a{sv} dictionary Location#serialize
# already produces (name/country/latitude/longitude), not the opaque blob
# gweather_location_serialize() emits upstream: this port's own Location is
# the one thing that can deserialize a record it saved, and a real
# GWeather::Location's serialize format is not reconstructable from the
# deep-unpacked Ruby values ruby-gnome hands back for it (there is no stable
# type signature to rebuild a GLib::Variant from), so reusing it here would
# either crash the DBus property or silently drop the location data.
#
# Exported from the application's own connection and object path, exactly as
# upstream's Application.vfunc_dbus_register hands its ShellIntegration the
# connection and path the application was just registered on — the Ruby
# bindings cannot override that virtual function, so App exports this from
# its 'startup' handler instead, once app.dbus_connection exists.
class ShellIntegration
  INTERFACE = 'org.gnome.Shell.WeatherIntegration'

  NODE_XML = <<~XML
    <node>
      <interface name="org.gnome.Shell.WeatherIntegration">
        <property name="AutomaticLocation" type="b" access="read"/>
        <property name="Locations" type="av" access="read"/>
      </interface>
    </node>
  XML

  ESCAPES = { '\\' => '\\\\', '"' => '\\"' }.freeze

  def initialize(settings)
    @settings = settings
    @connection = nil
    @path = nil
    @registration_id = nil
    @settings.watch('locations') { announce_locations_changed }
  end

  def export(connection, path)
    @connection = connection
    @path = path
    @registration_id = connection.register_object(
      path,
      interface_info,
      method(:handle_method_call),
      method(:get_property),
      method(:set_property),
    )
  rescue StandardError, GLib::Error => e
    warn "Could not export the shell weather integration: #{e.message}"
    nil
  end

  def unexport(connection)
    connection.unregister_object(@registration_id) if @registration_id
    @connection = nil
    @registration_id = nil
  end

  # lookup_interface rather than interfaces.first: Gio::DBusNodeInfo#interfaces
  # returns unusable strings in these bindings, while #lookup_interface returns
  # the Gio::DBusInterfaceInfo wanted here.
  def interface_info = Gio::DBusNodeInfo.new(NODE_XML).lookup_interface(INTERFACE)

  def automatic_location? = true

  def locations = Array(@settings.locations)

  private

    # No methods on this interface, only properties, but register_object still
    # needs a method-call closure to hand the connection.
    def handle_method_call(*) = nil

    def get_property(_connection, _sender, _path, _interface, property_name)
      case property_name
      when 'AutomaticLocation'
        GLib::Variant.new(automatic_location?)
      when 'Locations'
        locations_variant
      end
    end

    def set_property(*) = false

    def locations_variant = GLib::Variant.parse("[#{locations.map { |record| dict_text(record) }.join(', ')}]", 'av')

    def dict_text(record)
      "<{#{record.map { |key, value| "#{quote(key)}: <#{value_text(value)}>" }.join(', ')}}>"
    end

    def value_text(value)
      case value
      when Float, Integer then value.to_s
      else quote(value.to_s)
      end
    end

    def quote(value) = %("#{value.to_s.gsub(/[\\"]/) { |char| ESCAPES.fetch(char) }}")

    # Upstream's settings.connect('changed::locations', ...) -> emit_property_changed.
    def announce_locations_changed
      @connection&.emit_signal(
        nil,
        @path,
        'org.freedesktop.DBus.Properties',
        'PropertiesChanged',
        GLib::Variant.parse(
          "('#{INTERFACE}', {'Locations': <#{locations_variant_text}>}, @as [])",
          '(sa{sv}as)',
        ),
      )
    end

    def locations_variant_text
      locations.empty? ? '@av []' : "[#{locations.map { |record| dict_text(record) }.join(', ')}]"
    end
end
