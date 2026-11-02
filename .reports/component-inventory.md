# gnome-weather-rb — upstream component inventory

Survey of `origin/main` (GNOME Weather, GJS/TypeScript + GtkBuilder `.ui`)
against `lib/` on the `ruby` branch. Nothing but the application scaffold
exists on the port side yet, so every row below is a gap except where noted.

Upstream is a GJS app: each component is a `.ts` class **plus** the `.ui` file
its `Template:` points at. The two halves union into one `lib/*.rb` file.

Totals: **21 component units** (14 of them widgets), 1 menu model, 3
stylesheets, 1 GSettings schema, 1 `po/` catalogue of 100 languages.
Port side: 1 file, a placeholder.

---

## Port-side state (`ruby` branch)

| File | What it is |
|---|---|
| `lib/gnome_weather.rb` | requires `gnome_weather/application` |
| `lib/gnome_weather/application.rb` | scaffold `Application` — window + `Adwaita::StatusPage` saying the port is unwritten. No actions, no menu, no model |
| `lib/gnome/weather/rb/version.rb` | gem version |

No window, no views, no model, no forecast widgets, no D-Bus services.

---

## src/app/main.ts — process entry point

Not a widget. Sets up gettext/format, defines the `getApp()` global, builds
`WeatherApplication` and runs it through the GJS mainloop shim.

→ `lib/main.rb` (launcher as one expression, per house style). **Absent.**

## src/app/application.ts — the application object

| Thing | × | Detail |
|---|---:|---|
| `Gio.SimpleAction app.quit` | 1 | `Ctrl+Q` |
| `Gio.SimpleAction app.show-location` | 1 | param `v`, deserialises a `GWeather.Location`, opens a window on it |
| `Gio.SimpleAction app.show-search` | 1 | param `v`, opens a window in search mode |
| `Gio.SimpleAction app.temperature-unit` | 1 | **stateful**, param `s`, states `centigrade` / `fahrenheit` / `default`; mirrors `org.gnome.GWeather4` and legacy `org.gnome.GWeather` settings, and tracks `changed::temperature-unit` |
| Accelerators | 5 | `win.selection-mode`→`Escape`, `win.select-all`→`<Control>a`, `window.close`→`<Control>w`, `app.quit`→`<Control>q`, `win.refresh`→`F5`/`<Control>r` |
| Busy cursor | — | `mark_busy`/`unmark_busy` driven by `WorldModel#loading` |
| D-Bus | — | `vfunc_dbus_register` exports `ShellIntegration` |
| Shutdown | — | `GWeather.Info.store_cache()`, `model.saveSettingsNow()` |

Note: `win.selection-mode` and `win.select-all` have accels but **no action is
installed anywhere upstream** — dead accelerators. Reproduce the accels for
parity, but do not invent the actions.

→ `lib/gnome_weather/application.rb`. **Present but placeholder only** — none
of the above exists.

## src/app/window.ts + data/window.ui — main window

`Adw.ApplicationWindow`, 1050×650, two-page crossfade stack.

| Widget | × | CSS | Signals / actions | Notes |
|---|---:|---|---|---|
| `Adw.ApplicationWindow` (template root) | 1 | `devel` (dynamic, only when `pkg.name` ends in `Devel`) | `close-request` → saves geometry | geometry restored from `org.gnome.Weather` settings |
| `Gtk.Stack` `stack` | 1 | — | — | `crossfade`; children `searchView`, `cityBox` |
| `Adw.ToolbarView` `searchView` | 1 | — | — | welcome / empty state page |
| `Adw.HeaderBar` (in searchView) | 1 | — | — | `show-title=False` |
| `Gtk.MenuButton` (searchView end) | 1 | — | menu `primary-menu` | `open-menu-symbolic` |
| `Adw.StatusPage` `searchViewStatus` | 1 | — | — | “Welcome to Weather!” / “To get started, select a location.”; `icon_name` set to app id at runtime |
| `Gtk.MenuButton` `searchButton` | 1 | — | popover set in code to `WorldContentView` | label “Search for a city or country”, width-request 146 |
| `Adw.ToolbarView` `cityBox` | 1 | — | — | the city page |
| `Adw.HeaderBar` `header` | 1 | — | — | `centering_policy=strict` |
| `Gtk.Revealer` `refreshRevealer` | 1 | — | — | crossfade; hidden on the welcome page |
| `Gtk.Button` `refresh` | 1 | — | action `win.refresh` | `view-refresh-symbolic`, tooltip “Refresh” |
| `Adw.ViewSwitcherTitle` `forecastStackSwitcher` | 1 | — | — | title “Weather”; stack bound to the city view’s `forecastStack` |
| `Gtk.MenuButton` (header end) | 1 | — | menu `primary-menu`, `primary=true` | tooltip “Main Menu” |
| `Adw.Bin` `cityBin` | 1 | — | — | hosts `City.WeatherView` |
| `Adw.ViewSwitcherBar` `forecastStackSwitcherBar` | 1 | — | — | `reveal` bound to `forecastStackSwitcher.title-visible` |
| `Gio.SimpleAction win.about` | 1 | — | → `showAbout()` | |
| `Gio.SimpleAction win.refresh` | 1 | — | → `cityView.update()` | |

