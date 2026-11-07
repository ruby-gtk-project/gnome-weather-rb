# Test parity — gnome-weather-rb

| | |
|---|---|
| Upstream | `main` @ `6930d4a` |
| Port | `ruby` @ `a52fce1` |
| Upstream tests | 1 (gated behind `-Ddogtail`, off by default) |
| Ported (named, bijective) | 0 |
| Gaps | 1 |
| Test command (port) | `nix develop --command xvfb-run -a ruby test/check_model.rb` and `... test/drive_window.rb` |

## Upstream census

`test-census.sh` returns **0** rows against `../gnome-weather-upstream`,
because upstream's one test case is not written in any framework the
script's patterns match (`unittest`, `pytest`, `#[test]`, GLib
`Test.add_func`, etc.) — it is a raw Python script driven through meson's
`test()`, using plain `assert`. Cross-checking against the build file
(`tests/meson.build`) catches exactly the case the skill warns about: a
declared test with zero census rows.

```
tests/meson.build:
  test('world_view', pyexec, args: ['tests/world_view.py'], ...)
  gated by: if get_option('dogtail')
```

So by hand: upstream has **one** named test, `world_view`
(`tests/world_view.py`), built only when the `dogtail` meson option is
enabled (it is not upstream's default). It uses `pyatspi`/`dogtail` to drive
the running app through the accessibility tree and asserts, in one run:

- the places button, refresh button and city view are all showing on startup
- the world view (places popover) is not showing
- the current-conditions, weekly-forecast and forecast widgets are all showing

## Port census

```
scripts/test-census.sh .  →  116 rows
  test/check_model.rb    42 checks  (Util, Location, Settings, WeatherProvider, WeatherInfo, WorldModel)
  test/drive_window.rb   41 checks  (live-driven window/places/search/unit/About flow)
```

Wait — census counts 116 named rows but the two suites' own headline totals
(verified live, below) are 42 and 41 — **83, not 116**. The remaining 33
rows are `step(...)`/intermediate narration lines the census script also
picked up (`[0] the welcome page is showing`, `[1] type a city into the
places popover`, etc. — numbered steps in `drive_window.rb`, not assertions).
Per the skill's guidance ("decide which call is this suite's assertion unit
before you trust the count"), the pass-counter increment in both files is
`check(...)`, not the numbered `step` lines, and the live runs below (42 +
41 = 83) are the number to report, not the raw 116-row census.

## Live run (this session, `nix develop --command xvfb-run -a ruby ...`)

```
test/check_model.rb : 42 of 42 checks passed
test/drive_window.rb: 41 of 41 checks passed
DRIVE OK
```

This matches, exactly, the runtime gate this round reports for the whole
port: **41 checks, 0 failed, 18 components** — which is `drive_window.rb`
alone. `check_model.rb`'s 42 checks (the whole model/data layer: `Util`,
`Location`, `Settings`, `WeatherProvider`, `WeatherInfo`, `WorldModel`) are
**not counted in that 41**, run under a separate invocation, and are not
mentioned in the gate's "18 components" figure at all. Taken together the
gate's "41 checks… 18 components" undercounts what the port's own suite
actually verifies — a second, wider check the gate did not run — rather than
overcounts it; it is not a false claim, but a narrower claim than the full
picture, and should not be read as the whole suite.

## Bijection against the upstream test

Zero. None of the 83 live checks is named after, or written as a port of,
`world_view`. The port's `drive_window.rb` happens to assert overlapping
ground by accident of both testing the same app ("weather page visible",
"the primary menu is showing", "info page is showing") but no row in either
file traces back to the upstream test by name, and the census/ledger
discipline this skill requires — one upstream test, one named port test,
rows never merged or renamed — was not followed because there is no ledger
at all recording the mapping.

## Gap

| # | Upstream test | Purpose | Port test | State |
|---|---|---|---|---|
| 1 | `world_view` (`tests/world_view.py`) | on startup: places/refresh buttons and city view show, world view does not; current-conditions, weekly-forecast and forecast widgets all show | — | **gap** |

Behaviour still owed: a test that drives the real running port (not a mock)
and asserts, from outside the window class, that on first launch the
places button, refresh button and the city view are visible, the places
popover is not, and the current-conditions/forecast widgets are all
showing. `drive_window.rb`'s existing checks (`"weather page visible"`,
`"a temperature is shown"`, `"refresh is revealed"`) assert closely related
facts but were written independently, not as a port of this test, and carry
no name tying them to it.

## What this does and does not mean

- Upstream ships essentially no inherited safety net: one optional,
  accessibility-driven smoke test, off by default. The port's 83 checks are
  real, substantial, and all pass live — but they are **extra**, not
  parity, per the skill's own worked example (`planify-rb`): a bigger,
  green suite the port wrote for itself is not evidence that it ported
  upstream's test, because it didn't.
- Test parity is **0/1** by strict bijection. It would read **0/0, trivially
  met** only if upstream's `world_view` test did not exist at all; it does,
  it is just gated off by default, which does not remove it from the
  census.

## Extra

- `test/check_model.rb` — 42 checks on `Util`, `Location`, `Settings`,
  `WeatherProvider`, `WeatherInfo`, `WorldModel`. Verified live, 42/42.
- `test/drive_window.rb` — 41 checks driving the window, search, places
  popover, unit switch and About dialog end to end, with 12 screenshots.
  Verified live, 41/41.
- `test/fake_provider.rb`, `test/gtk_driver.rb` — harness files (excluded
  from the census by the skill's own `*fixture*`/`*driver*` filter); not
  test cases.
