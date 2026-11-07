# gnome-weather-rb — component inventory

Upstream is `org.gnome.Weather`, now written in TypeScript/GJS (not Vala) —
see `src/app/*.ts`, `src/service/*.ts`, `src/shared/world.ts`, `src/misc/util.ts`,
plus the `.ui` templates in `data/` and the one `.ui` beside its source in
`src/app/locationRow.ui`. Read from `origin/main` with `git show origin/main:<path>`
and `git ls-tree -r --name-only origin/main`; never checked out.

Scope: the whole app (opening survey of a fresh fork — totals are the point,
not an action list). One unit at a time follows for actual port work.

## Components, upstream file → port file

| Upstream file(s) | Kind | → `lib/*.rb` | Exists? | Notes |
|---|---|---|---|---|
| `src/app/main.ts` | entry point | `lib/main.rb` + `exe/gnome-weather-rb` (bin) | yes (`lib/main.rb`) | app bootstrap, gettext init |
| `src/app/application.ts` | `Adw.Application` subclass | `lib/main.rb` (app class) / `lib/gnome_weather.rb` | yes | holds `app.temperature-unit` action, About action wiring; verify win vs app action split against `window.ui`'s `app.temperature-unit` + `win.about` |
| `data/window.ui` + `src/app/window.ts` | main window (`Gjs_MainWindow` / `Adw.ApplicationWindow`) | `lib/window.rb` | yes | two-page `GtkStack`: welcome `AdwStatusPage` + city `AdwToolbarView`; `win.about`, `win.refresh` actions; `AdwViewSwitcherTitle`/`Bar` |
| `data/weather-widget.ui` + `src/app/city.ts` (the `WeatherWidget` half lives in `city.ts`? — confirm: upstream class is `WeatherWidget`, file `city.ts` holds `WeatherView`; `weather-widget.ui`'s `Gjs_WeatherWidget` template backs a class not yet located in a separate `.ts` — **re-check**: likely folded into `city.ts`; needs a read pass before porting) | main weather display | `lib/weather_widget.rb` | yes | conditions image, places button, temperature/apparent labels, forecast `AdwViewStack` (hourly/daily), prev/next scroll buttons |
| `data/city.ui` + `src/app/city.ts` | per-city view (`Gjs_WeatherView` / `WeatherView`), loading spinner → weather widget | `lib/weather_view.rb` | yes | `GtkStack` with `loading` page (`AdwSpinner`) and a weather page |
| `src/app/currentLocationController.ts` | geolocation portal controller | `lib/location.rb`? no dedicated file | **missing** — no `lib/current_location_controller.rb` | Should use `ashpd`'s `Ashpd::Location` portal (now wired as a gem dependency); confirm nothing hand-rolls geoclue/portal access elsewhere before porting this |
| `src/app/dailyForecast.ts` + thermometer render | daily forecast box (`DailyForecastBox`) | `lib/daily_forecast_box.rb` | yes | per-day entries, thermometer range bars |
| `src/app/hourlyForecast.ts` | hourly forecast box (`HourlyForecastBox`), horizontal scroller | `lib/hourly_forecast_box.rb` | yes | `GtkScrolledWindow`-driven entries, custom draw/animation (Graphene) |
| `data/day-entry.ui` | day entry popover (more-info `GtkPopover`, night/morning/afternoon/evening grid) | `lib/day_entry.rb` | yes | — |
| `data/hour-entry.ui` (`Gjs_HourEntry`) | hour entry (`AdwBin` template: time label, icon, temp label) | `lib/hour_entry.rb` | yes | — |
| `src/app/thermometer.ts` | custom-drawn temperature range widget (`TemperatureRange`, uses Gsk/Graphene for painting) | `lib/thermometer.rb` | yes | verify Gsk/Graphene-based custom drawing is reproduced, not approximated |
| `data/places-popover.ui` + `src/app/world.ts` | places popover (`Gtk.Popover` subclass `WorldContentView`): search entry, search `GtkListView`, saved-locations `GtkListBox` with empty-state grid | `lib/world_content_view.rb` | yes | empty state: `edit-find-symbolic` icon + "Search for a city" label — confirm present |
| `src/app/locationRow.ui` + `src/app/locationRow.ts` | one row in the places popover's location list (`LocationRow` extends `Gtk.Box`): name/country labels, current-location icon, selected icon, remove button, `remove` signal | `lib/location_row.rb` | yes | `isRemovable`/`isCurrentLocation`/`isSelected` visibility toggles — confirm all three states ported, not just the widgets |
| `src/app/entry.ts` | location search entry (`LocationSearchEntry`), walks the GWeather location tree (`getAllCitiesAndWeatherStations`) for the search model | `lib/location_search_entry.rb` | yes | now backed by the real `libgweather` gem per `lib/location.rb`'s header comment — confirm `entry.ts`'s own search-matching logic (not just the tree walk) is reproduced |
| `src/shared/world.ts` (`WorldModel`) | saved-locations model backing both window and popover | `lib/world_model.rb` | yes | — |
| `src/misc/util.ts` | shared formatting helpers (temperature/wind/etc. string formatting) | `lib/util.rb` | yes | — |
| `src/app/shell.ts` | GNOME Shell D-Bus weather integration (`ShellWeatherIntegration` interface, exported object) | — | **missing** | no `lib/shell_integration.rb`; this exports current weather to gnome-shell's weather applet over D-Bus (`data/ShellWeatherIntegration.xml`) |
| `src/service/main.ts` + `src/service/searchProvider.ts` | background service: `org.gnome.Weather.BackgroundService`, implements `ShellSearchProvider2` (search-provider D-Bus interface, `data/ShellSearchProvider2.xml`) so GNOME Shell's overview can search cities | — | **missing** | no `lib/` file, no `exe/` background-service binary; `data/org.gnome.Weather.BackgroundService.service.in` / `.search-provider.ini.in` have no port-side counterpart at all |
| `data/org.gnome.Weather.gschema.xml` | GSettings schema (`locations`, `window-width/height/maximized`) | `lib/settings.rb` | yes, but **hand-rolled** | `lib/settings.rb`'s own header admits: "This port has no GWeather, so the [temperature-unit] preference lives here" and persists via hand-written JSON/file, not `Gio::Settings` — worth a second look once GWeather's own settings integration is confirmed working, since `libgweather` is now a wired dependency |
| `data/org.gnome.Weather.metainfo.xml.in.in` / `.desktop.in.in` | app metadata, launcher, search keywords, `X-Geoclue-Reason` | not yet surveyed against gem packaging | not applicable to `lib/` | gemspec/flake-level, not a widget — check during packaging, not here |
| primary menu (`primary-menu` in `window.ui`): temperature-unit radio section (`app.temperature-unit` = centigrade/fahrenheit), About item (`win.about`) | menu | `lib/primary_menu.rb` | yes | — |
| About dialog (triggered by `win.about`) | dialog | `lib/about_dialog.rb` | yes | — |
| app-wide styling: `data/style.css`, `data/style-dark.css`, `data/style-hc.css` | stylesheet | `lib/styles.rb` | yes | confirm dark/high-contrast variants both carried over, not just the base sheet |
| `WeatherInfo`/reading model backing every widget (stands in for `GWeather.Info`) | data model, not a widget | `lib/weather_info.rb` + `lib/weather_provider.rb` | yes, but **hand-rolled against the network directly** | `lib/weather_provider.rb`'s header: "stands in for the values GWeather.Info exposes"; fetches via `net/http`/`json` instead of `GWeather::Info#update`, even though `libgweather` is now a wired runtime dependency (confirmed in gemspec, `nix/Gemfile`, `flake.nix`'s `gtkStack`/typelib wiring). This is exactly the "hand-rolled in place of a gem" pattern the fleet audit is looking for — `GWeather::Info` should be driving these widgets, not a bespoke HTTP client. Flagged for a follow-up port pass, not fixed in this survey step. |
| `Location` wrapper (stands in for `GWeather.Location`) | data model | `lib/location.rb` | yes, already uses `GWeather::Location` | correctly wraps the real gem; the comment explains the `GLib::Object` subclass is only for `Gio::ListStore` storage, not a reimplementation |
| po catalogue (`po/*.po`, 90 languages, `po/POTFILES.in`) | translations | not surveyed string-by-string here | — | belongs to `translation-parity`, not this component pass |
| version module | packaging | `lib/gnome/weather/rb/version.rb` | yes | gem scaffolding, not a component |

