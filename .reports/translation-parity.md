# Translation parity — gnome-weather-rb

| | |
|---|---|
| Upstream | `main` @ `6930d4a` |
| Port | `ruby` @ `ce70e77` |
| Domain | `gnome-weather` (unconfirmed — read from `meson.project_name()`, no committed `.pot` or `GETTEXT_PACKAGE` to confirm against) |
| Upstream messages | 49 |
| Ported | 0 |
| Gaps | 49 |
| Extra (untranslated) | 0 |
| Upstream occurrences | 59 across 49 messages (5 reused) |
| Port occurrences | 0 |
| Upstream languages | 87 `.po` files, 4,164 translated, 31 untranslated, 2 fuzzy |
| Languages shipped by the port | 0 |
| Build command | none — the port has no gettext dependency to build |

Generated with:

```
.claude/skills/translation-parity/scripts/catalogue.rb <upstream-tree> --role upstream
.claude/skills/translation-parity/scripts/catalogue.rb .               --role port
.claude/skills/translation-parity/scripts/catalogue.rb --compare <upstream.yaml> <port.yaml>
```

`summary.parity: false` — gaps 49, `languages_missing` all 87, `domain_matches: false`.

## The headline — unchanged since the last round, now re-verified against three new files

The port still has **no `po/` directory, no gettext dependency (`gem
'gettext'`, `gem 'fast_gettext'` or similar), and zero calls to `_`, `N_`,
`n_`, `C_` or any other marker** anywhere in `lib/`. Confirmed by direct grep
(`grep -rn "gettext\|def _\|require 'gettext'" lib/` returns nothing) and by
the catalogue scan, which returns `messages: 0` for the port tree. Every
user-visible string in the running app — "Welcome to Weather!", "Search for
a city or country", button tooltips, the About dialog's strings, the
`%d°`/`Feels like %.0f°` labels, the updated-time phrasing — is a bare Ruby
literal. This is not "translation not finished yet"; per the skill, that
phrase is itself a gap wearing a justification. The port is English-only,
today, for all 87 languages upstream already ships.

This round added `lib/shell_integration.rb`, `lib/search_provider.rb` and
`lib/background_service.rb`, which carry two of upstream's existing 49
messages between them (`src/service/searchProvider.ts:214`'s `_('%s, %s')`,
reused by `lib/search_provider.rb`'s `description_for` as a bare
`format('%s, %s', ...)` call with no marker, and `src/service/main.ts:50`'s
`_('Weather')`, reused by `lib/background_service.rb`'s
`GLib.application_name = 'Weather'`, also bare). Both were already counted
as gaps in the upstream catalogue before this round's work landed (confirmed:
`grep -n 'searchProvider.ts:214\|service/main.ts:50'
.reports/upstream-catalogue.yaml` finds both occurrences already on record),
so this round changes neither the 49/0 message count nor the gap list — it
just confirms the new Ruby call sites repeat the same unmarked-literal
pattern as everywhere else in this port, rather than introducing a second,
undiscovered class of gap.

## Upstream catalogue

| Source | Rows (approx., by file role) |
|---|---|
| `src/app/*.ts` | the bulk — window/menu/dialog/popover/forecast strings |
| `data/org.gnome.Weather.gschema.xml` | GSettings schema summaries/descriptions |
| `data/org.gnome.Weather.desktop.in.in` | `Name`, `Comment`, `Keywords` |
| `data/org.gnome.Weather.metainfo.xml.in.in` | AppStream `<summary>`/`<p>`/`<li>` |

**49 distinct messages, 59 call sites** (5 messages reused — e.g. the
degree-sign formats and a couple of button labels shared between the window
and the search page). **5 are plurals** (the "Updated N minutes/hours/days
ago" family), **0 carry a msgctxt**. 1 unresolved marker (a dynamic lookup
the census could not read as a literal — worth hand-censusing before this
ledger is treated as exhaustive, which it is not yet).

`po/` holds **87 `.po` files** with **4,164 translated, 31 untranslated and
2 fuzzy** strings, and `LINGUAS` matches the file list (checked with
`diff <(ls po/*.po | basename -s .po) <(sort po/LINGUAS)` equivalent via the
catalogue's `linguas_matches_files` field).

## Port catalogue

Zero, in every column:

```
messages: 0, occurrences: 0, reused: 0, plural: 0, with_context: 0
languages: { count: 0, list: [] }
```

## Why none of the 24 non-code messages can even be ported yet

Per `component-identification.md`, the port has no `.desktop` file, no
`.metainfo.xml`, and no `.gschema.xml` — none of those three files exist
anywhere in the port tree, still true after this round's work. So even
closing every string-literal gap in `lib/` would still leave the
desktop/metainfo/schema strings with nowhere to live. That is simultaneously
a translation gap and the component gap `component-parity.md` already names;
it is tracked once here as the reason those rows cannot move past "gap"
without component work landing first. The two new `.xml` node definitions
this round added (`ShellWeatherIntegration.xml`'s and
`ShellSearchProvider2.xml`'s interface descriptions, now inlined as
`NODE_XML` heredocs in `lib/shell_integration.rb` and
`lib/search_provider.rb`) carry no translatable strings on either side —
D-Bus introspection XML has none — so they do not change this section.

## Closing this

Per the skill's four-line discipline, nothing has been done yet:

1. Upstream's `po/` has not been copied into the port.
2. No gettext domain has been picked (and `gnome-weather` must be kept —
   confirming it needs `po/meson.build` or a committed `.pot`, neither of
   which exists in this fork yet, so it is `unconfirmed`).
3. No gap row has been transcribed — there is no ledger entry-by-entry
   table in this report because the generated YAML carries 0 port messages
   against 49 upstream ones; a 49-row table where every `Port site` cell
   reads "—" would say nothing a reader does not already get from the
   summary numbers above.
4. The census has not found a single port-side message to call `ported`.

## Checks not run

- `msgfmt -c` / `rmsgfmt` validation — moot, there is no `.po` to compile.
- Running the app under `LANGUAGE=de LC_ALL=de_DE.UTF-8` and asserting a
  translated string on screen — moot for the same reason, and not attempted.

## Report

**0/49 messages · 0/59 occurrences · 0/87 languages · 0/4,164 strings.**
`summary.parity: false`. This is not "English-only for now" — the 87
languages exist today, in the same repository, on `origin/main`, and
shipping without them is a regression the port introduces by never having
wired gettext in the first place. Unchanged by this round's component work:
three new files landed, zero new translation markers landed with them.