States: `showDefault` (most recent location, else search), `showSearch`,
`showInfo`. Settings written: `window-width`, `window-height`,
`window-maximized`.

→ `lib/window.rb`. **Absent.**

## data/window.ui `primary-menu` — menu model

Section “Temperature Unit” → items `_Celsius` (`app.temperature-unit`, target
`centigrade`) and `_Fahrenheit` (target `fahrenheit`); section → `_About
Weather` (`win.about`). 3 items, 2 sections. Used by two `Gtk.MenuButton`s.

→ `lib/primary_menu.rb` (or a memoized `Gio::Menu` on the window). **Absent.**

## src/app/window.ts#showAbout — about dialog

`Adw.AboutDialog`: developers, 8 designers, translator-credits, app name
“Weather”, app icon, developer name “The GNOME Project”, copyright
“Copyright 2013-2015 The Weather Developers”, GPL-2.0, version, website
`apps.gnome.org/Weather/`, issue URL. Plus a **conditional legal section**
carrying `info.get_attribution()` under `Gtk.License.CUSTOM`.

→ `lib/about_dialog.rb`. **Absent.**

## src/app/city.ts (WeatherView) + data/city.ui — city page shell

| Widget | × | CSS | Signals | Notes |
|---|---:|---|---|---|
| `Adw.Bin` (template root) | 1 | — | `vfunc_map`/`vfunc_unmap` | |
| `Gtk.Stack` `stack` | 1 | — | — | crossfade; pages `loading`, `info` |
| `Adw.Spinner` | 1 | — | — | the `loading` page |
| `WeatherWidget` | 1 | — | — | added as page `info` at runtime |

Behaviour: setting `info` disconnects the old `updated` handler, shows
`loading`, calls `info.update()` when invalid, swaps to `info` on update.

→ `lib/weather_view.rb`. **Absent.**

## src/app/city.ts (WeatherWidget) + data/weather-widget.ui — the weather page

Root is an `Adw.Bin` named `weather-page` with an `Adw.ClampLayout`
(`maximumSize: 1010`, `tighteningThreshold: 992`).

