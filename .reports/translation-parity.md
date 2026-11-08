# Translation parity — gnome-weather-rb

| | |
|---|---|
| Upstream | `main` @ `6930d4a` |
| Port | `ruby` @ `3edcfea` |
| Domain | `gnome-weather` (unconfirmed in the port — no committed `.pot`, no `GETTEXT_PACKAGE`, no gettext dependency to confirm against) |
| Upstream messages | 49 (`po/POTFILES.in`: 7 `data/*.ui`/`.xml`/`.in.in` files + 9 `src/**.ts` files) |
| Ported | **0** |
| Gaps | **49** |
| Upstream languages | 100 `.po` files listed in `po/LINGUAS` |
| Languages shipped by the port | **0** |
| Build command | none — the port has no gettext/i18n dependency at all |

`summary.parity: false`. Unchanged from both previous rounds, re-confirmed
directly against the current tree rather than carried forward.

## Re-confirmed this round

```sh
grep -rn "gettext\|def _(\|require 'gettext'\|require \"fast_gettext\"" lib/
```

returns nothing. `gnome-weather-rb.gemspec` declares no gettext-family
dependency. There is no `po/` directory anywhere in the `ruby` branch tree.
Every user-visible string in the running app — window titles, the welcome
page, search placeholder, tooltips, the About dialog's strings, forecast
labels, period names ("Night"/"Morning"/"Afternoon"/"Evening" in
`lib/day_entry.rb`), the `%s, %s` conditions/temperature description in
`lib/search_provider.rb`, `GLib.application_name = 'Weather'` in
`lib/background_service.rb` — is a bare Ruby literal with no translation
marker. This is not "translation not finished yet": per this skill, that
framing is itself a gap wearing a justification, and nothing in this tree
states it that way regardless.

## What changed in this round's commit, checked against the catalogue

`3edcfea` touched `lib/search_provider.rb`, `lib/background_service.rb`,
`lib/main.rb`, `lib/window.rb` and three new `data/*.service`/`.ini` files.
None of the diff's additions are new user-facing strings that would move the
49/0 count:

- The new `icon` field in `search_provider.rb`'s `meta_for` is a GVariant
  structural key (`'icon'`), not a displayed string.
- The `devel` CSS class name and `GNOME_WEATHER_APP_ID`/`DEVEL_APP_ID`
  constants are identifiers, not user-visible text.
- The three new `.service`/`.ini` files carry no translatable strings
  (confirmed by reading all three: `DesktopId`, `BusName`, `ObjectPath`,
  `Name`, `Exec` keys only — upstream's own `.ini.in`/`.service.in` templates
  carry none either).

So this round's real, substantial feature work left the translation count
exactly where it was: **49 upstream messages, 0 ported, 49 gaps**, now
re-verified against three more rounds of commits rather than stated once and
assumed to still hold.

## Upstream catalogue (unchanged in shape from the last round)

| Source | Role |
|---|---|
| `data/day-entry.ui`, `places-popover.ui`, `weather-widget.ui`, `window.ui` | UI template strings (labels, tooltips, button text) |
| `data/org.gnome.Weather.desktop.in.in` | Name/Comment/Keywords for the launcher |
| `data/org.gnome.Weather.gschema.xml` | setting summary/description strings |
| `data/org.gnome.Weather.metainfo.xml.in.in` | AppStream name/summary/description |
| `src/app/application.ts`, `city.ts`, `dailyForecast.ts`, `hourlyForecast.ts`, `window.ts`, `world.ts` | runtime strings: period names, error states, menu/dialog text |
| `src/misc/util.ts` | shared formatting strings (e.g. temperature/weekday formats) |
| `src/service/main.ts`, `searchProvider.ts` | `_('Weather')`, `_('%s, %s')` (conditions/temperature description) |

All of the above remain gaps. None of these source files has a ported,
marked-for-translation counterpart anywhere in `lib/`.

## The 100-language question

Upstream ships 100 `.po` files (`po/LINGUAS`). The port ships none, and has
no mechanism (no `.pot`, no `msgfmt`/`msgmerge` task, no gettext runtime
call) by which it ever could without first adding the marker calls this
report finds absent. This is a single root gap (no i18n infrastructure at
all), not 100 separate per-language gaps, but its user-facing effect is the
same as 100 gaps: a user running this port in any locale but English sees
English, where upstream shows their language if translated.

## Verdict

**Not clean.** The port is English-only today, for all 100 languages
upstream already ships, with zero change across three consecutive audit
rounds despite substantial feature work landing in each of them. This is
the single largest, most consistent gap in this fork.
