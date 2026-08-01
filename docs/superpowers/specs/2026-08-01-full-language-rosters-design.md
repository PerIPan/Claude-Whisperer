# Full language rosters for Dictate and Voice

**Date:** 2026-08-01
**Status:** Approved, not yet implemented
**Version:** 2.0.1 (no bump — version bumps are the owner's call)

## Problem

Both language rosters in Settings are far narrower than the engines behind them.

**Dictate** offers 18 languages, hardcoded in `SettingsData.languages`. WhisperKit's
`Constants.languages` exposes **100** codes, and large-v3-turbo is a single multilingual
model — every one of those codes already works today. The picker is the only thing
gating them, and it costs nothing to widen: no extra model, no extra download.

**Voice** offers 9 Kokoro languages plus a deliberately curated 5 Supertonic ones.
`TTSVoiceRouter.supertonicLanguages` already accepts all **31** Supertonic languages,
and `resolve_language_line()` in `hooks/voice-shared.sh` already carries display names
for all 30 non-English ones — Greek included. `supertonic:el:F1` works *today* via
`OW_TTS_VOICE`; it simply is not in the picker. All 31 languages ride in the one
~264 MB model, so exposing them adds zero bytes.

Two secondary problems in the Voice picker, both raised by the owner:

- It is **opaque**. A selected voice collapses to `F1 (F)` with no language shown.
  `F1`/`M1` are generic speaker *styles*, not regional accents — a fact recorded in the
  2.0.0 spec that never reached the UI. And picking a non-English voice silently changes
  what the model *writes* to the `speak` tool (`resolve_language_line()`), which nothing
  in Settings hints at.
- It has **no search**. Going from 14 groups to 33 makes that worse.

## Decisions

Settled with the owner before design; recorded here so they are not re-litigated.

| Decision | Choice | Why |
|---|---|---|
| Dictate scope | **All 100**, sorted into three quality tiers | Label, don't hide — see "Quality tiers" |
| Dictate picker | Searchable popover, captioned sections | 100 rows do not belong in a flat menu |
| Dictate default | **English**, not Auto-detect | See "Default language" |
| Cantonese | Own entry, separate from Chinese | Whisper has distinct `yue`/`zh` tokens |
| "Common" section | Today's 18, verbatim, in current order | Preserves muscle memory |
| Voice scope | The **24** Supertonic languages Kokoro cannot speak | No language appears twice |
| Voice styles | F1/M1 only | Styles are not accents; 10× the rows buys no real choice |
| Voice group order | Kokoro 9 first, then Supertonic 24 alphabetical | Keeps English at the top |
| Voice picker | Same searchable popover, plus explanatory labels | Owner asked for both |
| Preview | Yes, a play button | The only way to know what `F1` sounds like |

## Quality tiers

The owner first asked to exclude languages with very high WER, then revised to ship all
100 and let the user decide. Both readings need the same evidence, so the measurement
below still drives the design — it just sets a **section boundary and a badge** instead
of an exclusion.

Why labelling beats cutting: whether 34% WER is unusable depends on the task (dictating
prose vs. a two-word command) and on the alternative (for the one Faroese speaker, an
untested model beats nothing). A hard cut makes the app decide something it cannot know.
Labelling means nobody is blocked and nobody is misled into thinking Lingala works as
well as Dutch. It is the same principle applied to the Voice tab: explain, don't hide.

The measurement is derived from published data, not judgment.

**Source.** OpenAI's `language-breakdown.svg` (openai/whisper, `main`) — the per-language
chart in the Whisper README, published for **large-v3**, titled "all languages where
Whisper large-v3 performs lower than 60% error rate". matplotlib glyph-outlines its text,
so the numbers were recovered by decoding each `<use xlink:href="#DejaVuSans-XX">`
codepoint. Two panels: **Common Voice 15** (57 languages) and **FLEURS** (61). Each
language is taken at its better result of the two.

**What that yields.** Of WhisperKit's 100 codes, **65 have a published number** and
**35 do not** — absent from a chart whose own inclusion rule was "under 60% error".
Those 35 are either above 60% error or were never benchmarked; either way there is no
evidence they work.

So every code lands in exactly one of three tiers, **56 + 9 + 35 = 100**:

| Tier | Count | Rule | Badge in picker |
|---|---|---|---|
| **Good accuracy** | 56 | measured ≤ 35% error | none |
| **Limited accuracy** | 9 | measured > 35% error | `~40% errors` (its own number) |
| **Untested** | 35 | no published benchmark | none — the section caption says it once |

The Untested tier carries no per-row badge: all 35 rows would repeat the same string.
Limited accuracy does, because each language's number differs and that difference is the
whole point (Bengali at 40.3 and Albanian at 55.7 are not the same choice).

35% is the boundary because above it roughly two words in five are wrong, and correcting
the transcript costs more than typing it would have. Greek lands at 10.9%, in the top
tier. All 18 of today's languages are in the top tier, so no existing preference moves.

**Limited accuracy (9):** Basque 38.9, Telugu 39.3, Maori 39.8, Nepali 40.2,
Bengali 40.3, Armenian 42.2, Belarusian 42.5, Gujarati 47.4, Albanian 55.7.

**Untested (35):** Amharic, Assamese, Bashkir, Breton, Burmese, Faroese, Georgian,
Haitian Creole, Hausa, Hawaiian, Javanese, Khmer, Lao, Latin, Lingala, Luxembourgish,
Malagasy, Malayalam, Maltese, Mongolian, Occitan, Pashto, Sanskrit, Shona, Sindhi,
Sinhala, Somali, Sundanese, Tajik, Tatar, Tibetan, Turkmen, Uzbek, Yiddish, Yoruba.

Two caveats worth keeping:

- `zh`, `yue`, `ja`, `ko`, `th` are scored as **CER**, not WER, so their numbers are not
  strictly comparable to the rest. None is near the boundary, so it does not bite.
- "Untested" is not "known-bad". Faroese, Luxembourgish and Occitan are simply absent
  from both benchmarks. The badge says exactly that — no published benchmark — rather
  than implying poor quality we have not observed.

### Top tier: the 56 (code, display name, error rate)

```
af  Afrikaans          32.4    is  Icelandic          30.4    ru  Russian             5.0
ar  Arabic              9.6    id  Indonesian          6.1    sr  Serbian            11.6
az  Azerbaijani        19.7    it  Italian             3.0    sk  Slovak              9.2
bs  Bosnian            13.0    ja  Japanese            4.9    sl  Slovenian          16.8
bg  Bulgarian          12.5    kn  Kannada            33.0    es  Spanish             2.8
yue Cantonese          10.9    kk  Kazakh             32.4    sw  Swahili            34.1
ca  Catalan             4.8    ko  Korean              3.1    sv  Swedish             7.6
zh  Chinese             7.7    lv  Latvian            16.7    ta  Tamil              18.3
hr  Croatian           10.8    lt  Lithuanian         23.7    th  Thai                5.8
cs  Czech               9.0    mk  Macedonian         14.7    tr  Turkish             6.7
da  Danish             12.0    ms  Malay               7.3    uk  Ukrainian           6.4
nl  Dutch               4.3    mr  Marathi            34.1    ur  Urdu               20.4
en  English             4.1    no  Norwegian           7.8    vi  Vietnamese          8.6
et  Estonian           18.1    nn  Norwegian Nynorsk  30.7    cy  Welsh              28.6
tl  Filipino           13.0    fa  Persian            29.4
fi  Finnish             7.7    pl  Polish              4.6
fr  French              5.3    pt  Portuguese          4.1
gl  Galician           13.1    pa  Punjabi            34.7
de  German              4.9    ro  Romanian            8.2
el  Greek              10.9
he  Hebrew             23.5
hi  Hindi              16.9
hu  Hungarian          12.9
```

## Architecture

### 1. `STTLanguages` — new, `OpenWhispererKit`

`app/Sources/OpenWhispererKit/STTLanguages.swift`:

```swift
public enum STTTier: Sendable, Equatable { case standard, limited, untested }

public struct STTLanguage: Sendable, Equatable {
    public let code: String        // Whisper code, lowercase ("el", "yue")
    public let name: String        // display name ("Greek")
    public let errorRate: Double?  // best-of-both-datasets, nil when untested
    /// Computed, never stored — one boundary constant, no chance of the two disagreeing.
    public var tier: STTTier { ... }
}

public enum STTLanguages {
    /// All 100, alphabetical by display name.
    public static let all: [STTLanguage]
    /// Today's 18 codes, in today's order — pinned as a "Common" section.
    public static let common: [String]
    /// Case-insensitive: substring on name, prefix on code.
    public static func match(_ langs: [STTLanguage], query: String) -> [STTLanguage]
}
```

`errorRate` carries the published number so the picker's badge and the tier boundary
share one source. The 35% boundary is a single constant, so revisiting it is a one-line
change rather than a re-derivation.

It lives in Kit because Kit is dependency-free and is the only target with a test runner
under Command Line Tools. Display names are hand-written from WhisperKit's
`Constants.languages`, title-cased, with its alias entries collapsed to one canonical
name each (castilian→Spanish, flemish→Dutch, mandarin→Chinese, moldavian/moldovan→
Romanian, pushto→Pashto, sinhalese→Sinhala, valencian→Catalan, letzeburgesch→
Luxembourgish, burmese/myanmar, panjabi→Punjabi, haitian→Haitian Creole). A Swift
dictionary has no stable iteration order, so deriving canonical names from
`Constants.languages` at runtime would produce an unstable list — hence the fixed table.

**Drift guard.** `SettingsData` intersects `STTLanguages.all` against
`WhisperKit.Constants.languageCodes` when building the picker list. If the pinned
WhisperKit fork ever changes its set, the UI can only shrink; it can never offer a code
the decoder would reject. The reverse — a code WhisperKit *adds* — simply will not appear
until the table is updated, which is the safe direction to fail in.

**No escape hatch needed.** An earlier draft added an "Unlisted (`xx`)" row for
hand-edited `stt_language` values outside a curated list. Shipping all 100 makes every
code WhisperKit accepts representable in the UI, so that machinery is dropped.

### 1a. Default language

Today, no `stt_language` file → `readLanguage()` returns `nil` → `DecodingOptions` sets
`detectLanguage: true` and Whisper runs a language-detection pass. Auto-detect is the
current default. This design makes **English** the default instead.

Two reasons beyond preference. Detection costs an extra decoder pass on every dictation.
And it is least reliable exactly where dictation lives — a two-word utterance carries
little evidence, so short clips are the ones that get mis-detected and come back in the
wrong script. Pinning the language removes both.

**Observed, not just reasoned:** the owner reports measurably fewer transcription errors
when English is selected explicitly than when left on Auto-detect (2026-08-01). That is
the expected consequence of the mechanism above, and it is why this is a default change
rather than a cosmetic reordering. Do not "restore" Auto-detect as the default.

**Mechanism.** A one-time migration at launch, alongside the existing
`migrateVoiceDetailToTtsStyle()`: if `stt_language` does not exist, write `en`. Explicit
rather than implicit, so Settings shows the real state instead of an invisible fallback.
`readLanguage()` keeps returning `nil` for a literal `auto`, so choosing Auto-detect still
works — it is now an explicit choice at the top of the list rather than the default.

The decision is a pure function in Kit, following the precedent `VoiceMigration` already
set, so it is unit-testable rather than buried in `ConfigManager`'s file I/O:

```swift
/// nil = leave the file alone. Returns "en" only when nothing is stored yet.
public static func defaultedLanguage(existing: String?) -> String?
```

`ConfigManager` does the reading and writing; Kit decides. A stored `auto` is a real
choice and is left untouched.

**Accepted trade.** An existing user who never opened Settings and relied on auto-detect
for a non-English language is switched to English and must set their language once. There
is no way to distinguish "deliberately left on auto" from "never looked", and absence of
the file means the latter. Changing a default affects exactly the users who never chose;
that is what a default change is.

### 2. `OWSearchablePicker` — new control, app target

Added to `SettingsControls.swift`. Generic sectioned searchable popover over
`(id: String, label: String)`, with the collapsed-control styling of `OWMenuPicker` and
the popover geometry of `OWAppPicker`. Sections carry an optional caption line and rows
an optional trailing badge, which is what the Voice tab needs.

`OWAppPicker` is left untouched — its favorites/installed/`CUSTOM` semantics do not
generalize, and refactoring it is out of scope.

`OWGroupedMenuPicker` has exactly one caller (`VoiceTab`), which this design replaces.
It is deleted rather than left dead.

### 3. Dictate tab

`DictationTab.swift:198` swaps `OWMenuPicker` for `OWSearchablePicker`:

```
Language  [ Greek                                    ⌄ ]
          ┌────────────────────────────────────────────┐
          │ [ Search languages…                      ] │
          │   Auto-detect                              │
          │     Let Whisper guess. Less reliable on    │
          │     short phrases.                         │
          │ COMMON                                     │
          │     The usual shortlist. All also appear   │
          │     under Good accuracy.                   │
          │   English                                  │
          │   Spanish                             …    │
          │ GOOD ACCURACY                              │
          │     35% word errors or fewer in OpenAI's   │
          │     large-v3 benchmarks.                   │
          │ ✓ Greek                                    │
          │   Hebrew                              …    │
          │ LIMITED ACCURACY                           │
          │     More than 35% word errors. Fine for    │
          │     short phrases; expect to correct.      │
          │   Bengali                  ~40% errors     │
          │   Albanian                 ~56% errors     │
          │ UNTESTED                                   │
          │     Whisper accepts these, but OpenAI      │
          │     published no accuracy figures.         │
          │   Faroese                                  │
          └────────────────────────────────────────────┘
```

Each section header carries a one-line caption, so a category never has to be inferred
from its name — this is the "explain the categories" requirement, and it is why
`OWSearchablePicker` takes an optional caption per section. "All languages" is renamed
**"Good accuracy"**: with all 100 present it would otherwise be the only tier whose name
described scope rather than quality, making the other three read as exceptions to it.

`COMMON` repeats 18 languages that also appear under `GOOD ACCURACY`; that duplication is
deliberate and stated in its caption, exactly as `OWAppPicker` repeats favorites above the
full app list. The `onChange` write to `Paths.sttLanguage` is unchanged; the `load()`
membership check now validates against all 100 codes.

Beyond the new default in §1a, the transcription path is untouched: `readLanguage()` →
`DecodingOptions.language` already passes any code through.

### 4. Voice tab — registry

`TTSVoiceRegistry.supertonicGroups` grows from 5 tuples to **24** — every Supertonic
language Kokoro cannot speak: ko, ar, bg, cs, da, de, el, et, fi, hr, hu, id, lt, lv, nl,
pl, ro, ru, sk, sl, sv, tr, uk, vi. Two styles each (F1/M1). Kokoro's 9 groups stay first
and untouched. 33 groups total.

The seven languages both engines cover (en, es, fr, it, pt, hi, ja) stay Kokoro-only, so
no language appears under two entries.

The doc comment above `supertonicGroups` currently records the *opposite* decision
("Curated deliberately… these five are the ones ASR-verified"). It is rewritten to record
this one and its reasoning, so the next reader does not re-narrow the list.

**No hook change.** `resolve_language_line()` already maps all 24, Greek included;
verified entry by entry. **No router change.** `supertonicLanguages` already contains
all of them. `HookTests` already guards the map.

### 5. Voice tab — explanatory picker

```
Voice  [ Greek · F1 (Female)                    ⌄ ]  [ ▶ ]
       ┌────────────────────────────────────────┐
       │ [ gre|                               ] │
       │ GREEK · SUPERTONIC · 2 VOICES          │
       │   Speaker styles, not regional accents │
       │ ✓ F1 · Female                        ● │
       │   M1 · Male                          ● │
       └────────────────────────────────────────┘
       ● downloaded   ○ downloads on first use

       Replies will be spoken in Greek. Your on-screen
       reply stays in the language of the conversation.
```

1. **Fully-qualified collapsed label** — `Greek · F1 (Female)`, not `F1 (F)`.
2. **Section headers name engine and count** — `English (US) · Kokoro · 20 voices`.
3. **Supertonic sections carry a caption** stating F1/M1 are speaker styles, not accents.
4. **Per-row downloaded/not-downloaded dot.** The probe already exists inline at
   `TTSHTTPServer.swift:140`, serving `list_voices`. It is extracted to a `VoiceCache`
   helper (app target) so Settings and the MCP tool share one definition — including the
   rule that every Supertonic voice flips to cached together, since they share one model.
5. **Live caption for non-English voices**, stating replies will be *spoken* in that
   language while the written reply follows the conversation. This surfaces
   `resolve_language_line()`, which is real behavior with no UI presence today.

The caption's language name comes from the `TTSVoiceGroup.name` the user just picked, not
from a second table — but the hook keeps its own `code → language` map, so the two can
still disagree on wording (e.g. "Portuguese" vs "Brazilian Portuguese"). `HookTests`
already depends on `OpenWhispererKit` and can read the hook, so it is the one runner that
can assert both sides agree — see Testing.

Search matches language name, voice name, and ISO code, so `greek`, `el` and `F1` all
land. While a query is active, rows show the language inline (`Greek · F1 · Female`)
because section headers stop working as anchors.

### 6. Voice preview

A play button beside the picker synthesizes a fixed sample through the existing
`TTSPlaybackController` at the user's current speed and volume.

The sample **must be in the voice's own language** — an English sample read by a Greek
voice reproduces exactly the unintelligibility Supertonic was added to fix. So a new pure
`TTSSampleText` (Kit) maps language → one short sentence, with **English as the fallback**
for any language without an entry.

A test can assert a sample exists and is non-empty; it cannot judge whether the Ukrainian
one is idiomatic. Translation quality is flagged for the review phase, along with the
section captions.

Preview reuses `bargeIn()` before starting, so a preview cannot overlap a spoken reply or
a previous preview. On an uncached voice it triggers the normal on-demand download, which
the row dot has already disclosed.

## Testing

Both runners are plain `@main` executables that aggregate `*Failures() -> [String]`
groups and `exit(1)`; there is no XCTest on this machine.

**`STTLanguageChecks.swift`** (new, registered as `sttLanguageFailures()`):
- `all` has 100 entries, codes unique and lowercase
- tier split is exactly 56 standard / 9 limited / 35 untested
- `tier` agrees with `errorRate` for every entry: `nil` → `.untested`, `≤35` →
  `.standard`, `>35` → `.limited`
- no `auto` entry in `all`
- every `common` code exists in `all` and is `.standard`
- spot-checks: `el` is `.standard` at 10.9; `sq` is `.limited` at 55.7; `ln` is
  `.untested` with `errorRate == nil`
- `match` finds Greek by `"greek"`, `"Gree"` and `"el"`; empty query returns the list
  unchanged; a code match is prefix-only, so `"el"` does not match on code alone for
  unrelated entries

**`TTSVoiceRegistryChecks.swift`** (extend):
- exactly 24 Supertonic groups
- every generated id routes to `.supertonic` with the expected language
- no language appears in two groups
- every group language ∈ `TTSVoiceRouter.supertonicLanguages`
- Greek specifically resolves: `supertonic:el:F1` → `.supertonic`, language `el`

**`TTSSampleTextChecks.swift`** (new): every Supertonic and Kokoro language resolves to a
non-empty sample; an unknown language falls back to English.

**Default-language migration** (in `STTLanguageChecks`): `defaultedLanguage(existing:)`
returns `"en"` for `nil` and for an empty/whitespace file; returns `nil` for `"auto"`,
for `"el"`, and for any other stored value — a stored choice is never overwritten.

**`HookTests`** gains one cross-target check, which only it can run — it depends on
`OpenWhispererKit` *and* can read `hooks/voice-shared.sh`: every one of the 24 Supertonic
group names in `TTSVoiceRegistry` matches the language name `resolve_language_line()`
emits for that code. This is what keeps the Voice tab's caption and the model's nudge
from drifting apart while the map stays in bash. Its existing cases are unchanged and
must still pass.

## Documentation

`AGENTS.md`:
- "Roster is a UI decision, not a bytes decision" bullet: five → 24.
- New line recording that the Dictate list is all 100 Whisper codes in three tiers split
  at 35% error, with this spec as the source, so nobody re-derives the WER data.
- `stt_language` in the "State & IPC" list: note the default is now `en` via a one-time
  migration, and that Auto-detect is an explicit choice rather than the fallback.

No README change (it is already documented as describing an obsolete architecture).
No version bump.

## Out of scope

- Merged per-language Voice groups mixing both engines.
- All ten Supertonic styles per language.
- Native-language search terms (`Ελληνικά`, `Deutsch`).
- Any per-language download UI — there is nothing to download per language on either side.
- Refactoring `OWAppPicker`.

## Risks

- **Translation quality in `TTSSampleText`** is unverifiable by test and is the most
  likely source of an embarrassing defect. Explicitly assigned to review.
- **33 nested sections** will scroll on a short display. Search mitigates it.
- **`VoiceCache` extraction touches the MCP `list_voices` path.** Behavior must stay
  byte-identical; the extraction is a move, not a rewrite.
- **The 35% boundary is a judgment call on top of measured data.** It is recorded here
  with the full table so it can be revisited by changing one constant, not by re-deriving
  the evidence. Since it now only moves a language between sections, getting it slightly
  wrong is cosmetic rather than blocking.
- **The English default changes behavior for existing users** who never opened Settings.
  Accepted, with the reasoning and the owner's observation recorded above.
- **Section captions are the main new copy surface.** Four captions plus the Voice tab's
  language note are user-visible text that no test can judge; assigned to review along
  with the sample translations.

## Review

After implementation, before merge: `swift-expert` plus one further reviewer examine the
changes independently. Opus adjudicates their findings.
