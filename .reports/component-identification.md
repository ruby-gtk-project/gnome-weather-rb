# Component identification — gnome-weather-rb

| | |
|---|---|
| Upstream | `origin/main` @ `6930d4a` |
| Port | `ruby` @ `ce70e77` |

This report records the raw inventory step. The judged, axis-by-axis
comparison (and the remaining gaps) is in `component-parity.md`; this file
exists so the counts behind that comparison are reproducible.

Since the last round (`a52fce1`), `ce70e77` ("Port shell integration, search
provider, and background service") landed three of the four previously-absent
units: `lib/shell_integration.rb`, `lib/search_provider.rb`,
`lib/background_service.rb`, plus a rewritten `lib/main.rb` carrying
`app.show-location`/`app.show-search`. This file's unit table and the
"Non-widget assets" table below are re-verified against the current tree, not
carried over from the stale `a52fce1` snapshot.

## Upstream unit list (one `.ts` class, or `.ts` + `.ui` pair, per unit)

21 component units total (14 of them widgets), 1 menu model, 3 stylesheets,
1 GSettings schema, 1 `po/` catalogue of 87 languages:

| Upstream unit | Port file | State |
|---|---|---|
| `src/app/main.ts` | `lib/main.rb` (folded in) | present |
| `src/app/application.ts` | `lib/main.rb` | present, with gaps (see component-parity.md) |
| `src/app/window.ts` + `data/window.ui` | `lib/window.rb` | present |
| `data/window.ui` `primary-menu` | `lib/primary_menu.rb` | present |
| `src/app/window.ts#showAbout` | `lib/about_dialog.rb` | present |
| `src/app/city.ts` (`WeatherView`) + `data/city.ui` | `lib/weather_view.rb` | present |
| `src/app/city.ts` (`WeatherWidget`) + `data/weather-widget.ui` | `lib/weather_widget.rb` | present |
| `src/app/world.ts` + `data/places-popover.ui` | `lib/world_content_view.rb` | present |
| `src/app/entry.ts` | `lib/location_search_entry.rb` | present |
| `src/app/locationRow.ts` + `.ui` | `lib/location_row.rb` | present |
| `src/app/hourlyForecast.ts` (`HourlyForecastBox`) | `lib/hourly_forecast_box.rb` | present |
| `src/app/hourlyForecast.ts` (`HourEntry`) + `.ui` | `lib/hour_entry.rb` | present |
| `src/app/dailyForecast.ts` (`DailyForecastBox`) | `lib/daily_forecast_box.rb` | present |
| `src/app/dailyForecast.ts` (`DayEntry`) + `.ui` | `lib/day_entry.rb` | present |
| `src/app/thermometer.ts` | `lib/thermometer.rb` | present |
| `src/shared/world.ts` (`WorldModel`) | `lib/world_model.rb` | present |
| `src/misc/util.ts` | `lib/util.rb` | present, two helpers not carried over |
| `src/app/shell.ts` + `data/ShellWeatherIntegration.xml` | `lib/shell_integration.rb` | **now present** — see component-parity.md |
| `src/service/main.ts` | `lib/background_service.rb` | **now present** — see component-parity.md |
| `src/service/searchProvider.ts` + `data/ShellSearchProvider2.xml` | `lib/search_provider.rb` | **now present**, with gaps — see component-parity.md |
| `src/app/currentLocationController.ts` | — | **still absent** — no `lib/current_location_controller.rb`, `find lib -iname '*location_controller*'` and `grep -rn Geoclue lib/` both return nothing |

Confirmed directly: `lib/location.rb` now backs onto a real `GWeather::Location`
world tree (the `libgweather` gem's typelib loads and `GWeather::Location.world`
walks the real database — `flake.nix` wires `libgweather` into `gtkStack` and
`gnome-weather-rb.gemspec` depends on it `~> 1.0`). This supersedes the prior
round's framing that "no GWeather [is] reachable": GWeather *is* reachable and
*is* used for the world database. What is still true, and still a
correspondence rather than a gap, is that `temperature-unit` does not live in
`org.gnome.GWeather4`'s schema — it is one of this port's own JSON-backed
settings (see `lib/settings.rb`'s own comment on this, unchanged this round).

## Non-widget assets

| Upstream asset | Port | Present |
|---|---|---|
| `data/style.css`, `style-dark.css`, `style-hc.css` | `lib/styles.rb` (Ruby heredoc, `Gtk::CssProvider`) | yes |
| `data/org.gnome.Weather.gschema.xml` | `lib/settings.rb` (JSON file, same keys) | yes (substituted storage, same keys — correspondence) |
| `data/ShellWeatherIntegration.xml` | `lib/shell_integration.rb::NODE_XML` | yes, same interface/property names |
| `data/ShellSearchProvider2.xml` | `lib/search_provider.rb::NODE_XML` | yes, same interface/method names |
| `data/org.gnome.Weather.desktop.in.in` | — | **no** — still no desktop file anywhere in the port |
| `data/org.gnome.Weather.metainfo.xml.in.in` | — | **no** |
| `data/org.gnome.Weather.search-provider.ini.in`, `.service.in`, `BackgroundService.service.in` | — | **no** — confirmed: `find . -iname '*.service.in' -o -iname '*.ini.in'` returns nothing in the port. These are what actually let D-Bus *activate* the service/search-provider process on demand; without them, `lib/background_service.rb` only ever runs if something launches `exe/gnome-weather-search-provider` by hand (see `component-parity.md`) |
| `data/icons/**` (35 status icons + app icons) | — | **no** — confirmed: `find . -ipath '*icons*'` returns nothing in the port tree |
| `po/` (87 `.po` files, `LINGUAS`) | — | **no** — confirmed: no `po/` directory, no gettext dependency, no `_()`/`gettext` call anywhere in `lib/` |
| `tests/world_view.py`, `tests/testutil.py` | — | **no**, see `test-parity.md` |

## CSS classes: upstream has, port does not

```
devel
```

Read by hand, unchanged this round: upstream's `data/window.ui` adds the
`devel` class to the window root only when the running profile's app id ends
in `Devel`. `lib/window.rb` and `lib/main.rb` (`APP_ID = 'org.gnome.WeatherRb'`,
no `Devel` variant anywhere) still have no development-profile distinction —
real, if minor, gap, carried over unresolved from the previous round.

## New surfaces introduced this round, and what they add to the inventory

- `lib/shell_integration.rb` — 1 exported D-Bus object, 2 properties
  (`AutomaticLocation`, `Locations`), 1 `PropertiesChanged` signal path, driven
  by `@settings.watch('locations')` in place of upstream's
  `changed::locations`.
- `lib/search_provider.rb` — 1 exported D-Bus object, 5 interface methods
  (`GetInitialResultSet`, `GetSubsearchResultSet`, `GetResultMetas`,
  `ActivateResult`, `LaunchSearch`).
- `lib/background_service.rb` — a second `Gio::Application` process
  (`org.gnome.WeatherRb.SearchProvider`, `IS_SERVICE`), its own `WorldModel`,
  one `quit` action, and the two outbound `ActivateAction` calls
  (`show-location`, `show-search`) back into the windowed app.
- `exe/gnome-weather-search-provider` — the second process's entry point.

Axis-by-axis comparison of all of the above, including two confirmed gaps
(a dropped `icon` field on `GetResultMetas`, and no wait on `WorldModel#loading`
before answering a query), is in `component-parity.md`.
