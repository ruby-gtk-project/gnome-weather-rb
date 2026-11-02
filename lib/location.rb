# frozen_string_literal: true

require 'gtk4'
require_relative 'util'

# Location is a place the app can show the weather for.
#
# This file has no single counterpart upstream: it stands in for
# GWeather.Location, the type libgweather hands gnome-weather, together with
# the world database libgweather builds from its bundled Locations.xml.
#
# The GWeather typelib is not available to the Ruby bindings — requiring the
# 'GWeather' namespace through gobject-introspection fails outright — so the
# port supplies the two things gnome-weather actually asks libgweather for: a
# searchable list of cities, and a serialize/deserialize pair for the saved
# locations. It is a GLib::Object because the search list is a
# Gio::ListStore, and Gio::ListStore only holds GObjects.
#
# Upstream reaches a location's country by walking get_parent() up to
# LocationLevel.COUNTRY; the rows here carry their country directly, so
# Util.name_and_country reads the field instead of walking.
#
class Location < GLib::Object
  type_register

  # The world database: name, country, ISO country code, latitude, longitude.
  #
  # libgweather's Locations.xml lists every city and weather station it knows
  # of, which is far more than a port can carry inline; this is the subset a
  # city search is useful with — the capitals and the largest cities of every
  # inhabited region.
  CITIES = [
    ['Abidjan', "Côte d'Ivoire", 'CI', 5.32, -4.03],
    ['Abu Dhabi', 'United Arab Emirates', 'AE', 24.47, 54.37],
    ['Abuja', 'Nigeria', 'NG', 9.06, 7.49],
    ['Accra', 'Ghana', 'GH', 5.56, -0.20],
    ['Addis Ababa', 'Ethiopia', 'ET', 9.03, 38.74],
    ['Adelaide', 'Australia', 'AU', -34.93, 138.60],
    ['Algiers', 'Algeria', 'DZ', 36.75, 3.06],
    ['Almaty', 'Kazakhstan', 'KZ', 43.24, 76.89],
    ['Amman', 'Jordan', 'JO', 31.95, 35.93],
    ['Amsterdam', 'Netherlands', 'NL', 52.37, 4.90],
    ['Anchorage', 'United States', 'US', 61.22, -149.90],
    ['Ankara', 'Türkiye', 'TR', 39.93, 32.87],
    ['Antananarivo', 'Madagascar', 'MG', -18.88, 47.51],
    ['Asunción', 'Paraguay', 'PY', -25.26, -57.58],
    ['Athens', 'Greece', 'GR', 37.98, 23.73],
    ['Atlanta', 'United States', 'US', 33.75, -84.39],
    ['Auckland', 'New Zealand', 'NZ', -36.85, 174.76],
    ['Baghdad', 'Iraq', 'IQ', 33.31, 44.37],
    ['Baku', 'Azerbaijan', 'AZ', 40.41, 49.87],
    ['Bangalore', 'India', 'IN', 12.97, 77.59],
    ['Bangkok', 'Thailand', 'TH', 13.76, 100.50],
    ['Barcelona', 'Spain', 'ES', 41.39, 2.17],
    ['Beijing', 'China', 'CN', 39.90, 116.41],
    ['Beirut', 'Lebanon', 'LB', 33.89, 35.50],
    ['Belgrade', 'Serbia', 'RS', 44.79, 20.45],
    ['Berlin', 'Germany', 'DE', 52.52, 13.41],
    ['Bern', 'Switzerland', 'CH', 46.95, 7.45],
    ['Bogotá', 'Colombia', 'CO', 4.71, -74.07],
    ['Boston', 'United States', 'US', 42.36, -71.06],
    ['Brasília', 'Brazil', 'BR', -15.79, -47.88],
    ['Bratislava', 'Slovakia', 'SK', 48.15, 17.11],
    ['Brisbane', 'Australia', 'AU', -27.47, 153.03],
    ['Brussels', 'Belgium', 'BE', 50.85, 4.35],
    ['Bucharest', 'Romania', 'RO', 44.43, 26.10],
    ['Budapest', 'Hungary', 'HU', 47.50, 19.04],
    ['Buenos Aires', 'Argentina', 'AR', -34.60, -58.38],
    ['Cairo', 'Egypt', 'EG', 30.04, 31.24],
    ['Calgary', 'Canada', 'CA', 51.05, -114.07],
    ['Cape Town', 'South Africa', 'ZA', -33.92, 18.42],
    ['Caracas', 'Venezuela', 'VE', 10.48, -66.90],
    ['Casablanca', 'Morocco', 'MA', 33.57, -7.59],
    ['Chennai', 'India', 'IN', 13.08, 80.27],
    ['Chicago', 'United States', 'US', 41.88, -87.63],
    ['Chișinău', 'Moldova', 'MD', 47.01, 28.86],
    ['Colombo', 'Sri Lanka', 'LK', 6.93, 79.86],
    ['Copenhagen', 'Denmark', 'DK', 55.68, 12.57],
    ['Dakar', 'Senegal', 'SN', 14.72, -17.47],
    ['Dallas', 'United States', 'US', 32.78, -96.80],
    ['Damascus', 'Syria', 'SY', 33.51, 36.29],
    ['Dar es Salaam', 'Tanzania', 'TZ', -6.79, 39.21],
    ['Delhi', 'India', 'IN', 28.70, 77.10],
    ['Denver', 'United States', 'US', 39.74, -104.98],
    ['Detroit', 'United States', 'US', 42.33, -83.05],
    ['Dhaka', 'Bangladesh', 'BD', 23.81, 90.41],
    ['Doha', 'Qatar', 'QA', 25.29, 51.53],
    ['Dubai', 'United Arab Emirates', 'AE', 25.20, 55.27],
    ['Dublin', 'Ireland', 'IE', 53.35, -6.26],
    ['Edinburgh', 'United Kingdom', 'GB', 55.95, -3.19],
    ['Edmonton', 'Canada', 'CA', 53.55, -113.49],
    ['Frankfurt', 'Germany', 'DE', 50.11, 8.68],
    ['Georgetown', 'Guyana', 'GY', 6.80, -58.16],
    ['Guatemala City', 'Guatemala', 'GT', 14.63, -90.51],
    ['Hamburg', 'Germany', 'DE', 53.55, 9.99],
    ['Hanoi', 'Vietnam', 'VN', 21.03, 105.85],
    ['Harare', 'Zimbabwe', 'ZW', -17.83, 31.05],
    ['Havana', 'Cuba', 'CU', 23.11, -82.37],
    ['Helsinki', 'Finland', 'FI', 60.17, 24.94],
    ['Ho Chi Minh City', 'Vietnam', 'VN', 10.82, 106.63],
    ['Hong Kong', 'China', 'CN', 22.32, 114.17],
    ['Honolulu', 'United States', 'US', 21.31, -157.86],
    ['Houston', 'United States', 'US', 29.76, -95.37],
    ['Islamabad', 'Pakistan', 'PK', 33.68, 73.05],
    ['Istanbul', 'Türkiye', 'TR', 41.01, 28.98],
    ['Jakarta', 'Indonesia', 'ID', -6.21, 106.85],
    ['Jerusalem', 'Israel', 'IL', 31.77, 35.21],
    ['Johannesburg', 'South Africa', 'ZA', -26.20, 28.05],
    ['Kabul', 'Afghanistan', 'AF', 34.56, 69.21],
    ['Kampala', 'Uganda', 'UG', 0.35, 32.58],
    ['Karachi', 'Pakistan', 'PK', 24.86, 67.01],
    ['Kathmandu', 'Nepal', 'NP', 27.72, 85.32],
    ['Khartoum', 'Sudan', 'SD', 15.50, 32.56],
    ['Kingston', 'Jamaica', 'JM', 17.97, -76.79],
    ['Kinshasa', 'DR Congo', 'CD', -4.44, 15.27],
    ['Kolkata', 'India', 'IN', 22.57, 88.36],
    ['Kraków', 'Poland', 'PL', 50.06, 19.94],
    ['Kuala Lumpur', 'Malaysia', 'MY', 3.14, 101.69],
    ['Kuwait City', 'Kuwait', 'KW', 29.38, 47.99],
    ['Kyiv', 'Ukraine', 'UA', 50.45, 30.52],
    ['La Paz', 'Bolivia', 'BO', -16.50, -68.15],
    ['Lagos', 'Nigeria', 'NG', 6.52, 3.38],
    ['Lahore', 'Pakistan', 'PK', 31.55, 74.34],
    ['Lima', 'Peru', 'PE', -12.05, -77.04],
    ['Lisbon', 'Portugal', 'PT', 38.72, -9.14],
    ['Ljubljana', 'Slovenia', 'SI', 46.06, 14.51],
    ['London', 'United Kingdom', 'GB', 51.51, -0.13],
    ['Los Angeles', 'United States', 'US', 34.05, -118.24],
    ['Luanda', 'Angola', 'AO', -8.84, 13.23],
    ['Luxembourg', 'Luxembourg', 'LU', 49.61, 6.13],
    ['Madrid', 'Spain', 'ES', 40.42, -3.70],
    ['Managua', 'Nicaragua', 'NI', 12.11, -86.24],
    ['Manila', 'Philippines', 'PH', 14.60, 120.98],
    ['Marseille', 'France', 'FR', 43.30, 5.37],
    ['Melbourne', 'Australia', 'AU', -37.81, 144.96],
    ['Mexico City', 'Mexico', 'MX', 19.43, -99.13],
    ['Miami', 'United States', 'US', 25.76, -80.19],
    ['Milan', 'Italy', 'IT', 45.46, 9.19],
    ['Minneapolis', 'United States', 'US', 44.98, -93.27],
    ['Minsk', 'Belarus', 'BY', 53.90, 27.57],
    ['Mogadishu', 'Somalia', 'SO', 2.05, 45.32],
    ['Montevideo', 'Uruguay', 'UY', -34.90, -56.16],
    ['Montréal', 'Canada', 'CA', 45.50, -73.57],
    ['Moscow', 'Russia', 'RU', 55.76, 37.62],
    ['Mumbai', 'India', 'IN', 19.08, 72.88],
    ['Munich', 'Germany', 'DE', 48.14, 11.58],
    ['Muscat', 'Oman', 'OM', 23.59, 58.41],
    ['Nairobi', 'Kenya', 'KE', -1.29, 36.82],
    ['Naples', 'Italy', 'IT', 40.85, 14.27],
    ['New Orleans', 'United States', 'US', 29.95, -90.07],
    ['New York', 'United States', 'US', 40.71, -74.01],
    ['Nicosia', 'Cyprus', 'CY', 35.19, 33.38],
    ['Nuuk', 'Greenland', 'GL', 64.18, -51.69],
    ['Oslo', 'Norway', 'NO', 59.91, 10.75],
    ['Ottawa', 'Canada', 'CA', 45.42, -75.70],
    ['Panama City', 'Panama', 'PA', 8.98, -79.52],
    ['Paramaribo', 'Suriname', 'SR', 5.85, -55.20],
    ['Paris', 'France', 'FR', 48.86, 2.35],
    ['Perth', 'Australia', 'AU', -31.95, 115.86],
    ['Philadelphia', 'United States', 'US', 39.95, -75.17],
    ['Phnom Penh', 'Cambodia', 'KH', 11.56, 104.92],
    ['Phoenix', 'United States', 'US', 33.45, -112.07],
    ['Port Moresby', 'Papua New Guinea', 'PG', -9.44, 147.18],
    ['Porto', 'Portugal', 'PT', 41.15, -8.61],
    ['Prague', 'Czechia', 'CZ', 50.08, 14.44],
    ['Pretoria', 'South Africa', 'ZA', -25.75, 28.19],
    ['Pyongyang', 'North Korea', 'KP', 39.04, 125.76],
    ['Quito', 'Ecuador', 'EC', -0.18, -78.47],
    ['Rabat', 'Morocco', 'MA', 34.02, -6.84],
    ['Reykjavík', 'Iceland', 'IS', 64.15, -21.94],
    ['Riga', 'Latvia', 'LV', 56.95, 24.11],
    ['Rio de Janeiro', 'Brazil', 'BR', -22.91, -43.17],
    ['Riyadh', 'Saudi Arabia', 'SA', 24.71, 46.68],
    ['Rome', 'Italy', 'IT', 41.90, 12.50],
    ['Saint Petersburg', 'Russia', 'RU', 59.93, 30.34],
    ['San Francisco', 'United States', 'US', 37.77, -122.42],
    ['San José', 'Costa Rica', 'CR', 9.93, -84.08],
    ['San Juan', 'Puerto Rico', 'PR', 18.47, -66.11],
    ['San Salvador', 'El Salvador', 'SV', 13.69, -89.19],
    ['Santiago', 'Chile', 'CL', -33.45, -70.67],
    ['Santo Domingo', 'Dominican Republic', 'DO', 18.49, -69.93],
    ['São Paulo', 'Brazil', 'BR', -23.55, -46.63],
    ['Sarajevo', 'Bosnia and Herzegovina', 'BA', 43.86, 18.41],
    ['Seattle', 'United States', 'US', 47.61, -122.33],
    ['Seoul', 'South Korea', 'KR', 37.57, 126.98],
    ['Shanghai', 'China', 'CN', 31.23, 121.47],
    ['Singapore', 'Singapore', 'SG', 1.35, 103.82],
    ['Skopje', 'North Macedonia', 'MK', 41.99, 21.43],
    ['Sofia', 'Bulgaria', 'BG', 42.70, 23.32],
    ['Stockholm', 'Sweden', 'SE', 59.33, 18.07],
    ['Sydney', 'Australia', 'AU', -33.87, 151.21],
    ['Taipei', 'Taiwan', 'TW', 25.03, 121.57],
    ['Tallinn', 'Estonia', 'EE', 59.44, 24.75],
    ['Tashkent', 'Uzbekistan', 'UZ', 41.30, 69.24],
    ['Tbilisi', 'Georgia', 'GE', 41.72, 44.78],
    ['Tegucigalpa', 'Honduras', 'HN', 14.07, -87.19],
    ['Tehran', 'Iran', 'IR', 35.69, 51.39],
    ['Tel Aviv', 'Israel', 'IL', 32.08, 34.78],
    ['Thessaloniki', 'Greece', 'GR', 40.64, 22.94],
    ['Tirana', 'Albania', 'AL', 41.33, 19.82],
    ['Tokyo', 'Japan', 'JP', 35.68, 139.69],
    ['Toronto', 'Canada', 'CA', 43.65, -79.38],
    ['Tripoli', 'Libya', 'LY', 32.89, 13.19],
    ['Tunis', 'Tunisia', 'TN', 36.81, 10.18],
    ['Ulaanbaatar', 'Mongolia', 'MN', 47.89, 106.91],
    ['Vancouver', 'Canada', 'CA', 49.28, -123.12],
    ['Vienna', 'Austria', 'AT', 48.21, 16.37],
    ['Vilnius', 'Lithuania', 'LT', 54.69, 25.28],
    ['Warsaw', 'Poland', 'PL', 52.23, 21.01],
    ['Washington', 'United States', 'US', 38.91, -77.04],
    ['Wellington', 'New Zealand', 'NZ', -41.29, 174.78],
    ['Winnipeg', 'Canada', 'CA', 49.90, -97.14],
    ['Yangon', 'Myanmar', 'MM', 16.87, 96.20],
    ['Yaoundé', 'Cameroon', 'CM', 3.85, 11.50],
    ['Yerevan', 'Armenia', 'AM', 40.18, 44.51],
    ['Zagreb', 'Croatia', 'HR', 45.81, 15.98],
    ['Zürich', 'Switzerland', 'CH', 47.38, 8.54],
  ].freeze

  attr_reader :name, :country_name, :country_code, :latitude, :longitude

  def initialize(name:, latitude:, longitude:, country_name: '', country_code: '')
    super()
    @name = name
    @country_name = country_name
    @country_code = country_code
    @latitude = latitude
    @longitude = longitude
  end

  # Every city in the database, which is what the search list is built from.
  # Upstream's entry.ts walks the GWeather location tree down to the CITY and
  # WEATHER_STATION levels to get the same list; the database here holds cities
  # only, so the walk is a map.
  def self.world
    @world ||= CITIES.map do |name, country_name, country_code, latitude, longitude|
      new(
        name:         name,
        country_name: country_name,
        country_code: country_code,
        latitude:     latitude,
        longitude:    longitude,
      )
    end
  end

  # The pair gweather_location_serialize()/GWeather.Location.deserialize() has:
  # a saved location has to survive a restart, and the database may have moved
  # on in between, so everything needed to show the weather is in the record
  # rather than an index into the list.
  def serialize
    {
      'name'      => @name,
      'country'   => @country_name,
      'code'      => @country_code,
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
          country_code: hash['code'].to_s,
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
