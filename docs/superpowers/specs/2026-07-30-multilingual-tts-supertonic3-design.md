# Multilingual TTS via Supertonic-3 (speak languages Kokoro can't)

> **Status: implemented, shipped in 2.0.0.** Supersedes the Piper proposal in PR #32, which was
> never merged. The engine decision was settled by measurement, not preference — see
> [Engine selection](#engine-selection).

## Goal

Speak replies in languages Kokoro-82M has no voice for — **Dutch first**, plus German, Polish,
Russian and Ukrainian. Before this, a Dutch-dictated turn got a Dutch reply spoken by an *English*
Kokoro voice.

### The bug, measured

"Dutch in an English accent" undersells it. Synthesizing
*"Ik heb de wijzigingen doorgevoerd in het configuratiebestand. De tests slagen nu allemaal, dus je
kunt het gerust samenvoegen. Wil je dat ik ook de documentatie bijwerk?"* and transcribing the
result back with a multilingual ASR:

| engine | ASR read-back | WER |
|---|---|---|
| Kokoro `af_heart` | `"D test Slagin New Alemolol."` | **~100%** |
| Supertonic-3 `nl` F1 int8 | `"…De tests lagen nu allemaal…"` (one word) | **~3.7%** |

Kokoro's Dutch is not merely accented, it is **unrecoverable** — an ASR cannot get the sentence
back. That is the defect this feature fixes.

STT was never the problem: WhisperKit large-v3 turbo covers ~99 languages including Dutch.

### Non-goals (YAGNI)

- **Not** replacing Kokoro. It stays the default and keeps its nine languages — including
  **Mandarin, which Supertonic-3 was not trained on**, so the two rosters genuinely complement.
- **Not** auto-detecting reply language. The user picks a voice; language follows from it.
- **Not** all 31 Supertonic languages in the picker. See [Roster](#roster).
- **Not** changing STT.

## Engine selection

The original proposal bundled [Piper](https://github.com/rhasspy/piper): a signed arm64 binary plus
`espeak-ng-data` in `Contents/Resources`, per-language model downloads, and one subprocess per
sentence. A review pointed at **Supertonic-3**, already compiled into FluidAudio — the app's
existing speech dependency. Measured on an M-series Mac, warm cache, one short sentence:

| engine / variant | model load | inference | realtime | device |
|---|---|---|---|---|
| **Supertonic-3 int8** | 0.10 s | **0.12 s** | **19.2×** | ANE |
| Supertonic-3 int4 | 0.11 s | 0.16 s | 14.0× | ANE |
| Supertonic-3 fp16 | — | 0.67 s | 3.4× | CPU/GPU |
| Kokoro `af_heart` | 0.94 s | 1.27 s | 1.93× | ANE |

Supertonic-3 int8 is **~10× faster than the Kokoro already shipping**, and needs no bundled binary,
no code-signing surface, no subprocess (so no process-kill path for barge-in), and no new cache
location. Piper was dropped.

Two findings worth keeping so nobody re-derives them:

- **FP16 is not the quality setting.** Its RangeDim shapes cannot use the ANE, so it measured both
  slower *and* off-ANE. Quality comes from `int8` (upstream: "transparent, closest to FP16") while
  staying ANE-resident. `int8` over the upstream `int4` default is a deliberate quality call.
- **The docs' 398 MB figure counts every VectorEstimator variant.** Real footprint is ~70 MB core
  plus one variant set: **~264 MB for int8**, ~164 MB for int4. Only the selected variant downloads.

Per-language quality was ASR-verified for all five shipped languages (German, Polish and Russian
came back essentially verbatim; an initial Ukrainian miss was an ASR homophone boundary —
`Я вніс` / `Явні` — not a synthesis defect, confirmed by re-testing with different phrasing).

## Components

### 1. Router — `TTSVoiceRouter` (`OpenWhispererKit`, unit-tested)

Kokoro ids stay **bare** (`af_heart`) so every existing `tts_voice` pref keeps working with no
migration. Supertonic voices carry an explicit tag: **`supertonic:<lang>:<style>`**
(e.g. `supertonic:nl:F1`).

`route(_:)` returns `(engine, voice, language)`. It normalizes case and whitespace, clamps an
unknown style to `F1`, and falls back to the default Kokoro voice for an unsupported language —
including `supertonic:zh:*`, since Supertonic has no Mandarin. Because the language rides *inside*
the id, Settings needs **no separate language control** (a Language dropdown would allow the
invalid pair `af_heart` + Dutch) and per-project `OW_TTS_VOICE` works unchanged.

### 2. Engine — `Supertonic3TTS` actor

Mirrors `KokoroTTS` exactly: actor-isolated, in-flight load dedup, cache-first offline loading.
`Supertonic3Manager(computeUnits: .cpuAndNeuralEngine, vectorEstimator: .aneBucketed(.int8))`.
Voice styles come from `Supertonic3ResourceDownloader.loadVoiceStyle` — public in FluidAudio, so
there is **no hand-rolled download shim** (FluidAudio's own docs claim styles aren't
auto-downloaded; that known-issue note is stale relative to its code).

Note `Supertonic3Manager.synthesize` returns `(samples, **duration**)` — not a sample rate. The
rate is the fixed `Supertonic3Constants.sampleRate` (44 100).

### 3. Hub — `TTSEngines`

Exposes the same surface `KokoroTTS` did (`prepare`, `synthesize`, `synthesizeSamples`), so
`TTSPlaybackController`, `TTSHTTPServer` and `ServeTTSMode` were **type-swapped, not rewritten**;
sentence streaming, barge-in, the `speak` MCP tool and `/v1/audio/speech` are untouched.

`prepare()` warms Kokoro always, and Supertonic **only when the selected voice routes to it** — an
English-only user never downloads it.

> **Playback resampling.** The Piper proposal claimed `AudioPlaybackEngine` "already accepts a
> per-item `sampleRate`". **It does not** — it builds one fixed 24 kHz format in `init` and
> `schedule` takes no rate, so a 44.1 kHz buffer would play ~1.8× too slow. Supertonic output is
> downsampled to 24 kHz in the hub via FluidAudio's `AudioConverter`. That costs content above
> 12 kHz (inaudible for speech; Kokoro has always been 24 kHz) and avoids reconfiguring a graph
> with a documented wedging history. The WAV path keeps the native 44.1 kHz.

### 4. Roster

Five languages × two styles (F1/M1) = ten new picker entries.

The curation reasoning **inverts** from Piper: with Piper each language is a separate model
download, so a short list saved bytes. With Supertonic all 31 languages ride in the **one** model,
so adding a language costs **zero** extra download — the list is purely a UI-clutter decision.
Hence: the picker shows the five that were listened to and ASR-verified, while
`TTSVoiceRouter.supertonicLanguages` accepts all 31 (32 minus the `na` language-agnostic entry) so `OW_TTS_VOICE` can name any
of them. Extending the picker later is a registry-only edit.

Two styles rather than ten because F1–F5/M1–M5 are generic **speaker styles, not accents** —
there is one `nl`, no Flemish/Netherlands split — so eight more rows per language would add length
without adding meaningful choice. Voices are labelled by style (`F1`/`M1`) rather than given
human names, since the same style speaks every language.

### 5. Language-aware nudge — the easy-to-miss essential

A Dutch voice reading English text is pointless, so the spoken summary must be *in* the voice's
language. `hooks/voice-shared.sh` gains `resolve_language_line()`: a `<lang>` → language-name
lookup that appends one instruction to the speak nudge. Kokoro voices and `supertonic:en:*` get no
line, so English users see zero change.

The map lives **only in the hook** (no Swift parity pair), like the persona map, and `HookTests`
guards it. Its sentinel — `Write the text you pass to \`speak\` in` — is deliberately distinct from
the persona sentinel `voice speaking your reply`, so the two layers stay independently assertable.
Multilingual voices get the language line **instead of** a persona; personas are keyed to Kokoro's
first-char scheme and no national characters were invented for the new languages.

### 6. MCP surface

`validVoiceID` previously required `[a-z0-9_]` with an underscore at index 2, which **silently
dropped** `supertonic:nl:F1` back to the global voice; it now validates multilingual ids through
the router and returns their canonical spelling. `isVoiceCached` understands that multilingual
voices share one model, so all of them flip to cached together. The `speak` tool's own description
documents the new id shape, since the model reads it to choose voices.

## Testing

- **`OpenWhispererKitTests`** — router resolution (bare vs tagged, case/whitespace normalization,
  style clamping, unsupported-language fallback, `zh` explicitly excluded), `supertonicID`
  round-trip across all 31 × 10 combinations, registry integrity (per-engine counts, unique ids,
  every multilingual id routing to a real language + style).
- **`HookTests`** — seven checks: Dutch line present with the right voice arg, another language
  not hard-coded to Dutch, multilingual voice gets no persona, Kokoro gets no language line,
  `supertonic:en` gets none either, the line follows `OW_TTS_VOICE`, unknown code yields no line.
- **Manual (needs audio)** — first-use download + progress, barge-in mid-Supertonic-synthesis,
  the resampled 24 kHz playback level against Kokoro's.

## Known limitations

- **Playback loudness across engines is unverified.** Both paths return raw model samples; if
  Supertonic reads systematically louder or quieter than Kokoro, switching voices produces a volume
  step. `tts_volume` is the user-side lever. Worth measuring.
- **Best-effort reply language.** The nudge asks the model to write the summary in the target
  language; a model may drift back to English. Accepted (KISS), matching the existing
  "no Stop-hook fallback" philosophy.
- **~264 MB on first use** of a multilingual voice, subject to the known Xet-CDN/firewall caveat.
- **Supertonic's own chunker** splits at 110 characters and concatenates with 0.3 s of silence, on
  top of the app's `SentenceSplitter`. Long single sentences may show a seam.
