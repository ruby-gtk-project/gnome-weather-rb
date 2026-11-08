# Test parity — gnome-weather-rb

| | |
|---|---|
| Upstream | `main` @ `6930d4a` |
| Port | `ruby` @ `3edcfea` |
| Upstream tests | 1 (`tests/world_view.py`, gated behind `-Ddogtail`, off by default) |
| Ported (named, bijective) | **1 / 1 — closed this round** |
| Test commands (port) | `nix develop --command xvfb-run -a ruby test/check_model.rb`, `test/check_search_provider.rb`, `test/drive_window.rb`, `test/drive_dbus_integration.rb`, `test/drive_background_service.rb` |
| RSpec suite (`rake spec` / `spec/`) | **empty — 0 examples, 0 failures, confirmed by running it** |

## Upstream census — unchanged

Upstream's one test, `tests/world_view.py` (run via `tests/meson.build`'s
`test('world_view', ...)`, gated by `get_option('dogtail')`), drives the
running app through the accessibility tree and asserts, in one run:

1. `places_button.showing`
2. `refresh_button.showing`
3. `not world_view.showing`
4. `city_view.showing`
5. `current_conditions.showing`
6. `weekly_forecast.showing`
7. `forecast.showing`

## Bijection against the upstream test — gap closed this round

`3edcfea` added a step to `drive_window.rb` ("`[6] world_view.py's basic-state
and forecast assertions`") that names and asserts all seven of the above,
one check per assertion, each labeled with its upstream source
(`"places button showing (world_view.py: places_button.showing)"`, etc.).
Confirmed by an independent live run in this audit — not taken on the
commit message's word:

```
[6] world_view.py's basic-state and forecast assertions
    ok   places button showing (world_view.py: places_button.showing)
    ok   refresh button showing (world_view.py: refresh_button.showing)
    ok   places popover not showing (world_view.py: not world_view.showing)
    ok   city view showing (world_view.py: city_view.showing)
    ok   current conditions showing (world_view.py: current_conditions.showing)
    ok   weekly forecast showing (world_view.py: weekly_forecast.showing)
    ok   forecast showing (world_view.py: forecast.showing)
```

All seven pass, all seven are individually named after the upstream
assertion they port. This is a genuine bijective port, not a relabeling:
`world_view.py`'s own accessible-name lookups (`app.child('Places')`,
`app.child('World view')`, etc.) correspond one-to-one to the checks above,
and the previous two rounds' "0/1, no ledger anywhere maps any check to it
by name" finding no longer holds. **Test parity for upstream's one test is
now 1/1.**

The only honest caveat: upstream's test is dogtail/pyatspi-driven (real
accessibility tree, real running Shell), and the port's version re-checks
the same propositions against the GTK widget tree directly rather than
through an accessibility layer. This is the same kind of substitution this
skill expects to be named, and it is named — in the step's own label and in
the `3edcfea` commit message ("dogtail-gated, unrunnable here") — not hidden.

## Port census and live run (this session)

```
test/check_model.rb              : 42 of 42 checks passed
test/check_search_provider.rb    : 14 of 14 checks passed
test/drive_window.rb             : 49 of 49 checks passed, DRIVE OK
test/drive_dbus_integration.rb   : 12 of 12 checks passed, DRIVE OK
test/drive_background_service.rb :  4 of  4 checks passed, DRIVE OK
```

Total: **121 of 121**, exactly matching this round's runtime-gate headline
(121 checks, 0 failed, 21 components). Each script was run individually,
sequentially, with no other `xvfb-run` process concurrent — the flake the
previous round observed under concurrent load was not reproduced, and was
not re-tested under concurrent load either (not chased further, consistent
with the previous round's own framing of it as an unconfirmed hypothesis).

**The RSpec suite, separately, is empty.** The dev shell's own banner names
`ruby -e 'require "rspec/core"; ...'` against `spec/` as "the specs" command.
Run directly in this audit:

```
No examples found.
0 examples, 0 failures
```

`spec/` contains only `spec_helper.rb` and a `README.md` describing the
`kettle-test` harness helpers available to specs that do not exist yet. This
is not a failing suite — it is a suite with nothing in it, which this skill
treats as distinct from, and worse than, a suite that has never been run:
it has been run, repeatedly, and asserts nothing every time. None of the 121
checks above are RSpec examples; they are output from five standalone Ruby
scripts under `test/`, which is where this port's actual test coverage
lives. Anyone reading `rake spec` reporting "0 failures" without reading
`test/` would reasonably conclude the suite passed trivially — it is
recorded here so that conclusion is not left standing uncontested.

**Narrowness within the 121, not just a pass count.** One upstream D-Bus
method, `GetResultMetas`, is still never driven over a real bus by any test
in this tree (see `component-parity.md` for the full account). Its logic is
covered by `check_search_provider.rb`'s direct, in-process call, which is
real coverage of the logic but not of the wire format. Per this round's own
framing, a component no check exercises over the real transport is
unverified, not done, and this one is in exactly that state — the only item
in the 121 passing checks that does not amount to full verification of what
it nominally covers.

## Extra

- `test/check_model.rb` — 42 checks, `Util`/`Location`/`Settings`/
  `WeatherProvider`/`WeatherInfo`/`WorldModel`. Verified live, 42/42.
- `test/drive_window.rb` — 49 checks (42 window-driving checks + 7 ported
  `world_view.py` assertions, see above). Verified live, 49/49, `DRIVE OK`.
- `test/check_search_provider.rb` — 14 checks on `SearchProvider`'s pure
  logic, including the icon field and the loading wait added this round.
  Verified live, 14/14.
- `test/drive_dbus_integration.rb` — 12 checks driving `shell_integration.rb`
  and the `show-location`/`show-search` actions over the app's own real D-Bus
  connection. Verified live, 12/12, `DRIVE OK`.
- `test/drive_background_service.rb` — 4 checks (up from 2 last round; now
  also drives `GetSubsearchResultSet` and `LaunchSearch` over the real
  session bus — `GetResultMetas` still excluded, see above). Verified live,
  4/4, `DRIVE OK`.
- `test/fake_provider.rb`, `test/gtk_driver.rb` — harness files, not test
  cases, unchanged.

## Summary

Test parity against upstream's one real test is **1/1, closed this round** —
a genuine improvement, verified independently rather than taken on faith.
The port's own, much larger test surface (121 checks) is real and passes
live. The two things keeping this report from reading as unqualified green:
the RSpec suite the dev shell also advertises is empty, and one D-Bus method
out of the whole surface remains unverified at the wire level.
