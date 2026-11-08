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

  # Upstream's GetInitialResultSetAsync: if a fetch is already in flight, the
  # query waits for WorldModel's notify::loading to clear before it runs, so a
  # query issued right after D-Bus activation does not race the locations
  # still being loaded. With a block, the result is handed to it once ready
  # (which may be later, if a wait was needed); with none, the call blocks on
  # nothing and simply returns the result computed right now — the shape
  # test/check_search_provider.rb exercises directly, against a model double
  # that is never loading.
  def initial_result_set(terms, &block)
    wait_for_loading(block) { ranked_result_set(terms) }
  end

  # Upstream has no separate async wrapper for GetSubsearchResultSet (it is
  # plain, synchronous JS there), but the same race applies here for the same
  # reason, so this port waits on it too.
  def subsearch_result_set(previous_results, terms, &block)
    wait_for_loading(block) { subsearch_narrowed(previous_results, terms) }
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
        initial_result_set(parameters[0]) { |ids| invocation.return_value(string_array(ids)) }
      when 'GetSubsearchResultSet'
        subsearch_result_set(parameters[0], parameters[1]) { |ids| invocation.return_value(string_array(ids)) }
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

    # If the model is mid-fetch, waits for its loading flag to clear before
    # yielding +compute+ — once, via WorldModel#on_loading_changed — and hands
    # the result to +block+ if there is one; otherwise computes and hands back
    # (or returns) the result immediately. Mirrors upstream's
    # `if (model?.loading) { model.connect('notify::loading', …) } else { … }`.
    def wait_for_loading(block, &compute)
      if @model.loading?
        fired = false
        @model.on_loading_changed do |loading|
          if !loading && !fired
            fired = true
            block&.call(compute.call)
          end
        end
        nil
      elsif block
        block.call(compute.call)
      else
        compute.call
      end
    end

    def ranked_result_set(terms) = normalized(terms).then { |needles| needles.empty? ? [] : ranked(needles).first(MAX_RESULTS) }

    def subsearch_narrowed(previous_results, terms)
      normalized(terms).then do |needles|
        Array(previous_results).select { |id| matches?(@model.at_index(id.to_i), needles) }.first(MAX_RESULTS)
      end
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
            'icon'        => icon_for(info),
          }
        end
      end
    end

    # Upstream's "%s, %s" % [conditions, temp], e.g. "Clear sky, 14°".
    def description_for(info) = format('%s, %s', Util.weather_conditions(info), Util.temp_string(info))

    # Upstream's `icon: new Gio.ThemedIcon({name: info.get_icon_name()}).serialize()`.
    # lib/weather_widget.rb resolves the same "-symbolic" name for a
    # WeatherInfo's icon_name when it paints the conditions image; GThemedIcon's
    # own serialize() adds its plain (non-"-symbolic") form as a fallback name
    # (confirmed live: Gio::ThemedIcon.new('weather-clear-symbolic').serialize
    # returns ["themed", ["weather-clear-symbolic", "weather-clear"]]), which is
    # exactly the (sv) shape quoted into GVariant text below.
    def icon_for(info)
      names = [quote("#{info.icon_name}-symbolic"), quote(info.icon_name)].join(', ')
      GLib::Variant.parse(format('("themed", <[%s]>)', names), '(sv)')
    end

    # Reply variants are built by parsing GVariant text: GLib::Variant.new in
    # these bindings cannot construct a dictionary (raises NotImplementedError
    # for a{sv}) or the tuple a D-Bus reply needs, while GLib::Variant.parse
    # handles both.
    def string_array(values) = GLib::Variant.parse("([#{values.map { |v| quote(v) }.join(', ')}],)", '(as)')

    def metas_variant(metas) = GLib::Variant.parse("([#{metas.map { |meta| meta_text(meta) }.join(', ')}],)", '(aa{sv})')

    def meta_text(meta) = "{#{meta.map { |key, value| "#{quote(key)}: <#{variant_value_text(value)}>" }.join(', ')}}"

    # The icon field is already a GLib::Variant of type (sv) (see icon_for);
    # its own #to_s is already valid GVariant text and must be spliced in as
    # one, not re-quoted as a plain string the way every other field's value
    # is.
    def variant_value_text(value) = value.is_a?(GLib::Variant) ? value.to_s : quote(value)

    def quote(value) = %("#{value.to_s.gsub(/[\\"]/) { |char| ESCAPES.fetch(char) }}")
end
