# Component identification — gnome-weather-rb

| | |
|---|---|
| Upstream | `origin/main` @ `6930d4a` |
| Port | `ruby` @ `a52fce1` |

This report records the raw inventory step. The judged, axis-by-axis
comparison (and the unported units) is in `component-parity.md`; this file
exists so the counts behind that comparison are reproducible.

## Scan totals (`component-scan.sh`)

| | Upstream | Port |
|---|---:|---:|
| Rows | 184 | 141 |
| Distinct widget types | 29 | 31 |
| Distinct signals | 19 | 18 |
| Distinct CSS classes | 20 | 22 |

Widget-type counts alone look close, which is exactly the trap the
`component-identification` skill warns about: it is a whole-app total, not a
per-unit comparison, and it hides that four whole upstream units (geolocation,
shell integration, the background service, the search provider) have no port
file at all and therefore contribute zero rows to either side.

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
| `src/app/currentLocationController.ts` | — | **absent** |
| `src/app/shell.ts` + `data/ShellWeatherIntegration.xml` | — | **absent** |
| `src/service/main.ts` | — | **absent** |
| `src/service/searchProvider.ts` + `data/ShellSearchProvider2.xml` | — | **absent** |

Non-widget assets with their own port-side status, confirmed directly
(not taken on the existing `.reports/component-inventory.md`'s word):

| Upstream asset | Port | Present |
|---|---|---|
| `data/style.css`, `style-dark.css`, `style-hc.css` | `lib/styles.rb` (Ruby heredoc, `Gtk::CssProvider`) | yes |
| `data/org.gnome.Weather.gschema.xml` | `lib/settings.rb` (JSON file, same keys) | yes (substituted storage, same keys — correspondence) |
| `data/org.gnome.Weather.desktop.in.in` | — | **no** — no desktop file anywhere in the port |
| `data/org.gnome.Weather.metainfo.xml.in.in` | — | **no** |
| `data/org.gnome.Weather.search-provider.ini.in`, `.service.in`, `BackgroundService.service.in` | — | **no** |
| `data/icons/**` (35 status icons + app icons) | — | **no** — confirmed: `find . -ipath '*icons*'` returns nothing in the port tree |
| `po/` (87 `.po` files, `LINGUAS`) | — | **no** — confirmed: no `po/` directory, no gettext dependency, no `_()`/`gettext` call anywhere in `lib/` |
| `tests/world_view.py`, `tests/testutil.py` | — | **no**, see `test-parity.md` |

## Missing signals (upstream has, port's scan does not find)

```
changed::locations
changed::temperature-unit
notify::loading
notify::location
notify::range
remove
```

Read by hand before trusting this list as gaps (per the skill's Step 4):
`notify::location`, `notify::range` and `remove` are connected inside
`lib/location_search_entry.rb` / `lib/location_row.rb` / `lib/thermometer.rb`
using Ruby property-notify idioms the scan's regex does not match (it is a
scanner miss, not a missing connection — verified by reading the files).
`changed::locations` and `changed::temperature-unit` are real: they are
GSettings change signals from the `org.gnome.GWeather4`/`org.gnome.Weather`
schemas that this port does not mirror into (it keeps its own settings
store instead, so there is no equivalent signal to connect — see
`lib/main.rb`'s comment on `temperature-unit`). `notify::loading` is
connected via `WorldModel#on_loading_changed`, a plain Ruby callback list
rather than a GObject `notify` signal — a correspondence, not a gap.

## Extra signals (port has, upstream's scan does not find)

```
notify::dark
notify::high-contrast
shutdown
startup
unmap
```

All five are real and are the port substituting `Gtk::Application`'s
`startup`/`shutdown`/`activate` signals for upstream's `vfunc_startup` /
`vfunc_shutdown` overrides (Ruby bindings connect by signal where upstream
overrides a vfunc — a correspondence), plus `Styles` watching
`Adwaita::StyleManager`'s `notify::dark`/`notify::high-contrast` to swap the
CSS variant, which is the Ruby equivalent of upstream's
`Adw.StyleManager.connect('notify::dark', ...)` done the same way on both
sides.

## CSS classes: upstream has, port's scan does not find

```
devel
```

Read by hand: upstream's `data/window.ui` adds the `devel` class to the
window root only when the running profile's app id ends in `Devel`. The
port's `lib/window.rb` has no development-profile distinction at all (no
`org.gnome.WeatherDevel` application id, no devel icon) — this is a real,
if minor, gap, not a scanner miss.
