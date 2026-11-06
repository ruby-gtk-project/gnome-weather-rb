# frozen_string_literal: true

require 'gtk4'
require 'libgweather'
require_relative 'util'

# Location is a place the app can show the weather for.
#
# This file has no single counterpart upstream: it stands in for
# GWeather.Location, the type libgweather hands gnome-weather, together with
# the world database libgweather builds from its bundled Locations.xml.
#
# It wraps a real GWeather::Location rather than replacing it: the libgweather
# gem's typelib loads cleanly (see nix/Gemfile and flake.nix), so .world below
# is the actual GWeather location tree, walked the way upstream's
# getAllCitiesAndWeatherStations in src/app/entry.ts walks it, not a hardcoded
# subset of cities. The wrapper exists for one reason only: Gio::ListStore
# needs a GObject type to hold, and GWeather::Location's GType is not
# registrable as a Ruby subclass, so this is a GLib::Object carrying one
# alongside the plain-Ruby fields the rest of the port already reads.
#
class Location < GLib::Object
  type_register

  attr_reader :name, :country_name, :latitude, :longitude

  def initialize(name:, latitude:, longitude:, country_name: '', gweather_location: nil)
    super()
    @name = name
    @country_name = country_name
    @latitude = latitude
    @longitude = longitude
    @gweather_location = gweather_location
  end

  # The real GWeather::Location backing this place, resolved lazily for a
  # location that came back from GSettings with no tree node attached yet —
  # the nearest city in the real world database stands in for the saved spot,
  # which is the same approximation gweather_location_deserialize() falls back
  # to when a station has moved in the database since it was saved.
  def gweather_location
    @gweather_location ||= GWeather::Location.world.find_nearest_city(@latitude, @longitude)
  end

  # Upstream's getAllCitiesAndWeatherStations: walk world -> region -> country
  # -> (adm1 -> city/station | city/station), collecting every CITY and
  # WEATHER_STATION node. libgweather nests weather stations for some
  # countries one level deeper, under an administrative division, and leaves
  # others as direct children of the country.
  def self.world
    @world ||= walk_world
  end

  def self.walk_world
    root = GWeather::Location.world
    children(root).flat_map { |region| children(region) }
                  .flat_map { |country| children(country).flat_map { |location| cities_and_stations(location, country) } }
                  .map { |location, country| wrap(location, country) }
  end

  def self.cities_and_stations(node, country)
    if node.level == GWeather::LocationLevel::ADM1
      children(node).select { |child| leaf_level?(child) }.map { |child| [child, country] }
    elsif leaf_level?(node)
      [[node, country]]
    else
      []
    end
  end
  private_class_method :cities_and_stations

  def self.leaf_level?(location)
    location.level == GWeather::LocationLevel::CITY ||
      location.level == GWeather::LocationLevel::WEATHER_STATION
  end
  private_class_method :leaf_level?

  def self.wrap(gweather_location, country)
    gweather_location.coords.then do |latitude, longitude|
      new(
        name:              gweather_location.name.to_s,
        country_name:      country.name.to_s,
        latitude:          latitude,
        longitude:         longitude,
        gweather_location: gweather_location,
      )
    end
  end
  private_class_method :wrap

  # next_child(nil) starts the walk, and next_child(previous) advances it;
  # GWeather signals the end of a node's children with nil either way. Plain
  # Array rather than an Enumerator: flat_map only flattens what responds to
  # to_ary, so a lazily-built Enumerator would land in the result as one
  # opaque element instead of its items.
  def self.children(location)
    [].tap do |list|
      child = location.next_child(nil)
      while child
        list << child
        child = location.next_child(child)
      end
    end
  end
  private_class_method :children

  # The pair gweather_location_serialize()/GWeather.Location.deserialize() has:
  # a saved location has to survive a restart, and the database may have moved
  # on in between, so everything needed to show the weather is in the record
  # rather than an index into the list.
  def serialize
    {
      'name'      => @name,
      'country'   => @country_name,
      'latitude'  => @latitude,
      'longitude' => @longitude,
    }
  end

  def self.deserialize(record)
    record.then do |hash|
      if hash.is_a?(Hash) && hash['name'] && hash['latitude'] && hash['longitude']
        new(
          name:         hash['name'],
          country_name: hash['country'].to_s,
          latitude:     hash['latitude'].to_f,
          longitude:    hash['longitude'].to_f,
        )
      end
    end
  end

  def coords = [@latitude, @longitude]

  # Upstream compares locations with gweather_location_equal(), which is
  # identity over the station id; two records for the same place here are the
  # same place when they sit within ~1km of each other and share a name.
  def same_as?(other)
    other.is_a?(Location) &&
      name == other.name &&
      (latitude - other.latitude).abs < 0.01 &&
      (longitude - other.longitude).abs < 0.01
  end

  # The string LocationFilter matches a search against: the city and its
  # country, folded and unaccented so "zurich" finds "Zürich".
  def search_key
    @search_key ||= Util.normalize_casefold_and_unaccent("#{@name} #{@country_name}")
  end

  def to_s = Util.name_and_country(self).join(', ')
end
