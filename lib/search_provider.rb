# frozen_string_literal: true

require 'gio2'
require_relative 'util'

# SearchProvider answers GNOME Shell's org.gnome.Shell.SearchProvider2 for
# this app's locations, letting the overview search show their current
# weather without the app's window open.
#
# Ported from upstream's src/service/searchProvider.ts, together with the
# interface it exports, data/ShellSearchProvider2.xml:
#
#   GetInitialResultSet(as)       -> as      ids matching the terms
#   GetSubsearchResultSet(as, as) -> as      same, narrowed to previous_results
#   GetResultMetas(as)            -> aa{sv}  name/id/description per result
#   ActivateResult(s, as, u)                 show-location on the running app
#   LaunchSearch(as, u)                      show-search on the running app
#
# A result's id is its index into WorldModel#all, exactly as upstream's
# nameRet/cityRet/countryRet hand back `index.toString()`. Upstream ranks a
# name match above a city match above a country match; this port's Location
# has no separate city field from its name (the name *is* the city for a
# CITY-level place, see lib/location.rb), so the ranking collapses to two
# buckets: a name match, then a country-only match.
class SearchProvider
  INTERFACE = 'org.gnome.Shell.SearchProvider2'
  MAX_RESULTS = 20

  NODE_XML = <<~XML
    <node>
      <interface name="org.gnome.Shell.SearchProvider2">
        <method name="GetInitialResultSet">
          <arg type="as" name="terms" direction="in"/>
          <arg type="as" name="results" direction="out"/>
        </method>
        <method name="GetSubsearchResultSet">
          <arg type="as" name="previous_results" direction="in"/>
          <arg type="as" name="terms" direction="in"/>
          <arg type="as" name="results" direction="out"/>
        </method>
        <method name="GetResultMetas">
          <arg type="as" name="identifiers" direction="in"/>
          <arg type="aa{sv}" name="metas" direction="out"/>
        </method>
        <method name="ActivateResult">
          <arg type="s" name="identifier" direction="in"/>
          <arg type="as" name="terms" direction="in"/>
          <arg type="u" name="timestamp" direction="in"/>
        </method>
        <method name="LaunchSearch">
          <arg type="as" name="terms" direction="in"/>
          <arg type="u" name="timestamp" direction="in"/>
        </method>
      </interface>
    </node>
  XML

  ESCAPES = { '\\' => '\\\\', '"' => '\\"' }.freeze

  def initialize(model, on_activate_location: nil, on_launch_search: nil)
    @model = model
    @on_activate_location = on_activate_location
    @on_launch_search = on_launch_search
  end

  def export(connection, path)
    connection.register_object(path, interface_info, method(:handle_method_call))
  rescue StandardError, GLib::Error => e
    warn "Could not export the search provider: #{e.message}"
    nil
  end

  # lookup_interface rather than interfaces.first: Gio::DBusNodeInfo#interfaces
  # returns unusable strings in these bindings, while #lookup_interface returns
  # the Gio::DBusInterfaceInfo wanted here.
  def interface_info = Gio::DBusNodeInfo.new(NODE_XML).lookup_interface(INTERFACE)

  # --- Interface methods -----------------------------------------------------

  def initial_result_set(terms)
    normalized(terms).then { |needles| needles.empty? ? [] : ranked(needles).first(MAX_RESULTS) }
  end

  def subsearch_result_set(previous_results, terms)
    normalized(terms).then do |needles|
      Array(previous_results).select { |id| matches?(@model.at_index(id.to_i), needles) }.first(MAX_RESULTS)
    end
  end

  def result_metas(ids) = Array(ids).filter_map { |id| meta_for(id) }

  def activate_result(id, _terms, _timestamp)
    @model.at_index(id.to_i).then { |info| @on_activate_location&.call(info.location) if info }
  end

  def launch_search(terms, _timestamp) = @on_launch_search&.call(terms.join(' '))

  private

    # parameters arrives already deep-unpacked to a plain Ruby Array by these
    # bindings (one entry per "in" arg, each an array or scalar matching its
    # D-Bus type), not a GLib::Variant to pick apart with get_child_value —
    # that method does not even exist on what register_object's method-call
    # closure actually hands back here.
    def handle_method_call(_connection, _sender, _path, _interface, method_name, parameters, invocation)
      case method_name
      when 'GetInitialResultSet'
        invocation.return_value(string_array(initial_result_set(parameters[0])))
      when 'GetSubsearchResultSet'
        invocation.return_value(string_array(subsearch_result_set(parameters[0], parameters[1])))
      when 'GetResultMetas'
        invocation.return_value(metas_variant(result_metas(parameters[0])))
      when 'ActivateResult'
        activate_result(parameters[0], parameters[1], parameters[2])
        invocation.return_value(nil)
      when 'LaunchSearch'
        launch_search(parameters[0], parameters[1])
        invocation.return_value(nil)
      else
        invocation.return_dbus_error("#{INTERFACE}.UnknownMethod", "Unknown method #{method_name}")
      end
    rescue StandardError => e
      invocation.return_dbus_error("#{INTERFACE}.Error", e.message)
    end

    def normalized(terms) = Array(terms).map { |t| Util.normalize_casefold_and_unaccent(t.to_s) }.reject(&:empty?)

    # Name matches sort before country-only matches, mirroring upstream's
    # nameRet/cityRet/countryRet concatenation order.
    def ranked(needles)
      indexed = @model.all.each_with_index
      name_matches = indexed.select { |info, _| name_haystack(info).then { |h| needles.all? { |n| h.include?(n) } } }
      country_matches = indexed.reject { |info, _| name_matches.any? { |m, _| m.equal?(info) } }
                                .select { |info, _| matches?(info, needles) }
      (name_matches + country_matches).map { |_, index| index.to_s }
    end

    def matches?(info, needles) = info && haystack(info).then { |h| needles.all? { |n| h.include?(n) } }

    def name_haystack(info) = Util.normalize_casefold_and_unaccent(info.location.name)

    def haystack(info) = Util.normalize_casefold_and_unaccent("#{info.location.name} #{info.location.country_name}")

    def meta_for(id)
      @model.at_index(id.to_i).then do |info|
        if info
          {
            'id'          => id.to_s,
            'name'        => info.location.name,
            'description' => description_for(info),
          }
        end
      end
    end

    # Upstream's "%s, %s" % [conditions, temp], e.g. "Clear sky, 14°".
    def description_for(info) = format('%s, %s', Util.weather_conditions(info), Util.temp_string(info))

    # Reply variants are built by parsing GVariant text: GLib::Variant.new in
    # these bindings cannot construct a dictionary (raises NotImplementedError
    # for a{sv}) or the tuple a D-Bus reply needs, while GLib::Variant.parse
    # handles both.
    def string_array(values) = GLib::Variant.parse("([#{values.map { |v| quote(v) }.join(', ')}],)", '(as)')

    def metas_variant(metas) = GLib::Variant.parse("([#{metas.map { |meta| meta_text(meta) }.join(', ')}],)", '(aa{sv})')

    def meta_text(meta) = "{#{meta.map { |key, value| "#{quote(key)}: <#{quote(value)}>" }.join(', ')}}"

    def quote(value) = %("#{value.to_s.gsub(/[\\"]/) { |char| ESCAPES.fetch(char) }}")
end