| Widget | × | CSS | Signals | Notes |
|---|---:|---|---|---|
| `Gtk.Box` `outerBox` | 1 | — | — | vertical, spacing 20 |
| `Gtk.Grid` (`#conditions-grid`) | 1 | — | — | |
| `Gtk.Image` `conditionsImage` | 1 | `icon-dropshadow` | — | `<icon>-large`, pixel size 84 |
| `Gtk.MenuButton` `placesButton` | 1 | `text-button`, `flat` | popover set to `WorldContentView` | `always-show-arrow` |
| `Gtk.Label` `placesLabel` (`#places-label`) | 1 | — | — | “Places”, wrap word-char |
| `Gtk.Box` `temperatureBox` | 1 | — | — | baseline bottom |
| `Gtk.Label` `temperatureLabel` (`#temperature-label`) | 1 | — | — | `%d°` |
| `Gtk.Label` `apparentLabel` | 1 | `caption` | — | “Feels like %.0f°”, hidden when equal to temp |
| `Gtk.Overlay` | 1 | — | — | |
| `Adw.ViewStack` `forecastStack` | 1 | — | `notify::visible-child` → reset scroll, sync arrows | |
| `Adw.ViewStackPage` hourly | 1 | — | — | “_Hourly”, `weather-hourly-symbolic` |
| `Adw.ViewStackPage` daily | 1 | — | — | “_Daily”, `x-office-calendar-symbolic` |
| `Gtk.ScrolledWindow` ×2 (`forecastHourlyScrollWindow`, `forecastDailyScrollWindow`) | 2 | `forecast-card`, `card` | — | min width 308, external hscrollbar |
| `Gtk.Adjustment` ×2 | 2 (type, not widget) | — | `changed`, `value-changed` → `syncLeftRightButtons` | |
| `Gtk.Viewport` ×2 | 2 | — | — | natural scroll policy |
| `HourlyForecastBox` `forecastHourly` | 1 | — | — | composite, own file |
| `DailyForecastBox` `forecastDaily` | 1 | — | — | composite, own file |
| `Gtk.Button` `startButton` | 1 | `osd`, `circular` | `clicked` → page-back scroll animation | `go-previous-symbolic`; visibility is direction-aware |
| `Gtk.Button` `endButton` | 1 | `osd`, `circular` | `clicked` → page-forward scroll animation | `go-next-symbolic` |
| `Gtk.Box` (`#attributionGrid`) | 1 | — | — | |
| `Gtk.Label` `updatedTimeLabel` | 1 | `caption` | — | “Updated just now.” / ngettext minutes·hours·days·weeks·months, refreshed on a 60 s timeout |
| `Gtk.Label` `attributionLabel` | 1 | `dim-label`, `caption` | — | markup, ellipsised |

Also: a `Gtk.Widget` tick-callback scroll animation using `easeOutCubic`, and
RTL-aware arrow logic.

→ `lib/weather_widget.rb`. **Absent.**

## src/app/world.ts + data/places-popover.ui — places popover / world view

`Gtk.Popover` subclass, built from the `.ui` by a `Gtk.Builder` (top-level
object, not a template). Accessible label “World view”.

| Widget | × | CSS | Signals | Notes |
|---|---:|---|---|---|
| `Gtk.Popover` (root) | 1 | `weather-popover`, `menu` | `show` → focus the entry | `has-arrow=false`, halign from caller |
| `Gtk.Box` `popoverBox` | 1 | — | — | 320×300 |
| `LocationSearchEntry` `location-entry` (`#locationEntry`) | 1 | — | `search-updated`, `notify::location` | placeholder “Search for a city” |
| `Gtk.Stack` `popover-stack` | 1 | — | — | swaps search results ↔ saved locations |
| `Gtk.ScrolledWindow` `search-list-scroll-window` | 1 | `undershoot-top` | — | |
| `Gtk.ListView` `search-list-view` | 1 | — | — | model/factory supplied by the entry |
| `Gtk.ScrolledWindow` `locations-list-scroll-window` | 1 | `undershoot-top` | — | |
| `Gtk.Viewport` | 1 | — | — | |
| `Gtk.ListBox` `locations-list-box` | 1 | — | `row-activated` → `setSelectedLocation` + deferred popdown | `bind_model` over `WorldModel`, selection none |
| `Gtk.ListBoxRow` | repeater | — | carries `_info` | one per saved location |
| `LocationRow` | repeater | — | `remove` → `model.removeLocation` | child of each row |
| **Empty state**: `Gtk.Grid` `empty-search-grid` (`#search-city-grid`) | 1 | — | — | ListBox `placeholder` |
| `Gtk.Image` `search-image` | 1 | — | — | `edit-find-symbolic`, size 2 |
| `Gtk.Label` `search-label` | 1 | `dim-label` | — | “Search for a city” |

Also listens to `selected-location-changed` on the model → `window.showInfo`.
Two instances exist at runtime (window search button, weather page places
button).

→ `lib/world_content_view.rb`. **Absent.**

## src/app/entry.ts — location search entry (+ its model and filter)

Three classes in one file:

| Class | Kind | Notes |
|---|---|---|
| `LocationListModel` | `Gio.ListModel` impl | walks the whole GWeather tree for every `CITY` and `WEATHER_STATION`, loaded on idle |
| `LocationFilter` | `Gtk.Filter` subclass | lowercase substring match with a `WeakMap` name cache |
| `LocationSearchEntry` | `Adw.Bin` (`Gtk.BinLayout`) | the widget |

