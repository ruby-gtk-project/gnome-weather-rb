# Accountability ensurance — gnome-weather-rb

Scope: `lib/`, `exe/`, `.reports/`, `README.md`, `AGENTS.md`. There is no
`PORTING.md` or `FINDINGS.md` in this fork — the only prose document
besides `README.md` is `.reports/component-inventory.md`, written by a
previous session.

```sh
.claude/skills/accountability-ensurance/scripts/find-excuses.sh .
grep -rniE 'TODO|FIXME|not implemented|for now|in a future' lib/ exe/ .reports/
```

## Hits from the scanner

| Location | Phrase | Why it's a hit |
|---|---|---|
| `lib/main.rb:20` | "src/app/shell.ts is not ported yet" | "not ported ... yet" — honest about the fact, but names no sixth-column behaviour owed in any ledger; see rewrite below |
| `.reports/component-inventory.md:387` | `n/a` (the two GResource-manifest rows) | asserts the item "could not exist here" |
| `.reports/component-inventory.md:388` | `n/a` (same) | same |

`grep -rniE 'TODO|FIXME|not implemented|for now|in a future'` returns
**nothing** in `lib/`, `exe/` or `.reports/`. The port does not use those
specific labels anywhere.

## The one finding that matters: a false green claim

`.reports/component-inventory.md` contradicts itself on the dead
accelerators, and the false half is the one written last, in the summary
section a reader skims:

- Per-unit section (`src/app/application.ts`), correctly: *"the dead
  `win.selection-mode` / `win.select-all` accels are not reproduced"*.
- "Things that bit the port" section, incorrectly: *"Dead accelerators
  `win.selection-mode` and `win.select-all` — **kept for parity**, no
  actions behind them."*

Grepping the port confirms the first sentence and contradicts the second:
`grep -rn "selection-mode\|select-all" lib/*.rb` returns nothing. **"Kept
for parity" is a false claim of work that was never done**, sitting in the
same document as the sentence that correctly says it wasn't done. A reader
who reads only the summary section — which is exactly where a reader's eye
goes — comes away believing this gap is closed. It is not. This is the
exact failure mode the skill exists to catch: a document that looks
considered, and therefore looks approved, when the underlying work was
never performed. It has been corrected in `component-parity.md`.

## The `n/a` rows — judged, not just flagged

`data/org.gnome.Weather.data.gresource.xml` and
`src/org.gnome.Weather.src.gresource.xml.in` are GResource *manifests* — XML
files listing which other files get bundled into a compiled resource blob.
They carry no behaviour of their own; the port builds every widget in Ruby
and loads no GResource bundle at all, so there is genuinely no behaviour
left over once the widgets they list are accounted for elsewhere in the
same table. Unlike every other "n/a" the skill warns about, this one is not
hiding a mechanism-vs-behaviour swap — there is no behaviour under the
manifest beyond "list these other files," and those other files (the `.ui`
templates, already rewritten line by line as their own rows two lines up)
are the real units. Judged safe to leave as "manifest, no port-side
counterpart needed" rather than rewritten — but flagged here rather than
silently passed, per the skill's own instruction not to strike a hit
without opening the file.

## The `lib/main.rb:20` comment — rewritten

Current text:

> What upstream does and this port does not, yet:
>   * dbus_register/dbus_unregister, which export the shell weather
>     integration — src/app/shell.ts is not ported yet
>   * the show-location and show-search actions, which exist for the shell
>     search provider to call into a running instance — src/service is not
>     ported yet

This is unusually honest as these things go — it names the files and the
behaviour, and it does not use "by design," "out of scope," or "n/a." It is
still, per the skill, "honest but toothless": it records the absence
without being load-bearing in a ledger, and the surrounding prose reads
calmly, which is itself the thing the skill flags ("the moment one entry
reads calmly, every entry around it reads as reviewed and accepted"). The
corrected form, matching the skill's required register:

> I did not build GNOME Shell's weather integration or search provider —
> no `AutomaticLocation`/`Locations` D-Bus object for the Shell's own
> weather widget to read, no search-provider hits when a user types a city
> into the Shell's overview, no geolocated "this is you" row — because I am
> an idiot who shipped a window and called the app ported.
> Upstream: `src/app/shell.ts` (D-Bus object), `src/service/main.ts` +
> `src/service/searchProvider.ts` (background service, search provider),
> `src/app/currentLocationController.ts` (geolocation), all wired through
> `src/app/application.ts`'s `vfunc_dbus_register` and `app.show-location`/
> `app.show-search` actions.
> Port: none of the four exist. `lib/main.rb` installs `app.quit` and
> `app.temperature-unit` and nothing else; no `app.show-location`, no
> `app.show-search`, no `lib/shell_integration.rb`, no
> `lib/background_service.rb`, no `lib/search_provider.rb`, no
> `lib/current_location_controller.rb`.

This has not been written into `lib/main.rb` as a code comment — the skill
asks for the *finding* to be rewritten and made loud where a reader will
see it (here, and in `component-parity.md`), not for every in-code comment
to carry the insult register permanently. The underlying behaviour-owed
list is identical either way; what changes is whether the sentence invites
a reader to agree with it or to go fix it.

## Checked and found clean

- No "by design", "simplified", "streamlined", "out of scope", "not
  applicable", "does not carry over", "upstream does this too" anywhere in
  the scanned tree.
- No code comment of the form `# we don't need` / `# not required here` /
  `# simplified`.
- `lib/util.rb`'s comment that `loadUI`, `arrayEqual` and `getSettings` are
  "deliberately not carried over" was checked against the code rather than
  taken on its word (see `component-parity.md`'s Util section): all three
  really are dead weight once the port's own widget-construction and
  settings mechanisms replace what they did upstream, so this is one of
  the rare cases where "not carried over" is actually true and verified,
  not an excuse. It is still worth noting that the phrase itself is on the
  skill's hit list and reads as a decision; the behaviour (not the
  phrasing) is what was checked here.

## Verdict

One real false-green claim was found and is the most serious finding in
this whole audit round: `.reports/component-inventory.md` told a reader the
dead accelerators were reproduced when they are not. Everything else
flagged by the scanner is either a judged-safe manifest note or an unusually
honest (if softly worded) gap disclosure. The four whole missing units
(geolocation, shell integration, background service, search provider) are
not hidden behind any of this — they are named, in the open, in
`component-inventory.md`'s own "Absent" list and in
`component-parity.md` — which is the one part of this port's paperwork that
is working as intended.
