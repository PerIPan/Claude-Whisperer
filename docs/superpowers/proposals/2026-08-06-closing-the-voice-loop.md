# Closing the voice loop

**Status:** proposal — not an approved design. Nothing here is committed.
**Date:** 2026-08-06 · **Revised:** 2026-08-10 (conceptual pass, no implementation)
**Picking one up?** Jump to [If you're picking one up](#if-youre-picking-one-up).

> Docs in `specs/` are designs that were agreed and built. This directory is for
> the step before that: a case for doing something, with enough research attached
> that whoever picks it up doesn't start from zero. Expect to argue with it.

## The thesis

Wispr Flow and Quill are both **dictation**: one direction, mouth to text field.
Everything they compete on — filler removal, punctuation, tone matching, snippets
— is polish on that single arrow.

OpenWhisperer already has the other arrow. Kokoro and Supertonic-3 on the ANE, an
MCP server on `:8000`, and a `UserPromptSubmit` hook that gets the model to speak
*mid-turn* rather than after it. No competitor can copy that without building a
TTS stack, a playback queue, and a per-platform hook layer first. That asymmetry
is the moat, and right now we barely lean on it.

So the direction is not "catch up on dictation polish." It is:

**Make the round-trip the product.**

The agent should be able to *ask you something out loud and hear your answer*,
without you touching the keyboard, without the session breaking.

### Where we stand

| | Wispr Flow | Quill | OpenWhisperer |
|---|---|---|---|
| Direction | in | in | **in + out** |
| Runs locally | no (cloud, Privacy Mode = not stored) | optional | **always** |
| Agent integration | none | MCP: `start_recording`, `list_transcripts`, … | **MCP `speak` + hooks on 4 platforms** |
| Cleanup / formatting | yes, core pitch | yes, core pitch | **no** |
| Snippets | yes | no | **no** |
| Tone / per-app | yes | app context | no |

The row we win is the row nobody else is playing; the rows we lose are mostly
*polish*. Quill's MCP tools are worth noting — the agent can drive recording and
read transcripts — but it's still one direction: the agent reads what you said.
It cannot talk back.

---

## What the second pass changed

The first draft framed these as three features to build. Reading the code changed
two of them materially. Recorded here so the revisions aren't mistaken for drift.

1. **`ask_user` is not new surface area — it completes a mechanism that already
   exists.** `tts_response_mode: needed` already asks the model to detect the
   exact moment `ask_user` is for, and then gives it nowhere to go. This is the
   strongest argument in the proposal and it wasn't in the first draft. See
   [§1.1](#11-needed-mode-is-ask_user-without-a-return-path).
2. **Whisper Mode is mostly one change, not two.** The gain stage — the part
   everyone reaches for first — is probably a no-op for accuracy. The VAD swap is
   the feature. See [§3](#3-whisper-mode).
3. **MCP elicitation is architecturally unavailable to us**, not merely a poor UX
   fit. `GET /mcp` returns 405 by deliberate choice. See [§1.2](#12-why-not-mcp-elicitation).
4. **A shape emerged that none of the three fit individually** — the app has an
   implicit conversation state machine, and `ask_user` is what forces it to
   become explicit. See [The conversation state machine](#the-conversation-state-machine).

Sources are cited inline. Claims read from checked-out code are marked
**[verified]**; claims that still need a spike are marked **[unverified]**. Please
keep that distinction if you edit this.

---

## The conversation state machine

The single most useful thing this pass produced, and it isn't a feature.

The app already has a conversation model. It's just implicit, and spread across
three places that don't know about each other:

- **`DictationManager`** — `idle → recording → transcribing → typing`
- **`TTSPlaybackController`** — its own synth/playback queue
- **hands-free mode** — its own loop: calibrate, listen, detect silence, flush,
  transcribe, resume

They're coupled today by exactly one rule, and it's a negation: *starting to
listen kills the speaking* (`killTTS()` → `bargeIn()`, at
[`DictationManager.swift:812-816`][killtts]). **[verified]** That rule is why
these three can stay ignorant of each other — the interaction is never
genuinely bidirectional, so no shared state is needed.

`ask_user` breaks that. It needs speaking and listening **sequenced** rather than
mutually exclusive: speak fully, *then* listen. The moment one flow needs both
in order, the implicit model stops working and the special cases start
multiplying through `DictationManager`.

So the conceptual recommendation, ahead of any code:

> **Name the state machine before adding `ask_user` to it.** Not a refactor for
> its own sake — the feature is unimplementable cleanly without it, and the
> alternative is a scatter of `if isAnswering` branches through the manager.

Roughly what wants naming:

```
        ┌──────────────────────── idle ◄─────────────────────┐
        │                          │                         │
        │  user presses hotkey     │  ask_user arrives       │
        ▼                          ▼                         │
   dictating                   asking ──► speaking question  │
   (types into app)                          │               │
        │                                    │ playback ends │
        │                                    ▼               │
        │                              listening ────────────┤
        │                                    │  (VAD/silence)│
        ▼                                    ▼               │
   transcribe ─► type                  transcribe ─► return  │
        │                                    │  as tool result
        └────────────────────────────────────┴───────────────┘
```

Two paths, one shared transcribe step, differing in **where the text goes** —
typed into the focused app, or returned as a tool result. That framing makes the
whole feature tractable: `ask_user` is the existing pipeline with a different
sink and an inverted entry condition.

Worth stating what stays unchanged: barge-in is *not* removed. A user saying
"hold on" over a question must still work. The inversion is about **ordering
within `asking`**, not about abolishing the rule elsewhere.

[killtts]: ../../../app/Sources/OpenWhisperer/DictationManager.swift

---

## 1. `ask_user` — the spoken round-trip

**The differentiator. Largest effort. Do it last.**

### 1.1 `needed` mode is `ask_user` without a return path

This is the argument the first draft missed, and it should lead.

`tts_response_mode: needed` already exists. Its nudge, at
[`voice-shared.sh:195-201`][shared], instructs the model: **[verified]**

> First decide whether this turn ends on me: you are asking a question, you are
> blocked, you need my approval for something risky or destructive, or something
> failed and I have to choose what happens next. If so, your FIRST action must be
> to call the `speak` tool exactly once…

Read that against what `ask_user` is for. It is the same condition, word for
word. **The hard part of `ask_user` — getting the model to reliably recognize
"this turn ends on the user" — is already built, shipped, and prompt-tuned.**

And then the mechanism dead-ends. The model states what it needs, the audio
plays, the turn ends, and you go back to the keyboard to answer. `needed` mode
identifies the moment perfectly and then wastes it.

That reframes the proposal:

> `ask_user` is not a new capability. It is a **return path** for a determination
> the system already makes.

Consequences worth thinking through:

- **`needed` mode is the natural default** once `ask_user` exists. Today it's the
  least useful of the three response modes, because "speak only when I'm needed"
  produces a notification you then have to act on manually. With a return path it
  becomes the *only* mode that makes voice a genuine conversation.
- **The nudge may need almost no change** — swapping which tool it names, plus
  wording for the case where the model should ask rather than announce.
- **This is a strong argument for building it**, and equally a strong argument for
  building it *last*: it depends on the handshake, so anything that destabilizes
  the handshake destabilizes this.

[shared]: ../../../hooks/voice-shared.sh

### 1.2 Why not MCP elicitation

MCP added **elicitation** (`elicitation/create`, server→client) in the
[2025-06-18 revision][elicit]. That's the standard-shaped answer, so the reason
we're not using it needs to be on the record.

The first draft gave a UX reason: elicitation renders as a **client-side form**,
which is precisely the keyboard interruption we're removing. That still holds,
but there's a harder architectural one.

Elicitation is a **server→client request**. Under Streamable HTTP that requires
the server→client SSE stream — the `GET /mcp` channel. We deliberately don't
implement it: [`TTSHTTPServer.swift:214-216`][http] returns **405 Method Not
Allowed** with the comment *"We don't offer the optional server→client SSE
stream; say so rather than 404."* **[verified]**

So elicitation isn't a design preference we're declining. Adopting it means first
building a bidirectional MCP transport, then accepting a form-based UI that
defeats the purpose. A blocking tool call needs neither and works on every
platform we support today.

[elicit]: https://modelcontextprotocol.io/specification/draft/client/elicitation
[http]: ../../../app/Sources/OpenWhisperer/TTSHTTPServer.swift

### 1.3 The limitation nobody expects

**`ask_user` cannot voice-enable Claude Code's permission prompts.** Anyone
hearing about this feature assumes it can. It's the first example they'll reach
for, and it's out of reach.

When a tool needs approval, the *harness* intercepts the call and renders the
prompt. The model isn't in the loop and never sees it, so it cannot call a tool
in response. No MCP server can reach that prompt. **[unverified — believed true
from observed behavior; worth confirming before anyone promises it in a UI.]**

There is a workaround, and it's the good kind — it costs nothing: nudge the model
to call `ask_user` **proactively, before attempting** something destructive. That
converts a harness-level prompt into a model-level one. Weaker (it depends on the
model's judgement, and the harness will still prompt afterwards) but it's the
same trade the rest of the handshake already makes, and `needed` mode's wording
already covers "approval for something risky or destructive."

Worth writing down now so the feature isn't sold on a promise it can't keep.

### 1.4 Timeout semantics — the thing that decides whether this is usable

The failure mode that kills this feature is not a crash. It's:

> The agent asks. You don't hear it — headphones out, music playing, other room.
> It times out. **The agent picks a default and continues.**

That is strictly worse than never having asked, because now an unattended
decision is buried mid-turn. The design principle follows directly:

> **A timeout must degrade to "I don't know", never to a silent default.**

Concretely: the timeout result should be an explicit *"no answer was heard — the
user may be away"*, phrased so the model's obvious next move is to stop and
report, not to guess. Not an `isError` (that invites a retry loop) and not an
empty string (that invites "the user said nothing, so proceed").

That also settles the timeout duration. It doesn't need tuning if the failure is
safe — long enough to walk back to the desk, short enough not to hang a session.
**60 s** is a reasonable starting point, and the exact value stops being load-bearing.

Second-order: whatever we pick must sit **under** the MCP client's own tool
timeout, or the client gives up first and we're racing. Needs checking per
platform. **[unverified]**

### 1.5 Sketch

Three pieces, in dependency order. All **[verified]** against current code.

**(a) `MCPOutcome` needs a deferred case.** [`MCPServer.swift:5-12`][mcpout] has
three outcomes — `.json`, `.accepted`, `.speak` — all answered synchronously in
the `/mcp` switch at [`TTSHTTPServer.swift:200-212`][http]. `.speak` is
fire-and-forget: it plays audio *and* replies in the same breath. `ask_user` is
the first outcome that cannot reply yet.

The deferred-response pattern already exists in this file and works:
`POST /v1/audio/speech` responds from inside a `Task` long after `handle`
returned ([`TTSHTTPServer.swift:176-185`][http]). What's new is that the
deferring is driven by the pure layer.

Keep `MCPServer` pure. It should shape the JSON and say "now go ask"; it must not
learn about `AVAudioEngine`. That boundary is why the dispatch is unit-testable
under Command Line Tools at all.

**(b) `DictationManager` has no one-shot API.** The public surface is `toggle()`,
`holdToTalkDown()`, `holdToTalkUp()` — all hotkey-shaped, all `Void`, all typing
into whatever app had focus. `ask_user` needs "record one utterance, hand me the
text, type nothing."

The closest existing primitive is `activateHandsFree()`: calibrate ambient, wait
for silence, flush, transcribe, resume. Structurally the right loop, minus the
keyword detector and minus the typing. Read it before writing anything new.

**(c) It inverts the barge-in ordering.** Covered in
[the state machine section](#the-conversation-state-machine). The mechanism to
reuse: hands-free already mutes the mic while `tts_playing.lock` is present
([`DictationManager.swift:546,567`][killtts]) **[verified]** — reuse that gate
rather than inventing a second one.

[mcpout]: ../../../app/Sources/OpenWhispererKit/MCPServer.swift

### Done when

- `ask_user(question, timeout?)` appears in `tools/list` and returns the spoken
  answer as the tool result.
- The question finishes playing before the mic opens. Verify by asking a long
  question and checking the transcript doesn't contain it.
- A timeout returns "no answer heard", and the model stops rather than guessing.
- Works on Claude Code and Codex at minimum. Pi needs its own path — the
  extension talks to `/v1/audio/play`, not MCP.
- `swift run OpenWhispererKitTests` covers the new outcome's JSON shaping.
- **Not registered under `--serve-tts`** — headless has no mic and no overlay.

### Still open

- **Cancellation.** PTT hotkey pressed during an `ask_user` window — abort, or
  treat it as "let me answer now"? The second is more natural but overloads a key
  that currently means one thing.
- **Concurrency.** Two `ask_user` calls in flight is nonsense. Reject the second.
- **Does answering re-arm voice classification?** `voice_turn` is written at
  dictation and claimed at prompt-submit. An `ask_user` answer is a *tool result*,
  not a prompt, so it bypasses that path entirely. If you answered by voice you're
  plainly in a voice session, but nothing currently records it. Cosmetic until
  someone runs `needed` mode with `response = voice`, then it decides whether the
  conversation keeps speaking.
- **The keyword detector during `asking`.** In hands-free, "hold on" triggers
  barge-in. During an `ask_user` window it would be a plausible *answer*.
  Suspend detection while listening for an answer?

---

## 2. Snippets

**Cheapest thing on the list. Ship it first.** Unchanged by this pass except for
one forward-compatibility note that's cheap now and expensive later.

### Problem

Anyone using this with a coding agent says the same twenty phrases all day. "Run
the tests and fix what breaks." "Commit this with a conventional message." Wispr
Flow ships **Text snippets** and prices it as a headline feature. Quill has
nothing here.

It's the only proposal with no model, no download, no ANE contention, and no new
failure mode. It's a dictionary lookup.

### Sketch

Mirror the vocabulary feature exactly; same shape, already works.

- **`SnippetExpander`** in `OpenWhispererKit` — pure, unit-testable under CLT.
- **`Paths.sttSnippets`**, a flat file alongside `stt_vocabulary`.
- **A `SnippetsWindow`** cloned from [`VocabularyWindow.swift`][vocabwin] — a
  `TextEditor` that writes on change. Don't design a table UI; the vocabulary
  editor is a plain textarea and nobody has complained.
- **One line in the pipeline** at [`DictationManager.swift:229-232`][killtts]:

```swift
let defillered = (language == "en") ? DisfluencyFilter.apply(text) : text
let corrected  = VocabularyCorrector.apply(defillered, glossary: glossary)
let expanded   = SnippetExpander.apply(corrected, snippets: snippets)  // new
```

### The ordering principle — worth fixing now

Expansion goes **after** correction, so a trigger still fires when Whisper
misheard a word the glossary then fixed. That was in the first draft. The
generalization wasn't:

> **Deterministic expansions run last.** Nothing downstream should rewrite them.

This matters because of the cleanup pass in
[Deliberately not proposing](#deliberately-not-proposing). If an LLM cleanup
stage ever lands, it must sit **before** snippet expansion — otherwise it
paraphrases your canned text, and a snippet whose whole value is being *exact*
stops being exact. Ordering it the other way also helps matching: cleaned text has
predictable casing and punctuation, so triggers match more reliably.

Costs nothing today. Costs a pipeline rework if it's discovered later.

[vocabwin]: ../../../app/Sources/OpenWhisperer/VocabularyWindow.swift

### Done when

- A snippet defined in the editor expands in dictated text, in any app.
- `SnippetExpander` has check-group coverage in `OpenWhispererKitTests`.
- No snippets defined ⇒ provably zero behaviour change.

### Still open

- **Whole-utterance or substring?** Substring risks "ship it" firing inside "I'd
  ship it if…". Whole-utterance-only is safer and probably covers 90% of real use.
  Recommend starting there and loosening only on complaint.
- **Case and punctuation.** Whisper capitalizes and punctuates, so a literal match
  on `run the tests` misses `Run the tests.` — normalize both sides.
- **Multi-line expansions** in a line-oriented file need an escape. Probably not v1.

---

## 3. Whisper Mode

**Substantially revised. It's smaller than the first draft said, and the obvious
half of it is probably useless.**

### The premise is half wrong

The obvious pitch is "boost the gain and lower the VAD threshold so quiet speech
registers." That fixes *capture*. It does not fix *accuracy*.

Whispered speech isn't quiet normal speech. It has **no voiced excitation** — no
fundamental frequency, no harmonic structure — so its spectral envelope is
genuinely different, not just lower-amplitude. Measured on Whisper:

| | CER | WER |
|---|---|---|
| Normal speech | ~3.95% | — |
| Whispered speech | 4.24% – 18.93% | **18.8%** |

Source: [*Leveraging Self-Supervised Models for Automatic Whispered Speech
Recognition*][whisperpaper] (arXiv 2407.21211). Roughly **4–5× degradation**, and
the fix in the literature is fine-tuning on whispered corpora (wTIMIT, CHAINS) —
out of scope.

### The gain stage is probably a no-op — settle this before building it

Sharper version of the same point, and it removes work.

Whisper's front end converts audio to a log-mel spectrogram and **normalizes it**
— the standard implementation clamps against the spectrogram's own maximum, so a
constant multiplier on the waveform largely cancels before the encoder ever sees
it. If that holds, **software gain cannot improve transcription accuracy.** It
only moves the number the *RMS gate* compares against — and the VAD swap below
replaces that gate anyway.

The underlying problem is **SNR**, and gain multiplies signal and noise
identically. It cannot help.

This is **[unverified]** here and shouldn't be asserted without a measurement:
WhisperKit computes the mel in a compiled CoreML model (`MelSpectrogram.mlmodelc`,
loaded at `WhisperKit.swift:372` in the checkout), not in readable Swift, so it
can't be confirmed by reading source. **[verified: the mel is a compiled model.]**

The experiment is cheap and worth doing **before writing any gain code**:

> Take one quiet recording. Run it through `SpeechTranscriber` at 1× and at 4×
> software gain. Diff the transcripts. If they match, delete the gain stage from
> the proposal.

If they match, Whisper Mode collapses into "use a real VAD" — no gain stage, and
plausibly no user-facing toggle at all.

[whisperpaper]: https://arxiv.org/abs/2407.21211

### The VAD swap is the real feature — and it's better-supported than expected

[`AudioRecorder.swift:317-341`][rec] gates on bare RMS against an ambient
multiplier: **[verified]**

```swift
let threshold = ambientNoiseFloor * speechThresholdMultiplier
let nowSilent = safeRawRMS < threshold
```

Exactly what fails on whispers — low-amplitude, noise-like speech reads as
silence. Lowering the multiplier just trades that for false triggers on room noise.

FluidAudio — **already a dependency** — ships `VadManager`, a public actor
wrapping Silero VAD as CoreML. Reading the checked-out source turned up more than
the first draft claimed: **[verified]**

- **`VadManager.sampleRate = 16000`** — exactly our pipeline. That open question
  is closed; no resampling.
- **A streaming API** (`makeStreamState()` / `processStreamingChunk`), which is
  the shape `AudioRecorder` needs.
- **`VadSegmentationConfig`** exposes `minSpeechDuration`, `minSilenceDuration`,
  `speechPadding`, and `negativeThreshold` — **hysteresis**, i.e. separate
  on/off thresholds.

That last group matters more than the model does. The two real complaints about
hands-free today are *"it cut me off mid-sentence"* and *"it clipped my first
word."* Those are `minSilenceDuration` and `speechPadding` — named, tunable
parameters, not things anyone has to invent. A single RMS threshold structurally
cannot express either: one number can't be both a speech-onset and a
speech-offset criterion.

Worth noting WhisperKit ships its own `EnergyVAD` (`energyThreshold: Float = 0.02`)
**[verified]** — same energy-based weakness as ours. Not an upgrade. FluidAudio's
is the learned one.

### Scope, honestly

- **In scope:** the mic reliably *captures* quiet speech — no clipped first
  syllable, no dropped utterance because RMS never crossed the gate.
- **Out of scope:** whispered accuracy matching normal speech. It won't.

Still worth building. "It hears me at all" is the complaint. And it makes the
existing accuracy levers — `stt_vocabulary`, `VocabularyPrompt` — matter *more*,
because there's more error for them to absorb.

[rec]: ../../../app/Sources/OpenWhisperer/AudioRecorder.swift

### Done when

- Quiet/whispered speech triggers and completes an utterance in hands-free mode
  without cutting off mid-sentence.
- Normal-volume dictation is measurably unchanged.
- The overlay waveform still animates (RMS-derived meters and `SpectrumBands`
  read pre-gain — check this if a gain stage survives the experiment).
- The UI **does not** promise accuracy parity. Cite the number if it says anything.

### Still open

- **Is it a mode at all?** If VAD alone fixes capture and gain is a no-op, a
  user-facing toggle may be unnecessary. One fewer setting is a win. Measure first.
- **Model download.** VAD adds a first-run fetch to `~/.cache/fluidaudio`, same as
  Kokoro. Small, but the HuggingFace Xet CDN issue in `AGENTS.md` applies.
- **ANE contention.** VAD is CoreML on the ANE, alongside Whisper and Kokoro. The
  flows are sequential today (VAD while listening, Whisper after), so this should
  be fine — but `ask_user` adds a fourth consumer to the same chain. Watch it if
  both land. **[unverified]**

---

## If you're picking one up

Recommended order — **cheapest and most independent first**:

| # | Feature | Effort | Risk | New deps |
|---|---|---|---|---|
| 2 | Snippets | small | very low | none |
| 3 | Whisper Mode | small–medium | low | none (FluidAudio has VAD) |
| 1 | `ask_user` | large | medium | none |

They're independent — take any one without the others. But `ask_user` touches the
MCP layer, the HTTP layer, `DictationManager`, and the barge-in invariant at once,
so it's a poor first contribution to this codebase.

**Two things you can do without buying into any of this:**

1. **Replace the RMS silence gate with `VadManager`.** Improves hands-free today,
   for everyone, independent of Whisper Mode.
2. **Run the gain experiment** in [§3](#the-gain-stage-is-probably-a-no-op--settle-this-before-building-it).
   An afternoon, and it either removes a chunk of proposed work or overturns the
   reasoning here. Either outcome is worth having.

Read `AGENTS.md` first — worktree layout, the two test runners, why there's no
XCTest, and the Conventions section on code signing (ad-hoc builds drop your
Accessibility grant every rebuild, which will otherwise waste an afternoon).

## Deliberately not proposing

Considered and left out, so nobody re-derives why:

- **Local cleanup pass** (filler removal, punctuation, casing, list formatting).
  Honestly **the biggest gap** — the entire pitch of both competitors, and
  `DisfluencyFilter` is a stub next to it. Excluded because it's a *different
  bet*: it needs an LLM in-process (Apple Foundation Models on macOS 26+, or a
  bundled small MLX model for 14+), which means a model-size decision, a latency
  budget, and a quality bar. Deserves its own proposal. **Someone should write
  that** — and see the [ordering principle](#the-ordering-principle--worth-fixing-now)
  before wiring it into the pipeline.
- **Per-app profiles** — depends on cleanup existing first.
- **Voice edit on selection** — same, plus a text-selection capture path.
- **Parakeet as an engine option** — settled. The owner reversed the Parakeet
  migration on 2026-07-30 with measurements in hand. See `AGENTS.md`; do not reopen.
- **System-audio capture** — a real feature (Quill has it, it opens meeting
  notes), but it's an input-source change, orthogonal to the round-trip.
- **Local stats** — retention telemetry for a product with no retention problem yet.

## Sources

- [MCP — Elicitation](https://modelcontextprotocol.io/specification/draft/client/elicitation)
- [Leveraging Self-Supervised Models for Automatic Whispered Speech Recognition (arXiv 2407.21211)](https://arxiv.org/abs/2407.21211)
- [FluidInference/silero-vad-coreml](https://huggingface.co/FluidInference/silero-vad-coreml)
- [snakers4/silero-vad](https://github.com/snakers4/silero-vad)
- [Wispr Flow](https://wisprflow.ai/)
- [Quill](https://github.com/woosublee/quill)

Code claims marked **[verified]** were read from this repo or from
`app/.build/checkouts/` at revision `a8dd37e`.
