# Component parity — gnome-weather-rb

| | |
|---|---|
| Upstream | `main` @ `6930d4a` |
| Port | `ruby` @ `3edcfea` |
| Units with full (4-axis) parity | 20 / 21 |
| Units entirely absent | 1 / 21 |
| Units present with confirmed gaps | 0 / 21 full units — 1 narrow-drive-run gap inside an otherwise-correct unit (see below) |

Since `c064bf4`'s report, `3edcfea` ("Close search-provider gaps, add D-Bus
activation files and Devel profile") fixed every confirmed behavioural gap
that round found: the search provider's dropped `icon` field, its missing
`loading` wait, `background_service.rb`'s double-wrap bug that silently
dropped `LaunchSearch`, the missing D-Bus activation files, and the missing
`devel` CSS class / Devel app-id profile. All five are re-verified live
below, not taken on the commit message's word.

Live runs this round (`nix develop --command xvfb-run -a ruby ...`), each run
to completion with no other `xvfb-run` process concurrent on the machine:

```
test/check_model.rb              42 of 42 checks passed
test/check_search_provider.rb    14 of 14 checks passed
test/drive_window.rb             49 of 49 checks passed, DRIVE OK
test/drive_dbus_integration.rb   12 of 12 checks passed, DRIVE OK
test/drive_background_service.rb  4 of  4 checks passed, DRIVE OK
```

Total: **121 of 121**, matching this round's runtime-gate headline exactly
(121 checks, 0 failed, 21 components) — the ambiguity the previous two
rounds flagged (108 vs. 110, 41 vs. 42) is resolved: this round's counts tie
out cleanly to the gate, confirmed by an independent re-run rather than taken
on the gate's own say.

## Units with parity

| Unit | Upstream → Port | Verdict |
|---|---|---|
| Main window | `src/app/window.ts`+`.ui` → `lib/window.rb` | parity, including the `devel` CSS class, closed this round |
| Primary menu | `data/window.ui` menu → `lib/primary_menu.rb` | parity |
| About dialog | `window.ts#showAbout` → `lib/about_dialog.rb` | parity |
| City page shell | `city.ts` (`WeatherView`) → `lib/weather_view.rb` | parity |
| Weather page | `city.ts` (`WeatherWidget`) → `lib/weather_widget.rb` | parity, 2 documented asset substitutions (icon-less degree sign, no shipped icon set) |
| Places popover | `world.ts`+`.ui` → `lib/world_content_view.rb` | parity |
| Search entry (in-window) | `entry.ts` → `lib/location_search_entry.rb` | parity |
| Location row | `locationRow.ts`+`.ui` → `lib/location_row.rb` | parity |
| Hourly strip | `hourlyForecast.ts` → `lib/hourly_forecast_box.rb` | parity |
| Hour cell | `hourlyForecast.ts`+`.ui` → `lib/hour_entry.rb` | parity |
| Daily strip | `dailyForecast.ts` → `lib/daily_forecast_box.rb` | parity |
| Day cell + popover | `dailyForecast.ts`+`.ui` → `lib/day_entry.rb` | parity, 1 documented asset substitution |
| Thermometer | `thermometer.ts` → `lib/thermometer.rb` | parity |
| World model | `shared/world.ts` → `lib/world_model.rb` | parity |
| Util | `misc/util.ts` → `lib/util.rb` | parity, 2 helpers not carried over, correspondence |
| Stylesheet | `style*.css` → `lib/styles.rb` | parity |
| App/actions | `src/app/application.ts` → `lib/main.rb` | parity — see one remaining inert item below |
| Shell integration | `src/app/shell.ts` → `lib/shell_integration.rb` | parity, verified live over the real bus |
| Search provider | `src/service/searchProvider.ts` → `lib/search_provider.rb` | parity on all 5 interface methods' logic — see the one drive-coverage gap below |
| Background service | `src/service/main.ts` → `lib/background_service.rb` | parity, and now actually D-Bus-activatable (the `.service`/`.ini` files landed this round) |

## App/actions — `lib/main.rb` — one inert item, unchanged, not a port gap

| Item | Upstream | Port | Verdict |
|---|---|---|---|
| `app.quit`, `app.temperature-unit`, `app.show-location`, `app.show-search` | yes | yes | parity, all four driven live |
| `win.selection-mode` / `win.select-all` accels | accels set (`set_accels_for_action`) but **no action behind them anywhere in upstream either** — confirmed: `grep -rn "select-all\|selection-mode" src/ data/` finds only the two `set_accels_for_action` calls in `application.ts`, no `SimpleAction` named either | absent | not a gap — these accels are dead code in upstream itself (likely a leftover from a removed selection-mode UI), so a port with no equivalent has full behavioural parity, not a hole |
| `devel` CSS class / Devel app-id profile | yes | yes, via `GNOME_WEATHER_APP_ID` | **parity, closed this round** |

## Search provider — `lib/search_provider.rb` — both confirmed gaps fixed, re-verified

