# Component identification — gnome-weather-rb

| | |
|---|---|
| Upstream | `origin/main` @ `6930d4a` |
| Port | `ruby` @ `3edcfea` |

This report records the raw inventory step. The judged, axis-by-axis
comparison (and the remaining gaps) is in `component-parity.md`.

Since the previous round (`ce70e77`, "Port shell integration, search
provider, and background service"), `3edcfea` ("Close search-provider gaps,
add D-Bus activation files and Devel profile") landed: a themed `icon` field
on `GetResultMetas`, a `loading` wait in the search provider, a fix to
`background_service.rb`'s `call_main_app_action` double-wrapping (which had
silently dropped `LaunchSearch`), three D-Bus activation data files, and a
`Devel` app-id profile with its matching `devel` CSS class. Re-verified live
against the current tree, not carried over from the stale `ce70e77` snapshot.

## Upstream unit list (one `.ts` class, or `.ts` + `.ui` pair, per unit)

21 component units total (14 of them widgets), 1 menu model, 3 stylesheets,
1 GSettings schema, 1 `po/` catalogue of 100 languages (`po/LINGUAS`):

| Upstream unit | Port file | State |
|---|---|---|
| `src/app/main.ts` | `lib/main.rb` (folded in) | present |
| `src/app/application.ts` | `lib/main.rb` | present, one unchanged gap (see component-parity.md) |
| `src/app/window.ts` + `data/window.ui` | `lib/window.rb` | present |
| `data/window.ui` `primary-menu` | `lib/primary_menu.rb` | present |
| `src/app/window.ts#showAbout` | `lib/about_dialog.rb` | present |
| `src/app/city.ts` (`WeatherView`) + `data/city.ui` | `lib/weather_view.rb` | present |
| `src/app/city.ts` (`WeatherWidget`) + `data/weather-widget.ui` | `lib/weather_widget.rb` | present, 2 asset substitutions |
| `src/app/world.ts` + `data/places-popover.ui` | `lib/world_content_view.rb` | present |
| `src/app/entry.ts` | `lib/location_search_entry.rb` | present |
| `src/app/locationRow.ts` + `.ui` | `lib/location_row.rb` | present |
| `src/app/hourlyForecast.ts` (`HourlyForecastBox`) | `lib/hourly_forecast_box.rb` | present |
| `src/app/hourlyForecast.ts` (`HourEntry`) + `.ui` | `lib/hour_entry.rb` | present |
| `src/app/dailyForecast.ts` (`DailyForecastBox`) | `lib/daily_forecast_box.rb` | present |
| `src/app/dailyForecast.ts` (`DayEntry`) + `.ui` | `lib/day_entry.rb` | present, 1 asset substitution |
| `src/app/thermometer.ts` | `lib/thermometer.rb` | present |
| `src/shared/world.ts` (`WorldModel`) | `lib/world_model.rb` | present |
| `src/misc/util.ts` | `lib/util.rb` | present, two helpers not carried over |
| `src/app/shell.ts` + `data/ShellWeatherIntegration.xml` | `lib/shell_integration.rb` | present |
| `src/service/main.ts` | `lib/background_service.rb` | present |
| `src/service/searchProvider.ts` + `data/ShellSearchProvider2.xml` | `lib/search_provider.rb` | present — last round's two confirmed gaps (dropped icon, no loading wait) are both fixed this round, re-verified live below |
| `src/app/currentLocationController.ts` | — | **still absent** — no `lib/current_location_controller.rb`; `find lib -iname '*location_controller*'` and `grep -rn Geoclue lib/` both return nothing |

Confirmed directly (unchanged): `lib/location.rb` backs onto a real
`GWeather::Location` world tree via the `libgweather` gem. `temperature-unit`
remains a correspondence, not a gap: it lives in this port's own JSON-backed
`Settings`, not in `org.gnome.GWeather4`'s schema, per `lib/settings.rb`'s own
comment.

## Non-widget assets

