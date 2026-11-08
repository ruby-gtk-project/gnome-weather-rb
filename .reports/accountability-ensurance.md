# Accountability ensurance — gnome-weather-rb

| | |
|---|---|
| Upstream | `main` @ `6930d4a` |
| Port | `ruby` @ `ce70e77` |

Scope: `lib/`, `exe/`, `.reports/`, `README.md`, `AGENTS.md`. There is still
no `PORTING.md` or `FINDINGS.md` in this fork. `.reports/component-inventory.md`
(written by a previous session, pre-dating this audit's skill-named reports)
remains in the tree and is itself checked below.

```sh
grep -rniE 'TODO|FIXME|not implemented|for now|in a future' lib/ exe/ .reports/
```

returns **nothing** literal in `lib/` or `exe/`. As last round, the port does
not use those exact labels. That is not the same finding as "no excuses" —
see below.

## Finding 1 — a stale document now makes the opposite false claim it made before

`.reports/component-inventory.md` was written against an older commit and
says, in its "Absent" list and three per-unit sections (lines 69, 387-408):

> Absent: `current_location_controller.rb`, `shell_integration.rb`,
> `background_service.rb`, `search_provider.rb`

This was true when written. It is **false now**: `ce70e77` added
`lib/shell_integration.rb`, `lib/background_service.rb` and
`lib/search_provider.rb`, all three non-trivial and all three driven live
(see `component-parity.md`). Last round's finding in this same report was a
false-**green** claim (work claimed done that wasn't); this is the opposite
direction — a false-**red** claim, a document telling a reader work is
missing that has since landed. It is less dangerous than a false green (a
reader who trusts it undersells the port, not oversells it), but it is the
same root cause the skill names: **a document nobody updates becomes false
the moment the code under it moves**, regardless of which direction the
error points. `.reports/component-inventory.md` has not been corrected or
retired, and nothing in this tree marks it stale. Flagged here rather than
silently worked around, per the skill's instruction to open and judge every
hit rather than strike it on sight.

## Finding 2 — a real, now-confirmed gap sits behind calm, confident prose in the new code itself

`lib/search_provider.rb`'s `meta_for` method and the comment above the
`ranked` method both read as settled, reasoned engineering — the ranking
collapse to two buckets is explained and justified, the icon field is simply
never mentioned at all. Per the skill, the dangerous case is not the comment
that announces a gap, it is the one that says nothing, because a reader has
no reason to go looking. Opening `search_provider.ts` against
`lib/search_provider.rb` line by line (done in `component-parity.md`) found
upstream's `GetResultMetas` returns an `icon` field this port's `meta_for`
never builds. No comment, test, or report anywhere in this fork said so
before this audit. This is the exact failure mode the skill exists to catch:
code that reads as complete because nothing in it admits otherwise.

## Finding 3 — a claim resting on something the test suite admits it cannot run

`test/drive_background_service.rb`'s own comment says plainly that
`GetResultMetas`'s real D-Bus reply "crashes `call_finish`" in the current
ruby-gnome bindings, and that this is why the test calls the Ruby method
directly instead of over the bus. This is **good** disclosure, written
exactly where a reader driving the test would see it — the opposite of a
hidden gap. Reproduced directly in this audit (a minimal script hitting
`GetResultMetas` over a real D-Bus connection raises
`NotImplementedError: TODO: GVariant({sv}) -> Ruby` from inside
`GObjectIntrospection::MethodInfo#invoke`, confirming the comment's claim is
accurate and not stale). The accountability concern is narrower than the
comment itself: **no report in this tree, before this one, named the
consequence** — that `GetResultMetas`'s wire-format correctness is therefore
verified by exactly one path (a direct Ruby call bypassing D-Bus
marshaling), on an interface whose entire purpose is to be called over D-Bus
by a process that is not this test. The code comment is honest about the
binding limitation; nothing until `component-parity.md` (this round) said
"and therefore this method's real behaviour is unverified." A true
statement in a test file is not the same as the finding it implies being
written down anywhere a reader of the *reports* would see it.

## Finding 4 — a deferred rewrite, named honestly, but still an open item with no tracking

`lib/weather_provider.rb`'s header comment (present since `028a1a6`,
unchanged this round, so not new, but not previously called out in this
report either) says:

> Rebuilding `WeatherInfo` around `GWeather::Info`'s own async cycle is a
> real follow-up, but a bigger change than swapping a data source, so it is
> left as a named remaining item rather than rewritten under this round's
> time budget.

This does not match any of the scanner's literal phrases ("for now", "TODO",
etc.), which is exactly why a literal grep is not sufficient on its own —
"this round's time budget" is a time-boxing excuse in the same family as "for
now," just worded differently, and the skill's job is to catch the family, not
the exact string. Judged on substance: it names the specific behaviour owed
(async rebuild of `WeatherInfo` around `GWeather::Info`'s own cycle) and the
reason it is deferred, which is honest — but there is no ledger entry
anywhere (`component-parity.md`, `PORTING.md` — which does not exist — or
elsewhere) carrying this item forward. It lives in one comment, in one file,
and nothing outside that comment would tell a reader it is still owed. Not a
false claim, but an untracked one; noted here so it is tracked at least once,
outside the source file itself.

## Checked and found clean

- No "by design", "simplified", "streamlined", "out of scope", "not
  applicable", "does not carry over", "upstream does this too" anywhere in
  the scanned tree, including the three new files.
- No code comment of the form `# we don't need` / `# not required here`.
- `lib/util.rb`'s "deliberately not carried over" comment: re-checked this
  round, still verified true (see `component-parity.md`'s Util section,
  unchanged).
- The new D-Bus files' error-handling (`rescue StandardError, GLib::Error`
  around both `export` methods, warning and returning `nil`) does not hide a
  gap behind a swallowed exception — it is a real defensive guard around a
  real D-Bus registration call, and a failure there is logged, not silently
  dropped.

## Verdict

Two real findings survive this round's adversarial pass: a confirmed,
previously unreported component gap (`GetResultMetas`'s missing icon field,
Finding 2) and a confirmed verification gap on the same method (Finding 3) —
both now written down in `component-parity.md` and `test-parity.md` as well
as here, per the skill's "tracked in both places" rule. Neither is hidden;
both were found only by opening the files rather than trusting the new
code's own calm framing, which is the point of this skill. The stale
`component-inventory.md` (Finding 1) is a documentation-hygiene problem, not
a disguised gap — but it is exactly the kind of drift that turns into a
false claim the next time someone reads only the summary, which is the
lesson last round's "kept for parity" finding already taught this fork once.
