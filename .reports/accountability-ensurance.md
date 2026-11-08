# Accountability ensurance — gnome-weather-rb

| | |
|---|---|
| Upstream | `main` @ `6930d4a` |
| Port | `ruby` @ `3edcfea` |

Scope: `lib/`, `exe/`, `.reports/`, `README.md`, `AGENTS.md`, `CLAUDE.md`.
There is still no `PORTING.md` or `FINDINGS.md` in this fork.

```sh
grep -rniE 'TODO|FIXME|not implemented|for now|in a future' lib/ exe/ .reports/
```

returns, in `lib/`/`exe/`: **nothing literal**. In `.reports/`: only the
scanner pattern itself quoted inside `component-parity.md` and this file
(describing a `NotImplementedError` the ruby-gnome *binding* raises, and a
literal discussion of the phrase "for now" in `translation-parity.md` —
both are the scanner's own phrases being discussed, not an excuse being
made). As in both previous rounds, the port does not use those exact labels.
That is not the same finding as "no excuses" — three findings below are
exactly that, found by reading rather than grepping.

## Finding 1 (carried, now resolved) — the stale inventory file

Previous rounds' Finding 1 was `.reports/component-inventory.md` making a
claim ("shell_integration/background_service/search_provider absent") that
had gone stale. Checked again this round: the file already carries a
`> **Superseded.**` banner at its top, added before this round began,
correctly naming the three files that landed and pointing readers to
`component-identification.md`/`component-parity.md` instead. This is now
**self-disclosed staleness**, not a silent false claim — the failure mode
this report exists to catch is a document that misleads a reader who trusts
it, and a banner that tells the reader not to trust the body closes that.
Not re-flagged as an open finding; recorded as resolved so the next round
does not re-litigate it from scratch.

## Finding 2 — a false-green risk in how this round's own fixes are claimed, checked and found genuine

The commit message for `3edcfea` makes five specific, falsifiable claims
("GetResultMetas now serializes an 'icon' field", "LaunchSearch silently
never reached the windowed app" [now fixed], "GetResultMetas stays untested
there, tracked as a ruby-gnome aa{sv} unpacking gap"). Per this skill, a
claim in a commit message is exactly the kind of thing that must be
independently verified, not taken on trust, before a report repeats it as
fact. Each was checked directly in this audit rather than re-stated from the
commit:

- Icon field: read `lib/search_provider.rb`'s `meta_for`/`icon_for` directly
  — present. Ran `test/check_search_provider.rb` live — the specific check
  ("the meta carries a themed icon variant...") passes. **Confirmed, not
  just claimed.**
- `LaunchSearch` fix: read `call_main_app_action`'s `double_wrap:` parameter
  and `launch_main_app_search`'s call site directly — the fix matches the
  description. Ran `test/drive_background_service.rb` live — "LaunchSearch
  reached the windowed app over ActivateAction" passes. **Confirmed.**
- `GetResultMetas` untested-over-D-Bus claim: read `test/drive_*.rb` for any
  call to `GetResultMetas` over the real connection — none exists, only a
  comment explaining why. **Confirmed, and this is the one claim in the
  commit message that is an admission of a gap, not a claim of a fix** — it
  is reported here as still-open in `component-parity.md`/`test-parity.md`,
  not quietly dropped now that the other four claims checked out.

No false-green was found in this round's own claims — a meaningfully
different result from the previous round, where Finding 2 (the dropped icon
field) was a real, previously-unreported gap sitting behind calm, confident
prose that said nothing about it. This round's new code is not hiding
anything new; the one thing it still does not do (drive `GetResultMetas`
over a real bus) is named in the commit message, in a test-file comment, and
now in three report files. That is the accountability bar this skill sets,
met.

## Finding 3 (carried from two previous rounds, unchanged) — `weather_provider.rb`'s deferred rewrite remains untracked outside its own comment

`lib/weather_provider.rb`'s header comment (present since `028a1a6`, still
present verbatim this round: "a real follow-up, but a bigger change than
swapping a data source, so it is left as a named remaining item rather than
rewritten under this round's time budget") is honest about naming the owed
work (an async rebuild of `WeatherInfo` around `GWeather::Info`'s own cycle)
but still has no ledger entry anywhere outside that one comment — no
`PORTING.md` (still does not exist), no line in `component-parity.md`. This
is the third consecutive round this item has gone unaddressed and
un-tracked outside its own source comment. Not a false claim — a comment
that names its own deferral honestly is not an excuse in the sense this
skill warns against — but "honest and three rounds stale" is itself worth
naming: a deferred item with no external tracking tends to stay deferred
indefinitely, which is a process gap even where the comment itself is clean.

## Finding 4 — the packaging gap (no `.desktop`, no icons, no installed activation files) is correctly reported as a gap, not excused as "that's packaging, not porting"

This round added real D-Bus activation *files*, which created a specific
risk this skill is built to catch: declaring the gap "closed" because the
files exist, without checking whether they are reachable in a real install.
Checked directly in this audit (see `component-parity.md`): the three new
files are not installed anywhere by any task in `Rakefile`/the gemspec —
`gem install` places them nowhere D-Bus or GNOME Shell would read them from.
Nothing in `lib/`, `.reports/`, or the `3edcfea` commit message claims this
gap is closed; the commit message's own wording ("so GNOME Shell has a real
way to launch...") is arguably optimistic given the install gap, but no
report before this one stated the install-path caveat outright. Recorded
here as the thing closest to a false-green risk this round produced, caught
before it reached a report as an unqualified claim.

## Checked and found clean

- No "by design", "simplified", "streamlined", "out of scope", "not
  applicable", "does not carry over", "upstream does this too", "we don't
  need", "not required here" anywhere in `lib/`/`exe/`, including every file
  touched by `3edcfea`.
- `lib/util.rb`'s "deliberately not carried over" comment: re-checked again
  this round, still verified true against `misc/util.ts`.
- `translation-parity.md`'s own verdict is not softened anywhere in this
  tree — no comment or report calls the 0/49 translation count "not a
  priority" or similar; it is stated flatly as a gap in both
  `translation-parity.md` and this file.
- The new D-Bus files' error-handling (`rescue StandardError, GLib::Error`
  around both `export` methods) is a real defensive guard around a real
  D-Bus registration call, logged on failure, not a swallowed exception
  hiding a gap.

## Verdict

One real, previously-latent accountability risk (Finding 4 — a packaging
"fix" that is real but not yet reachable in a real install) is caught and
recorded before any report stated it as closed. One long-running, honest but
untracked deferral (Finding 3) persists for a third round. The specific
false-green pattern this report caught last round (a confirmed gap sitting
behind code that said nothing about it) was **not** reproduced this round —
this round's new/changed code is accompanied by accurate self-disclosure of
its one remaining limitation (`GetResultMetas`), checked independently
rather than taken on the commit's word, and found to hold up.