| Widget | × | CSS | Signals | Notes |
|---|---:|---|---|---|
| `Adw.Bin` (root) | 1 | — | `vfunc_unroot` clears the list view model | props `text`, `placeholder-text`, `location`; signal `search-updated` |
| `Gtk.SearchEntry` | 1 | — | `search-changed` → refilter + emit `search-updated` | bound bidirectionally to `text` |
| `Gtk.SingleSelection` | 1 (type) | — | `notify::selected` → sets `location` | `autoselect: false`, selected `MAXUINT32` |
| `Gtk.FilterListModel` | 1 (type) | — | — | incremental |
| `Gtk.SignalListItemFactory` | 1 (type) | — | `setup` → new `LocationRow`; `bind` → name + country | drives `search-list-view` |

→ `lib/location_search_entry.rb`. **Absent.**

## src/app/locationRow.ts + src/app/locationRow.ui — one location row

| Widget | × | CSS | Signals | Notes |
|---|---:|---|---|---|
| `Gtk.Box` (template root) | 1 | — | custom signal `remove` | width-request 320, spacing 12 |
| `Gtk.Box` | 2 | — | — | inner layout |
| `Gtk.Label` `label` | 1 | `body` | — | location name, ellipsised |
| `Gtk.Label` `countryLabel` (`#countryLabel`) | 1 | `caption` | — | country name |
| `Gtk.Image` `currentIcon` | 1 | — | — | `checkmark-symbolic`, visible when selected |
| `Gtk.Image` `locationIcon` | 1 | `circular` | — | `find-location-symbolic`, visible for the geolocated city |
| `Gtk.Button` `removeButton` | 1 | `circular`, `flat` | `clicked` → `_onRemoveClicked` → emits `remove` | `window-close-symbolic`, visible only when removable |

Used from two places (popover list rows and the search `ListView` factory).

→ `lib/location_row.rb`. **Absent.**

## src/app/hourlyForecast.ts (HourlyForecastBox) — hourly strip

`Gtk.Box` named `hourly-forecast-box`, accessible label “Hourly Forecast”.

| Widget | × | CSS | Signals | Notes |
|---|---:|---|---|---|
| `Gtk.Box` (root) | 1 | — | — | horizontal, spacing 0 |
| `HourEntry` | repeater | — | — | one per forecast hour within 24 h |
| `Gtk.Separator` | repeater | — | — | vertical, between entries |
| **Empty state**: `Gtk.Label` | 1 | — | — | “Forecast not Available” |

Also a **custom `vfunc_snapshot`**: a cairo temperature spline filled with
`weather_temp_chart_fill_color` and stroked with
`weather_temp_chart_stroke_color`. Reads `clock-format` from
`org.gnome.desktop.interface` for the “Now” / `%l∶%M %p` / `%R` labels.

→ `lib/hourly_forecast_box.rb`. **Absent.**

## src/app/hourlyForecast.ts (HourEntry) + data/hour-entry.ui — one hour cell

| Widget | × | CSS | Signals | Notes |
|---|---:|---|---|---|
| `Adw.Bin` (template root) | 1 | — | — | 75×200, margins 18 |
| `Gtk.Box` | 1 | — | — | vertical, spacing 18 |
| `Gtk.Label` `timeLabel` | 1 | — | — | “Now” or a formatted hour |
| `Gtk.Image` `image` | 1 | `forecast-graphic` | — | `<icon>-small`, pixel size 32 |
| `Gtk.Label` `forecastTemperatureLabel` | 1 | `forecast-temperature-label` | — | `13°` |

→ `lib/hour_entry.rb`. **Absent.**

## src/app/dailyForecast.ts (DailyForecastBox) — daily strip

`Gtk.Box` named `daily-forecast-box`, accessible label “Daily Forecast”.

| Widget | × | CSS | Signals | Notes |
|---|---:|---|---|---|
| `Gtk.Box` (root) | 1 | — | — | horizontal |
| `DayEntry` | repeater | — | — | one per forecast day |
| `Gtk.Separator` | repeater | — | — | vertical, after each entry |
| **Empty state**: `Gtk.Label` | 1 | — | — | “Forecast not Available” when fewer than 2 days |

Logic: buckets forecasts by local day, picks the nearest info to each of five
period times (night 02:00, morning 07:00, day 12:00, afternoon 17:00, evening
22:00), computes weekly high/low.

