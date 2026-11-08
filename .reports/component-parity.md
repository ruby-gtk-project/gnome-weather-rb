# Component parity — gnome-weather-rb

| | |
|---|---|
| Upstream | `main` @ `6930d4a` |
| Port | `ruby` @ `ce70e77` |
| Units with full (4-axis) parity | 18 / 21 |
| Units entirely absent | 1 / 21 |
| Units present with confirmed gaps | 2 / 21 (search provider, background service's activation path) |

Since the `a52fce1` round, three of the four previously-absent units
landed: shell integration, the search provider and the background service.
This is real, substantial progress, verified live below — but it is not
clean. Re-auditing it adversarially (rather than taking the new files' own
code comments at their word) finds two confirmed behavioural gaps and one
confirmed missing activation path that make the search provider not actually
reachable from a cold GNOME Shell the way upstream's is.

The 18 "present, with parity" units were driven live under:

```
nix develop --command xvfb-run -a ruby test/check_model.rb              — 42/42
nix develop --command xvfb-run -a ruby test/check_search_provider.rb    — 12/12
nix develop --command xvfb-run -a ruby test/drive_window.rb             — 42/42 (3 of 4 runs this session; see note below)
nix develop --command xvfb-run -a ruby test/drive_dbus_integration.rb   — 12/12
nix develop --command xvfb-run -a ruby test/drive_background_service.rb — 2/2
```

**A flake observed and not dismissed.** Run once in parallel with
`drive_dbus_integration.rb` on the same machine, `drive_window.rb` failed
41/42 ("failed check: info page is showing again"); run three more times
sequentially afterward it passed 42/42 every time. The likely cause is
resource contention from two concurrent `xvfb-run`/GTK processes sharing one
machine during this audit, not a reproduced app bug — but that is a
hypothesis, not a demonstrated root cause, and it was not tracked down
further. Recorded here rather than silently treated as "just noise": a drive
suite that can report 0 failures on one invocation and 1 on another is, per
this round's own runtime gate framing, a result that deserves a named cause
before it is trusted, and currently does not have one.

## Units with parity

| Unit | Upstream → Port | Verdict |
|---|---|---|
| Main window | `src/app/window.ts`+`.ui` → `lib/window.rb` | parity |
| Primary menu | `data/window.ui` menu → `lib/primary_menu.rb` | parity |
| About dialog | `window.ts#showAbout` → `lib/about_dialog.rb` | parity |
| City page shell | `city.ts` (`WeatherView`) → `lib/weather_view.rb` | parity |
| Weather page | `city.ts` (`WeatherWidget`) → `lib/weather_widget.rb` | parity, 2 asset substitutions (unchanged, see component-identification.md) |
| Places popover | `world.ts`+`.ui` → `lib/world_content_view.rb` | parity |
| Search entry (in-window) | `entry.ts` → `lib/location_search_entry.rb` | parity |
| Location row | `locationRow.ts`+`.ui` → `lib/location_row.rb` | parity |
| Hourly strip | `hourlyForecast.ts` → `lib/hourly_forecast_box.rb` | parity |
| Hour cell | `hourlyForecast.ts`+`.ui` → `lib/hour_entry.rb` | parity |
| Daily strip | `dailyForecast.ts` → `lib/daily_forecast_box.rb` | parity |
| Day cell + popover | `dailyForecast.ts`+`.ui` → `lib/day_entry.rb` | parity, 1 asset substitution |
| Thermometer | `thermometer.ts` → `lib/thermometer.rb` | parity, label layout differs (noted, not a behaviour gap) |
| World model | `shared/world.ts` → `lib/world_model.rb` | parity |
| Util | `misc/util.ts` → `lib/util.rb` | parity, 3 helpers dropped, correspondence |
| Stylesheet | `style*.css` → `lib/styles.rb` | parity |
| App/actions | `src/app/application.ts` → `lib/main.rb` | parity — `app.show-location`/`app.show-search` now exist, closing last round's gap (see below) |
| Shell integration | `src/app/shell.ts` → `lib/shell_integration.rb` | parity, verified live over the real bus (`drive_dbus_integration.rb`) |

## App/actions — `lib/main.rb` — gap closed, re-verified

| Item | Upstream | Port | Verdict |
|---|---|---|---|
| `app.quit` (`Ctrl+Q`) | yes | yes | parity |
| `app.temperature-unit` (stateful) | yes, mirrors `org.gnome.GWeather4` | yes, own settings only | correspondence, unchanged |
| `app.show-location` | yes | **yes**, `GLib::VariantType.new('v')` parameter | parity — driven live in `drive_dbus_integration.rb` ("drive the show-location action") and `drive_background_service.rb` (over a real `ActivateAction` round trip between two processes) |
| `app.show-search` | yes | **yes**, `GLib::VariantType.new('s')` parameter | parity — driven live in `drive_dbus_integration.rb` |
| `win.selection-mode` / `win.select-all` accels | yes, but dead upstream too (no actions behind them) | absent | still a gap, still inert either way — unchanged from last round |
| `devel` CSS class / `Devel` app-id profile | yes | absent | still a gap — unchanged from last round, see `component-identification.md` |

## Shell integration — `lib/shell_integration.rb` — parity

Interface, property names and the `PropertiesChanged` announce-on-change
behaviour all match upstream's `shell.ts`. `locations` is driven off
`Settings#watch('locations')` in place of upstream's
`changed::locations` GSettings signal — a correspondence, since this port's
`Settings` is the JSON-backed stand-in and genuinely has no GSettings signal
to connect to instead. Verified live end to end: `drive_dbus_integration.rb`
reads `AutomaticLocation` and `Locations` back over a **real**
`org.freedesktop.DBus.Properties.Get` call on the app's own connection
(not a direct Ruby method call), both before and after a location is added via
`show-location`, and gets the right answer both times.

## Search provider — `lib/search_provider.rb` — two confirmed gaps

The provider's ranking, subsearch narrowing and activate/launch callbacks are
correct and are driven both directly (`check_search_provider.rb`, 12/12) and
over a real D-Bus round trip through `background_service.rb`
(`drive_background_service.rb`'s `GetInitialResultSet` check). Two things are
not parity, confirmed by reading `search_provider.ts` against
`lib/search_provider.rb` line by line:

1. **`GetResultMetas` drops the result icon.** Upstream's `GetResultMetas`
   returns four fields per result — `name`, `id`, `description`, and `icon`
   (a serialized `Gio.ThemedIcon` built from `info.get_icon_name()`). The
   port's `meta_for` builds only three: `id`, `name`, `description`
   (`lib/search_provider.rb`, the `meta_for` method). A real GNOME Shell
   overview search result for this app would show no weather glyph next to
   the name/description, where upstream's shows one. This is not a binding
   limitation — nothing stops the hash literal from gaining an `'icon'` key —
   it is a dropped field, and no report, comment or test in this fork says so
   anywhere before this one.

2. **No wait on `WorldModel#loading` before answering a query.** Upstream's
   `GetInitialResultSetAsync` explicitly checks `model.loading` and, if a
   fetch is in flight, waits for `notify::loading` to go false before running
   the query (`searchProvider.ts`'s `GetInitialResultSetAsync`). The port's
   `initial_result_set` calls `ranked(needles)` immediately with no check of
   `@model.loading?` at all (confirmed: `grep -n loading lib/search_provider.rb`
   returns nothing) even though `WorldModel` tracks exactly this flag
   (`lib/world_model.rb`'s `loading?`/`on_loading_changed`, used by
   `lib/main.rb` and `lib/window.rb` but not by the search provider). A
   real GNOME Shell search issued immediately after D-Bus-activating this
   app's background service — exactly the moment a search provider is most
   likely to be invoked — races an in-flight fetch instead of waiting for it,
   diverging from upstream's deliberate ordering.

Neither gap is caught by any existing test: `check_search_provider.rb`'s
fixture (`FakeModel`) has no concept of `loading` at all, and none of its 12
checks reads the `icon` key because the port never writes one to miss.

## Background service — `lib/background_service.rb` — present, but its
## activation path is a confirmed gap, and most of its own surface is
## unverified by any check

Driven live, `drive_background_service.rb` passes 2/2 — but those 2 checks
cover exactly two of the service's methods (`GetInitialResultSet`,
`ActivateResult`) out of five on the interface. `GetSubsearchResultSet`,
`GetResultMetas` and `LaunchSearch` are never called over the real bus by any
test in this tree; `GetResultMetas` specifically cannot be, by the test's own
admission (see its comment: ruby-gnome's `call_finish` cannot deep-unpack an
`aa{sv}` reply at all, confirmed by direct reproduction in this audit — the
call raises `NotImplementedError: TODO: GVariant({sv}) -> Ruby` from inside
`GObjectIntrospection::MethodInfo#invoke`). This is **not** a bug the real
app will hit, because the real D-Bus client is GNOME Shell's own GJS/C code,
not a Ruby client — but it does mean the wire-format correctness of
`GetResultMetas`, the one method that actually produces what the user sees in
a search result, is verified **only** by calling the Ruby method directly
(`check_search_provider.rb`), never by actually marshaling it onto a bus and
back. 2 of 5 interface methods driven live is a narrow drive run in exactly
the sense this round's task framing warns about: a component no check
exercises over the real transport is unverified, not done.

Separately, and more seriously: **nothing in the port makes GNOME Shell able
to start this service in the first place.** Upstream ships
`data/org.gnome.Weather.search-provider.ini.in` (tells Shell's search
framework the provider exists and which D-Bus name/object path to talk to)
and `data/org.gnome.Weather.BackgroundService.service.in` (tells the session
bus how to D-Bus-activate the process on demand). Confirmed absent from the
port tree (`component-identification.md`). Without them, `exe/gnome-weather-
search-provider` only ever runs if something already knows to launch it by
hand — which is exactly what every test in this tree does
(`built_service.register(nil)` inside the test script itself). A real,
freshly-installed copy of this port gives GNOME Shell no way to ever start
the search provider, so typing a city into the overview would find nothing,
same as before this round's work landed, for a different reason than before.
This is tracked here because it is a gap in the unit's own right, not a
restatement of the `.ini`/`.service` row already in
`component-identification.md`'s asset table — the asset being missing *is*
the reason the rest of this unit's new, real, well-tested code is currently
unreachable in production.

## Units entirely absent

| Unit | Upstream file(s) | What a user loses |
|---|---|---|
| Geolocation | `src/app/currentLocationController.ts` | The device's current city is never auto-added; `LocationRow`'s `find-location-symbolic` "this is you" icon can never appear, ever, for any user. |

## Overall verdict

**18 of 21 upstream units have four-axis parity, verified live**, up from
17/21 last round — real progress, not a relabeling. But two of the three
newly-landed units carry confirmed, previously-unreported gaps: the search
provider silently drops the result icon and never waits on the loading flag,
and the background service — despite having real, live-driven D-Bus code —
ships with no activation files, so nothing outside this test suite can ever
start it. Component parity is **not** reported as finished.