1. **`icon` field** — `meta_for` now includes an `icon_for(info)` result
   built as a `(sv)` variant matching `Gio.ThemedIcon#serialize`'s observed
   shape. Confirmed by direct read of `lib/search_provider.rb:183-209` and by
   the live check `check_search_provider.rb`: "the meta carries a themed icon
   variant, matching the widget's icon name" — passes.
2. **Loading wait** — `initial_result_set`/`subsearch_result_set` now go
   through `wait_for_loading`, which checks `@model.loading?` and defers via
   `on_loading_changed` exactly as upstream's `GetInitialResultSetAsync`
   checks `model.loading`. Confirmed live: "a query run while the model is
   loading waits for notify::loading to clear" — passes.

Both fixes are also exercised end to end over the real session bus in
`drive_background_service.rb` (`GetInitialResultSet`,
`GetSubsearchResultSet`), not just the in-process `check_search_provider.rb`.

## Background service — `lib/background_service.rb` — activation path fixed, one narrow-drive-run gap remains

The double-wrap bug that silently dropped `LaunchSearch` (`show-search`'s
`'s'` parameter type was being wrapped as if it were `show-location`'s `'v'`)
is fixed: `call_main_app_action` now takes `double_wrap:`, and
`launch_main_app_search` passes `double_wrap: false`. Confirmed live:
`drive_background_service.rb`'s "LaunchSearch reached the windowed app over
ActivateAction" — passes, where it silently failed to assert anything
meaningful before this fix existed.

The three D-Bus activation files
(`org.gnome.WeatherRb.search-provider.ini`,
`org.gnome.WeatherRb.SearchProvider.service`, `org.gnome.WeatherRb.service`)
are present and read correctly — confirmed by direct read, matching
`BackgroundService::APP_ID`/`App::APP_ID`. This closes last round's "nothing
outside this test suite can ever start it" finding. A caveat the port cannot
close by itself: these three files are not installed anywhere
(`$(datadir)/dbus-1/services/`, `$(datadir)/gnome-shell/search-providers/`)
by any build/install task in this gem-packaged port — `gnome-weather-rb.gemspec`
has no mechanism to place data files outside Ruby's own load path, so a `gem
install` of this port places the `.service`/`.ini` files nowhere D-Bus or
Shell will ever read them from. The files existing in the repo is necessary
but not sufficient for the real-world activation path to work; this is a
packaging gap, tracked here rather than claimed closed.

**Remaining, narrow drive-coverage gap.** `drive_background_service.rb` now
drives 4 of the search-provider interface's 5 methods over the real bus
(`GetInitialResultSet`, `GetSubsearchResultSet`, `ActivateResult`,
`LaunchSearch`). `GetResultMetas` — the one method that actually produces
the name/description/icon a user sees in a search result — is still never
called over the real bus by any test in this tree. The commit introducing
this round's fixes says so itself ("`GetResultMetas` stays untested there,
tracked as a ruby-gnome `aa{sv}` unpacking gap"), and that claim is confirmed
independently in this audit: `grep -n GetResultMetas test/drive_*.rb` finds
only a comment explaining why it is skipped, no call. Its correctness is
verified **only** by calling the Ruby method directly
(`check_search_provider.rb`), never by actually marshaling an `aa{sv}` reply
onto a bus and back — the exact "component no check exercises... is
unverified, not done" case this round's task framing names. This is honestly
disclosed (in the commit message and in a code comment in the test file),
not hidden — but it is still a real gap in drive coverage for one full unit,
and this report records it as open rather than letting the other four
methods' pass count imply the fifth is covered too.

## Units entirely absent

| Unit | Upstream file(s) | What a user loses |
|---|---|---|
| Geolocation | `src/app/currentLocationController.ts` | The device's current city is never auto-added; `LocationRow`'s "this is you" treatment can never appear, for any user. Unchanged across three rounds. |

## Packaging surface — new finding this round, not previously tracked as a component-parity item

`component-identification.md` already lists the missing `.desktop` file,
AppStream metainfo and icon set as absent assets. This round's new
`.service`/`.ini` files make it worth stating plainly as a component-parity
verdict: **even with the D-Bus activation files present, this port ships no
discoverable application at all** — no launcher entry, no icon, and (as
above) no installed copy of the activation files either. Upstream's user can
find and launch Weather from the GNOME Shell overview by name and icon; this
port's user cannot, today, regardless of how correct `lib/background_service.rb`
and `lib/search_provider.rb` now are internally.

## Overall verdict

**20 of 21 upstream units have four-axis parity, verified live** — up from
18/21 last round, and every confirmed behavioural gap from that round is
fixed and re-verified, not just claimed. Component parity is substantially
better than last round, but still **not** reported as finished: geolocation
remains entirely absent, `GetResultMetas` remains unverified over a real bus,
and the whole app remains undiscoverable by a real desktop (no `.desktop`
file, no icon, no installed D-Bus activation files) independent of how
correct the in-process logic is.