→ `lib/daily_forecast_box.rb`. **Absent.**

## src/app/dailyForecast.ts (DayEntry) + data/day-entry.ui — one day cell + its popover

| Widget | × | CSS | Signals | Notes |
|---|---:|---|---|---|
| `Adw.Bin` (template root) | 1 | — | `vfunc_root` fills every label | 100×200, margins 18 |
| `Gtk.Box` | 1 | — | — | vertical |
| `Gtk.Label` `nameLabel` | 1 | `caption-heading` | — | `%a` |
| `Gtk.Label` `dateLabel` | 1 | `caption` | — | “%b %e” (translated format) |
| `Gtk.Image` `image` | 1 | `forecast-graphic` | — | `<icon>-small`, pixel size 32 |
| `Thermometer` `thermometer` | 1 | — | — | composite, own file |
| `Gtk.MenuButton` | 1 | `forecast-button`, `image-button`, `circular`, `flat` | popover `more_menu` | `view-more-symbolic` |
| **Popover** `more_menu` | 1 | `day-popover` | — | 5×5 grid, see below |
| `Gtk.Grid` (in popover) | 1 | — | — | margins 16, spacings 8/16 |
| `Gtk.Label` (period names) | 4 | `caption` | — | Night, Morning, Afternoon, Evening |
| `Gtk.Image` (column heads) | 3 | — | — | `temperature-symbolic`, `weather-showers-scattered-symbolic`, `weather-windy` |
| `Gtk.Image` (per-period icons) | 4 | — | — | `nightImage`…`eveningImage` |
| `Gtk.Label` (temperatures) | 4 | — | — | `nightTemperatureLabel`… |
| `Gtk.Label` (humidity) | 4 | — | — | `nightHumidity`… |
| `Gtk.Label` (wind) | 4 | — | — | `nightWind`…; falls back from `get_value_wind` to `get_wind()` |

→ `lib/day_entry.rb`. **Absent.**

## src/app/thermometer.ts — thermometer widget

Three classes: `TemperatureRange` (plain value object), `ThermometerScale`
(`Gtk.Widget`, CSS name `WeatherThermometerScale`, custom `vfunc_snapshot`
drawing a rounded gradient bar between `weather_thermometer_warm_color` and
`weather_thermometer_cold_color`, `queue_draw` on `notify::range`), and
`Thermometer` (`Gtk.Widget`, CSS name `WeatherThermometer`, custom
`vfunc_measure`/`vfunc_size_allocate`/`vfunc_root`).

| Widget | × | CSS | Notes |
|---|---:|---|---|
| `Thermometer` | 1 | `WeatherThermometer` (CSS name) | hand-laid-out |
| `Gtk.Label` high | 1 | `high`, `body` | coloured `weather_thermometer_high_color` |
| `Gtk.Label` low | 1 | `low`, `body` | coloured `weather_thermometer_low_color` |
| `ThermometerScale` | 1 | `WeatherThermometerScale` (CSS name) | the drawn bar |

→ `lib/thermometer.rb`. **Absent.**

## src/shared/world.ts — the world model

`GObject.Object` implementing `Gio.ListModel` of `GWeather.Info`. Property
`loading`; signal `selected-location-changed`. Loads and saves the
`locations` `av` GSettings key, adds/removes locations, tracks the geolocated
“current location”, exposes `getRecent`, `getAll`, `getAtIndex`,
`addNewLocation`, `updateInfo`, `saveSettingsNow`.

→ `lib/world_model.rb`. **Absent.** (Not a widget, but every view binds to it.)

## src/app/currentLocationController.ts — geolocation

Geoclue `Simple` client at `CITY` accuracy, 100 m threshold; maps the position
to the nearest GWeather city and pushes it into the model; logs and clears on
failure. Non-widget.

→ `lib/current_location_controller.rb`. **Absent.**

## src/misc/util.ts — helpers

`loadUI`, `arrayEqual`, `getSettings`, `getWeatherConditions`,
`normalizeCasefoldAndUnaccent`, `getTemperature` (“%s / %s”),
`getEnabledProviders`, `easeOutCubic`, the five period-time helpers,
`getDateTime`, `getTemp`, `formatTemperature`, `getTempString`,
`getNameAndCountry`. Carries two translatable strings.

→ `lib/util.rb`. **Absent.**