## Totals

- Upstream user-facing TS files scanned: `application.ts`, `main.ts`, `window.ts`,
  `city.ts`, `currentLocationController.ts`, `dailyForecast.ts`, `entry.ts`,
  `hourlyForecast.ts`, `locationRow.ts`, `thermometer.ts`, `world.ts`, `shell.ts`,
  plus service-side `main.ts`/`searchProvider.ts` — 14 files.
- `.ui`/template files: `window.ui`, `weather-widget.ui`, `city.ui`, `day-entry.ui`,
  `hour-entry.ui`, `places-popover.ui`, `locationRow.ui` — 7 files.
- `lib/*.rb` on `ruby`: 21 files, 4079 lines.
- Components with a `lib/*.rb` counterpart: 16 of 18 upstream units identified.
- **Missing entirely**: the GNOME Shell weather-applet D-Bus integration
  (`src/app/shell.ts`) and the whole background service / search provider
  (`src/service/main.ts`, `src/service/searchProvider.ts`,
  `data/org.gnome.Weather.BackgroundService.*`, `data/ShellSearchProvider2.xml`,
  `data/org.gnome.Weather.search-provider.ini.in`). Nobody has started either.
- **Present but hand-rolled in place of the now-wired `libgweather` gem**:
  `lib/weather_provider.rb` / `lib/weather_info.rb` fetch and model weather
  data themselves (`net/http`, `json`, a custom `Reading` struct) instead of
  calling `GWeather::Info#update` and reading its accessors, and
  `lib/settings.rb` hand-rolls the temperature-unit preference instead of
  going through GSettings/GWeather's own settings key, by its own admission
  in both files' header comments. `lib/location.rb` is the one model file that
  already uses the real `GWeather::Location`.
- Not yet checked against upstream in this pass: exact widget/CSS/signal counts
  inside each existing `lib/*.rb` (that is `component-parity`'s job, to run
  once each unit above is picked for porting) and the `po/` string census
  (`translation-parity`'s job).

## Next unit to pick

Given the gaps above, the highest-value next units are:
1. `lib/weather_info.rb` / `lib/weather_provider.rb` — replace the hand-rolled
   HTTP fetch with `GWeather::Info`, now that the gem is wired and proven to
   load (`ruby -e 'require "libgweather"; puts GWeather.constants.size'`).
2. `lib/shell_integration.rb` — port `src/app/shell.ts`'s D-Bus weather
   integration.
3. A background-service unit — port `src/service/main.ts` +
   `src/service/searchProvider.ts` as a second executable
   (`org.gnome.Weather.BackgroundService` / `ShellSearchProvider2`).

No app code was written in this step.
