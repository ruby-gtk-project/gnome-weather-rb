# Test parity — gnome-weather-rb

| | |
|---|---|
| Upstream | `main` @ `6930d4a` |
| Port | `ruby` @ `ce70e77` |
| Upstream tests | 1 (gated behind `-Ddogtail`, off by default) |
| Ported (named, bijective) | 0 |
| Gaps | 1 |
| Test commands (port) | `nix develop --command xvfb-run -a ruby test/check_model.rb`, `test/check_search_provider.rb`, `test/drive_window.rb`, `test/drive_dbus_integration.rb`, `test/drive_background_service.rb` |

## Upstream census — unchanged this round

Upstream's one test, `tests/world_view.py` (run via `tests/meson.build`'s
`test('world_view', ...)`, gated by `get_option('dogtail')`), has not
changed since the last audit. It drives the running app through the
accessibility tree and asserts, in one run:

- the places button, refresh button and city view are all showing on startup
- the world view (places popover) is not showing
- the current-conditions, weekly-forecast and forecast widgets are all showing

## Port census — grown by three files this round

Three new test files landed alongside the shell-integration/search-provider/
background-service work:

```
test/check_model.rb           42 checks  (unchanged)
test/drive_window.rb          42 checks  (was 41; +1 for the new accel/action wiring)
test/check_search_provider.rb 12 checks  (new — ranking, subsearch, metas, callbacks, no D-Bus)
test/drive_dbus_integration.rb 12 checks (new — shell integration + show-location/show-search over a real bus)
test/drive_background_service.rb 2 checks (new — the two-process search flow over a real bus)
```

## Live run (this session, `nix develop --command xvfb-run -a ruby ...`)

```
test/check_model.rb             : 42 of 42 checks passed
test/check_search_provider.rb   : 12 of 12 checks passed
test/drive_window.rb            : 42 of 42 checks passed (re-run clean 3/3 after one 41/42 failure; see component-parity.md)
test/drive_dbus_integration.rb  : 12 of 12 checks passed
test/drive_background_service.rb:  2 of  2 checks passed, DRIVE OK
```

Total live-verified checks this round: **110** (42+12+42+12+2). This is close
to, but not identical to, the runtime gate's own headline for this round
(**108 checks, 0 failed, 21 components**); the 2-check difference was not
tracked down to a specific cause (a different invocation set, a different
commit, or a different pass/step-counting convention are all plausible — see
the discussion of this exact ambiguity in last round's report for
`check_model.rb`/`drive_window.rb`'s "41 vs 42" gap). Reported rather than
silently rounded to match, because the point of this skill is not to make the
numbers agree.

**Narrowness, not just a count.** `drive_background_service.rb`'s 2 checks
exercise 2 of the search-provider interface's 5 D-Bus methods
(`GetInitialResultSet`, `ActivateResult`); `GetSubsearchResultSet`,
`GetResultMetas` and `LaunchSearch` are never driven over a real bus by any
test (see `component-parity.md` for why `GetResultMetas` specifically
cannot be, with ruby-gnome in its current state). Per this round's own
framing: a component no check exercises is unverified, not done, and two of
five methods on this interface are in exactly that state.

## Bijection against the upstream test — unchanged, still 0/1

Still zero. None of the 110 live checks is named after, or written as a port
of, `world_view`. No ledger anywhere in this tree maps any check to it by
name.

## Gap

| # | Upstream test | Purpose | Port test | State |
|---|---|---|---|---|
| 1 | `world_view` (`tests/world_view.py`) | on startup: places/refresh buttons and city view show, world view does not; current-conditions, weekly-forecast and forecast widgets all show | — | **gap**, unchanged |

## What this does and does not mean

- The port's test suite is real, substantial, and (modulo the one observed
  flake, discussed in `component-parity.md`) passes live. It is still
  **extra**, not parity: none of it is a port of `world_view.py`, and test
  parity and component parity are separate claims (per the skill) — three
  new, well-tested components landing this round does not change the
  bijection count against upstream's one test by itself.
- Test parity is **0/1** by strict bijection, same as last round.

## Extra

- `test/check_model.rb` — 42 checks, `Util`/`Location`/`Settings`/
  `WeatherProvider`/`WeatherInfo`/`WorldModel`. Verified live, 42/42.
- `test/drive_window.rb` — 42 checks driving the window end to end. Verified
  live, 42/42 (see the flake note in `component-parity.md`).
- `test/check_search_provider.rb` — 12 checks on `SearchProvider`'s pure
  logic. Verified live, 12/12.
- `test/drive_dbus_integration.rb` — 12 checks driving `shell_integration.rb`
  and the `show-location`/`show-search` actions over the app's own real D-Bus
  connection. Verified live, 12/12.
- `test/drive_background_service.rb` — 2 checks driving the two-process
  search flow over the session bus. Verified live, 2/2, but narrow — see
  above.
- `test/fake_provider.rb`, `test/gtk_driver.rb` — harness files, not test
  cases, unchanged.