## src/app/shell.ts + data/ShellWeatherIntegration.xml — shell integration

`org.gnome.Shell.WeatherIntegration` D-Bus object: read-only
`AutomaticLocation` (always true) and `Locations`, re-emitting
`PropertiesChanged` on `changed::locations`. Non-widget.

→ `lib/shell_integration.rb`. **Absent.**

## src/service/main.ts — background search-provider service

`Gio.Application` with `IS_SERVICE`, 60 s inactivity timeout, own `quit`
action, loads the model, exports the search provider on `dbus_register`.

→ `lib/background_service.rb`. **Absent.**

## src/service/searchProvider.ts + data/ShellSearchProvider2.xml — shell search provider

`org.gnome.Shell.SearchProvider2`: `GetInitialResultSetAsync` (waits out model
loading), `GetSubsearchResultSet`, `GetResultMetas` (“%s, %s” conditions +
temperature, themed icon), `ActivateResult` → `app.show-location`,
`LaunchSearch` → `app.show-search`. Matching is name → city → country, each
normalised casefolded and unaccented.

→ `lib/search_provider.rb`. **Absent.**

---

## Non-code assets

| Upstream | Target | Kind | Present |
|---|---|---|---|
| `data/style.css` | `lib/styles.rb` (inline `Gtk::CssProvider`) | stylesheet — 9 `@define-color`s, `#places-label`, `#temperature-label`, `.content-view.cell`, `#locationEntry`, `.weather-popover`, `.forecast-card`, `.forecast-card separator`, `#conditions-grid`, `#attributionGrid`, `#weather-page .small .forecast-card`, `.forecast-temperature-label`, `WeatherThermometer`, `WeatherThermometer > label.high/.low`, `.forecast-button`, `.forecast-graphic`, `button.osd.circular`, `image.circular` | no |
| `data/style-dark.css` | same | dark-variant colour overrides (libadwaita auto-loads it from the resource base path) | no |
| `data/style-hc.css` | same | high-contrast override of `.forecast-card separator` | no |
| `data/org.gnome.Weather.gschema.xml` | `lib/settings.rb` | GSettings: `locations` (`av`), `window-width`, `window-height`, `window-maximized` | no |
| `data/org.gnome.Weather.data.gresource.xml` | n/a — the port builds widgets in Ruby, no GResource | manifest | n/a |
| `src/org.gnome.Weather.src.gresource.xml.in` | n/a | manifest | n/a |
| `data/org.gnome.Weather.desktop.in.in`, `.metainfo.xml.in.in`, `.search-provider.ini.in`, `.service.in`, `BackgroundService.service.in` | packaging | desktop/appstream/D-Bus activation | no |
| `po/` (100 languages, `LINGUAS`) | translation parity step | catalogue; `POTFILES.in` lists 7 `.ui`/data files and 9 sources | no |
| `data/icons/…` (35 status icons + app icons) | shipped icons — `-large`/`-small` weather variants, `checkmark-symbolic`, `temperature-symbolic`, `weather-hourly-symbolic` | assets | no |
| `tests/world_view.py`, `tests/testutil.py` | test parity step | upstream’s only tests | no |

## Things that will bite the port

- **Two custom-drawn widgets.** `HourlyForecastBox#vfunc_snapshot` (cairo
  temperature spline) and `ThermometerScale#vfunc_snapshot` (gradient bar),
  plus `Thermometer`’s hand-written `measure`/`size_allocate`. These are the
  only places the app leaves ordinary widget composition.
- **`GWeather` and `Geoclue` bindings** must both be reachable from the dev
  shell; without GWeather there is no app at all.
- **Two `WorldContentView` instances** share one `WorldModel` and one global
  `LocationListModel`; the popover clears its list-view model on unroot to
  avoid both sharing a selection.
- **A stateful radio action** (`app.temperature-unit`) with a third
  `default` state, mirrored into two external GSettings schemas.
- **Dead accelerators** `win.selection-mode` and `win.select-all` — kept for
  parity, no actions behind them.
- **`.ui` → memoized Ruby**: nine declarative files collapse into the port’s
  widget methods; the `window.ui` property binding
  (`forecastStackSwitcherBar.reveal` ← `forecastStackSwitcher.title-visible`)
  has to be reproduced as an explicit `bind_property`.
