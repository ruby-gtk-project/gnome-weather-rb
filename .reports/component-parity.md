# Component parity — gnome-weather-rb

| | |
|---|---|
| Upstream | `main` @ `6930d4a` |
| Port | `ruby` @ `a52fce1` |
| Units with full (4-axis) parity | 17 / 21 |
| Units entirely absent | 4 / 21 |

The 17 "present" units below were driven live under
`nix develop --command xvfb-run -a ruby test/drive_window.rb` (41/41 checks)
and `ruby test/check_model.rb` (42/42 checks) — the behaviour axis for the
window, forecast pages, places popover, search, unit switch, About dialog and
world model is not a static read, it was exercised. The CSS axis was checked
by diffing `lib/styles.rb`'s heredoc against `data/style.css` /
`style-dark.css` / `style-hc.css` directly.

## Units with parity

| Unit | Upstream → Port | Verdict |
|---|---|---|
| App/actions | `src/app/application.ts` → `lib/main.rb` | **gap**, see below |
| Main window | `src/app/window.ts`+`.ui` → `lib/window.rb` | parity |
| Primary menu | `data/window.ui` menu → `lib/primary_menu.rb` | parity |
| About dialog | `window.ts#showAbout` → `lib/about_dialog.rb` | parity |
| City page shell | `city.ts` (`WeatherView`) → `lib/weather_view.rb` | parity |
| Weather page | `city.ts` (`WeatherWidget`) → `lib/weather_widget.rb` | parity, 2 asset substitutions noted below |
| Places popover | `world.ts`+`.ui` → `lib/world_content_view.rb` | parity |
| Search entry | `entry.ts` → `lib/location_search_entry.rb` | parity |
| Location row | `locationRow.ts`+`.ui` → `lib/location_row.rb` | parity |
| Hourly strip | `hourlyForecast.ts` → `lib/hourly_forecast_box.rb` | parity, incl. cairo spline |
| Hour cell | `hourlyForecast.ts`+`.ui` → `lib/hour_entry.rb` | parity |
| Daily strip | `dailyForecast.ts` → `lib/daily_forecast_box.rb` | parity |
| Day cell + popover | `dailyForecast.ts`+`.ui` → `lib/day_entry.rb` | parity, 1 asset substitution |
| Thermometer | `thermometer.ts` → `lib/thermometer.rb` | parity, label layout differs (noted, not a behaviour gap) |
| World model | `shared/world.ts` → `lib/world_model.rb` | parity |
| Util | `misc/util.ts` → `lib/util.rb` | parity, 3 helpers dropped (see below) |
| Stylesheet | `style*.css` → `lib/styles.rb` | parity |

## App/actions — `lib/main.rb` — **gap**

| Item | Upstream | Port | Verdict |
|---|---|---|---|
| `app.quit` (`Ctrl+Q`) | yes | yes | parity |
| `app.temperature-unit` (stateful) | yes, mirrors `org.gnome.GWeather4` | yes, own settings only | correspondence (no GWeather reachable — `FINDINGS.md`-class issue, not a behaviour gap by itself) |
| `app.show-location` | yes | **absent** | **gap** — the search provider's `ActivateResult` has nothing to call |
| `app.show-search` | yes | **absent** | **gap** — the search provider's `LaunchSearch` has nothing to call |
| `win.selection-mode` accel (`Escape`) | yes (dead: no action installed upstream either) | **absent** | **gap**, but inert either way — reproducing it would do nothing on either side |
| `win.select-all` accel (`<Control>a`) | yes (dead, same as above) | **absent** | **gap**, same note |
| `window.close` accel (`<Control>w`) | yes | yes | parity |
| `win.refresh` accels (`F5`, `<Control>r`) | yes | yes | parity, verified live (drive check "setting written" / refresh flow) |
| `devel` CSS class on window when app id ends `Devel` | yes | **absent** — no devel profile/app-id distinction built | **gap** |

Correction to `.reports/component-inventory.md`: that earlier report's
"Things that bit the port" section says the dead `win.selection-mode` /
`win.select-all` accelerators were **"kept for parity, no actions behind
them"**, while its own per-unit section for `application.ts` says the
opposite — "the dead accels ... are not reproduced". Grepping the port
confirms the second sentence: `grep -rn "selection-mode\|select-all"
lib/*.rb` returns nothing. **The "kept for parity" line is false** and is
called out again in `accountability-ensurance.md`.

## Weather page — `lib/weather_widget.rb` — asset substitutions, not gaps

Two icon-asset differences, both forced by the absence of
`data/icons/**` in the port (see `component-identification.md`):
`conditionsImage` and the hour/day cell images request `-symbolic` icon
variants instead of upstream's `-large`/`-small` raster-style icons, because
those are not shipped. Visually this is a real, user-visible difference
(no coloured weather glyphs, symbolic monochrome icons instead) but it is
downstream of one root cause — the missing icon set — not an independent
per-widget gap. Tracked once, under "Non-widget assets" in
`component-identification.md`.

## Day cell — `lib/day_entry.rb` — one substitution

The popover's temperature column is headed by a degree sign instead of the
`temperature-symbolic` icon, same root cause as above.

## Thermometer — `lib/thermometer.rb` — layout difference, not a behaviour gap

Upstream positions the high/low labels along the gradient bar at the point
their temperature falls; the port packs them as a fixed pair beside the bar.
Both show the right numbers and the right bar; the spatial correspondence
between label and bar position is lost. Driven check "the thermometer has a
range" passes either way because it only asserts the range is non-nil — this
is a real gap the drive suite does not catch, recorded here rather than
claimed covered.

## Util — `lib/util.rb` — three helpers not carried over

`loadUI`, `arrayEqual` and `getSettings` have no port equivalent.
`loadUI` and `getSettings` are GResource/GSettings plumbing with no
behaviour of their own once the port's widgets are built in Ruby and its
settings are a JSON file (correspondence, not a gap — nothing a user can
see is missing). `arrayEqual` is used upstream to decide whether the saved
locations list actually changed before re-rendering; grep confirms
`lib/world_model.rb` doesn't need it because it rebuilds via a
`Gio::ListStore` diff instead. Correspondence.

## Units entirely absent

| Unit | Upstream file(s) | What a user loses |
|---|---|---|
| Geolocation | `src/app/currentLocationController.ts` | The device's current city is never auto-added; `LocationRow`'s `find-location-symbolic` "this is you" icon can never appear, ever, for any user. |
| Shell integration | `src/app/shell.ts` + `data/ShellWeatherIntegration.xml` | `org.gnome.Shell.WeatherIntegration` D-Bus object is never exported — GNOME Shell's own weather applet/lock-screen widget has nothing to read from this app. |
| Background service | `src/service/main.ts` | No `org.gnome.Weather.BackgroundService`; nothing keeps weather data warm outside the open window. |
| Search provider | `src/service/searchProvider.ts` + `data/ShellSearchProvider2.xml` | Typing a city into GNOME Shell's overview search returns nothing from this app — upstream's whole reason for having `app.show-location`/`app.show-search`. |

None of these four has a port file, a stub, or a TODO naming them anywhere
outside the (accurate) `.reports/component-inventory.md` entry that already
calls them "Absent." They are not disguised; they are open. Component
parity on these four units is 0%.

## Overall verdict

**17 of 21 upstream units have four-axis parity, verified live.** The
remaining 4 are not degraded versions of a feature — they are the feature
entirely missing, plus the two actions (`app.show-location`,
`app.show-search`) and the `devel` CSS class that depend on them or on a
profile distinction the port never built. Component parity is **not**
reported as finished.