| Upstream asset | Port | Present |
|---|---|---|
| `data/style.css`, `style-dark.css`, `style-hc.css` | `lib/styles.rb` (Ruby heredoc, `Gtk::CssProvider`) | yes |
| `data/org.gnome.Weather.gschema.xml` | `lib/settings.rb` (JSON file, same keys) | yes (substituted storage, same keys — correspondence) |
| `data/ShellWeatherIntegration.xml` | `lib/shell_integration.rb::NODE_XML` | yes, same interface/property names |
| `data/ShellSearchProvider2.xml` | `lib/search_provider.rb::NODE_XML` | yes, same interface/method names |
| `data/org.gnome.Weather.search-provider.ini.in` | `data/org.gnome.WeatherRb.search-provider.ini` | **yes, new this round** — confirmed present, read, names `BusName`/`ObjectPath` matching `background_service.rb` |
| `data/org.gnome.Weather.BackgroundService.service.in` | `data/org.gnome.WeatherRb.SearchProvider.service` | **yes, new this round** |
| `data/org.gnome.Weather.service.in` | `data/org.gnome.WeatherRb.service` | **yes, new this round** |
| `data/org.gnome.Weather.desktop.in.in` | — | **no** — confirmed: `find . -iname '*.desktop*'` returns nothing in the port. No application-launcher entry exists at all; a freshly-installed copy of this port has no icon or menu entry a user can click, independent of the search-provider's own activation gap |
| `data/org.gnome.Weather.metainfo.xml.in.in` | — | **no** — confirmed: `find . -iname '*metainfo*'` returns nothing. No AppStream entry means no software-center listing, screenshots or description |
| `data/icons/**` (35 status/app icons, 2 app ids: regular + `WeatherDevel`) | — | **no** — confirmed: `find . -ipath '*icons*'` (outside `.git`) returns nothing in the port tree. Every icon the port shows is resolved from the system Adwaita/hicolor theme by name, documented in `lib/hour_entry.rb`/`lib/day_entry.rb`'s own comments, but the app's own identity icon (taskbar/launcher) and the Devel variant's distinct icon do not exist anywhere in this tree |
| `po/` (100 `.po` files, `LINGUAS`) | — | **no** — confirmed: no `po/` directory, no gettext dependency (`gem 'gettext'`/`'fast_gettext'`), no `_()`/`gettext()` call anywhere in `lib/`. See `translation-parity.md` |
| `tests/world_view.py`, `tests/testutil.py` | — | ported — `test/drive_window.rb`'s step 6 now explicitly names and asserts every `world_view.py` check, see `test-parity.md` |

## CSS classes: upstream has, port now has too (gap closed)

```
devel
```

Confirmed this round: `lib/window.rb` adds `devel` to the window root when
`@app_id.end_with?('Devel')`, and `lib/main.rb` derives `@app_id` from
`DEVEL_APP_ID` when `ENV['GNOME_WEATHER_APP_ID']` matches it, mirroring
upstream's build-time `pkg.name?.endsWith('Devel')` check with a run-time
environment-variable substitute (documented in both files' own comments).
This closes the gap the previous two rounds carried as open.

## Surfaces introduced across the last two rounds, current state

- `lib/shell_integration.rb` — 1 exported D-Bus object, 2 properties
  (`AutomaticLocation`, `Locations`), 1 `PropertiesChanged` signal path.
- `lib/search_provider.rb` — 1 exported D-Bus object, 5 interface methods
  (`GetInitialResultSet`, `GetSubsearchResultSet`, `GetResultMetas`,
  `ActivateResult`, `LaunchSearch`), all five now functionally correct
  (icon field present, loading wait present) — see `component-parity.md`
  for which of the five are actually exercised over a real D-Bus connection
  versus only called directly in-process.
- `lib/background_service.rb` — a second `Gio::Application` process
  (`org.gnome.WeatherRb.SearchProvider`, `IS_SERVICE`), its own `WorldModel`,
  one `quit` action, and two outbound `ActivateAction` calls back into the
  windowed app, both now confirmed reaching it (`show-location` already did;
  `show-search`/`LaunchSearch` is this round's fix).
- `exe/gnome-weather-search-provider` — the second process's entry point,
  now actually D-Bus-activatable by GNOME Shell via the new `.service`/`.ini`
  files, closing last round's "nothing can start this" finding.

Axis-by-axis comparison, including the one narrow-drive-run gap that remains
(`GetResultMetas` never driven over a real bus), is in `component-parity.md`.
