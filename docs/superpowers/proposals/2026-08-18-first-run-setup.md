# First run: one sheet, honestly

**Status:** proposal — not an approved design. No implementation.
**Date:** 2026-08-18
**Scope:** the first thing a new user sees. Nothing about STT/TTS internals.

> Companion to the voice-loop proposal (`2026-08-06-closing-the-voice-loop.md`,
> PR #37 — lands in this directory when that merges). That one argues where the
> product should go; this one argues that nobody gets far enough in to find out.

## The thesis

**There is no first-run experience.** Not a thin one — none. `SetupManager` is 56
lines that write a marker file and return: **[verified]**

```swift
/// First-launch setup: nothing to install (models load on demand), so just persist the
/// completion marker and report success.
```

That comment was true when it was written — the Python `uv`/venv/pip bootstrap
it replaced really did go away in the Phase-2b port. But "nothing to *install*"
quietly became "nothing to *explain*", and those aren't the same claim. A new
user still has to make about six decisions before the app does what it says on
the tin, and right now they make all of them by wandering through a settings
window.

What actually happens on first launch, in order ([`AppDelegate.swift:68-88`][app]) **[verified]**:

1. `prepareSTT()` starts a ~1.5 GB download in the background.
2. After **0.5 s**, the Settings window opens on the General tab.
3. `runFirstLaunchSetup` writes the marker. Instantly.
4. After **1 s** more, an `InstructionWindow` pops *over* Settings containing raw
   JSON and a `claude mcp add` command line.

So within a second and a half of a first launch you are looking at a settings
window with five tabs and a modal full of config snippets, while 1.5 GB downloads
behind it. The code comment is candid about why:

> First run: the menubar is only a small dropdown now, so nothing would surface
> the setup/model progress on its own. Open Settings on General (which hosts
> those banners) so the user sees what's happening.

That's a workaround for a missing screen, and it's doing a job it wasn't designed
for. Settings is a place you return to in order to change one thing. It is a bad
first screen for the same reason a car's manual is a bad windshield.

The ask is a first-run sheet that covers three things, simply and transparently:
**(1)** pick the Dictate / Voice / Persona parameters, **(2)** offer to install
the agent hooks + MCP, **(3)** report honestly on setup and downloads. Everything
below is in service of those three.

---

## Four gaps, all verified

Reading the code turned up four specific things wrong with first run. Each maps
onto part of the ask.

### 1. The settings surface is the onboarding surface

Settings is **1,697 lines across five tabs** — General, Dictation, Voice, Agents,
Advanced. **[verified]** To get from launch to working voice you must visit at
least three of them, in an order nothing communicates:

| Tab | What a new user must do there |
|---|---|
| General | Grant Accessibility **and** Microphone |
| Dictation | Language, hotkey, interaction mode |
| Voice | Voice, speed, style |
| Agents | Platform, then Auto-Apply |

None of that is discoverable. `preferredTab(for:)` **[verified]** picks General
only when a permission is missing, otherwise Dictation — a reasonable rule for
the *second* launch, and no substitute for a path on the first.

### 2. Persona is applied but never disclosed — the transparency gap

This one is the reason "transparently" belongs in the ask.

Choosing a voice silently attaches a **national-character persona** to every
spoken reply. Pick a French voice and the model is told to be *dry and faintly
unimpressed*; pick Hindi and it's *irrepressibly helpful*; American English gets
*light SV hype*. It's ungated — every turn, for that voice.

Grep count for "persona": **15 in `hooks/voice-shared.sh`, 0 anywhere in the
Settings UI.** **[verified]**

So a behaviour that shapes the tone of every spoken reply is derived from the
first character of a voice id, lives only in a bash file, and is never mentioned
to the person it's being done to. Nobody chose this — it's an artifact of the
persona map having always lived in the hook. But the effect is a personality
applied to a user's tools without disclosure, and first run is the honest place
to fix it.

To be clear about the fix: **surface it, don't remove it.** The personas are a
deliberate, playful touch and `AGENTS.md` is explicit that they should stay
subdued and not be re-litigated. The proposal is one line of copy and a way to
turn it off — not a redesign.

### 3. First-run instructions fire for a platform the user hasn't chosen

`ConfigManager.showHookInstructions(for: Platform.load())` runs 1 s after launch,
and `Platform.load()` **defaults to `.claudeCode`** when nothing is stored
([`ConfigManager.swift:22-27`][cfg]). **[verified]**

On first run nothing *is* stored. So every new user — Codex, Pi, Antigravity
alike — gets a modal of **Claude Code** JSON and a `claude mcp add` command, for
a tool they may not use, before being asked which agent they run.

Worse for Codex specifically. `AGENTS.md:116` says: **[verified]**

> Codex silently skips *untrusted* hooks, so a first-run user must approve
> trusting the OpenWhisperer hook once (**the setup window says so**).

There is no setup window. The file that would have said so doesn't exist — the
grep for setup/onboarding/welcome UI returns `SetupManager.swift` and nothing
else. **[verified]** A first-run Codex user gets silent dictated turns, no
explanation in the app, and a documented promise that the explanation exists.

Detection is cheap, and the app doesn't attempt it. Which agents are installed is
readable from paths `Paths.swift` already knows: `~/.claude.json`,
`~/.codex/config.toml`, `~/.pi/agent/extensions/`, `~/.gemini/config/`. Note
`InstalledApps` can't help here — it scans `/Applications` for GUI bundles, and
these are all CLI tools. **[verified]**

### 4. Download feedback is good for STT and absent for TTS

The asymmetry is stark, and both halves are verified.

**STT is genuinely well done.** `SpeechTranscriber.setDownloadProgressHandler` is
wired through `DictationManager` to real percentages, with copy that sets
expectations properly:

> `"Downloading the speech model… 42% of ~1.5 GB (one-time)."`
> `"Download done — compiling for the Neural Engine…"`

That second string matters — the ANE compile is a long silent pause that would
otherwise read as a hang.

**TTS has nothing.** Grep for `progress` / `fractionCompleted` across
`KokoroTTS.swift`, `Supertonic3TTS.swift`, `TTSEngines.swift`, `VoiceCache.swift`
returns **zero matches**. **[verified]** So:

- Selecting a Dutch voice fetches **Supertonic-3 (~264 MB)** on demand — silently.
- Selecting any non-default Kokoro voice fetches a voice pack — silently.

From the user's side the app is simply broken for a while, then isn't. And the
`setupManager.progress` bar bound in `GeneralTab` **[verified]** can never help:
`SetupManager` jumps 0 → 1.0 in the same function call, so that `ProgressView`
renders progress for work that doesn't happen while the real 1.5 GB download goes
unrepresented by it.

[app]: ../../../app/Sources/OpenWhisperer/AppDelegate.swift
[cfg]: ../../../app/Sources/OpenWhisperer/ConfigManager.swift

---

## Proposed shape: one sheet, four panes, skippable throughout

A single window on first launch, replacing the Settings-plus-modal ambush. Not a
wizard that gates the app — every pane has a working default and a way past it.

```
┌─────────────────────────────────────────────────┐
│  ● ○ ○ ○                              Skip all  │
│                                                 │
│   1  Permissions   Mic + Accessibility, why     │
│   2  Dictate       language · hotkey · mode     │
│   3  Voice         voice · persona · style      │
│   4  Agent         detected agent → Apply       │
│                                                 │
│  Downloading speech model… 42% of ~1.5 GB       │
│  ───────────────────────────────────────        │
│                            [ Back ]  [ Next ]   │
└─────────────────────────────────────────────────┘
```

Two structural decisions worth stating up front.

**Download status lives in the chrome, not in a pane.** The 1.5 GB fetch starts
at launch and outlives every pane, so it belongs in a persistent strip along the
bottom — visible from pane 1 through 4, and after the sheet closes. That is the
whole of ask (3), and it's mostly plumbing that already exists.

**Nothing here blocks.** The model downloads while you pick a voice. If someone
hits "Skip all" on pane 1 they land exactly where they land today, which is the
current experience and therefore not a regression.

### Pane 1 — Permissions

The only pane that genuinely gates anything: without Accessibility and Microphone
the app cannot work at all. Two buttons, live status, and one line each on *why*
this app wants them — dictation types into the focused app via Accessibility, and
the clipboard is deliberately never touched. That last fact is a trust asset and
it currently appears nowhere a user will read.

### Pane 2 — Dictate

Language, hotkey, interaction mode. All three already exist in `DictationTab`;
this pane should reuse those controls rather than reimplement them.

One judgement call to make explicitly: the roster is **100 languages in three
tiers** and the default is English. A first-run pane should show the default and
a way to change it — not the full tiered roster. The tiers are a Settings-grade
detail and putting them here trades away the simplicity the ask calls for.

### Pane 3 — Voice **and persona**

The pane that fixes gap 2, and the one that most needs writing carefully.

Voice picker, speed, style — plus, when the selected voice carries a persona, one
plain line saying so:

> **Persona.** Your voice's character carries into spoken replies — the French
> voice is dry and faintly unimpressed. Personality only; it never changes what
> gets done. `[ ✓ Use persona ]`

Three things about that:

- **A preview button matters more than the copy.** `TTSSampleText` already exists
  for exactly this. Hearing it is faster and more honest than reading about it.
- **The opt-out is the point.** Disclosure without a switch is just a notice.
  Needs a new pref (`tts_persona`) that `resolve_flavor()` in the hook checks —
  small, but it *is* new surface area in the hook, and `HookTests` guards that
  file.
- **Say nothing when there's nothing to say.** Multilingual Supertonic voices get
  the reply-language line *instead of* a persona, so the pane should stay quiet
  for those rather than explain a thing that isn't happening.

### Pane 4 — Agent

Fixes gap 3. Detect which agents are actually installed by probing the config
paths above, then show what will be changed, then offer to do it:

> Found **Codex CLI**. OpenWhisperer will add a `UserPromptSubmit` hook to
> `~/.codex/config.toml` and register the `speak` tool.
> `[ Apply ]` `[ Show me the config instead ]`
>
> ⚠️ Codex skips untrusted hooks — you'll need to approve it once, in Codex.

Notes:

- **Keep `InstructionWindow`, demote it.** The manual JSON should stay reachable
  behind "Show me the config instead" — some people want it, and it's the honest
  fallback when Apply fails. It just shouldn't be the *first* thing.
- **The Codex warning has to be here.** It's the only place the promise in
  `AGENTS.md:116` can be kept.
- **Detecting nothing is a real case.** Say so plainly and point at the docs
  rather than defaulting to Claude Code, which is what produces gap 3 today.

---

## What this must not become

The ask says *simply*, and onboarding flows rot in a predictable direction.

- **Not a settings clone.** Four panes. If a fifth is tempting, it belongs in
  Settings.
- **Not a gate.** Skippable throughout; re-openable from the menubar afterwards.
- **Not a tour.** No feature carousel, no "did you know". Set the six things that
  must be set, then leave.
- **Not a second source of truth.** Panes 2–4 write the same flat files Settings
  writes. No parallel state, no "onboarding values" that diverge later.

## Done when

- First launch opens the sheet — not Settings, and not an `InstructionWindow`.
- The sheet writes the same prefs as Settings; setting something there and
  reopening Settings shows it.
- Download status is visible from launch until the model is ready, and covers
  **TTS as well as STT** — including on-demand Supertonic and voice-pack fetches.
- A user who picks a personified voice is told the persona exists and can turn it
  off.
- A Codex user is told about hook trust, in the app, on first run.
- Skipping every pane leaves the app exactly as it is today.
- `swift run OpenWhispererKitTests` and `swift run HookTests` pass; the latter
  matters if `tts_persona` touches `resolve_flavor()`.
- `AGENTS.md:116` becomes true, or gets corrected.

## Open questions

- **Does "Skip all" mean skip-forever or ask-again?** Ask-again is friendlier and
  risks being a nag. Leaning skip-forever plus a menubar item, since the marker
  file already exists.
- **Where does TTS progress come from?** STT got percentages because WhisperKit
  exposes a `progressCallback`. Whether FluidAudio surfaces anything equivalent
  for Supertonic and voice packs is **[unverified]** and worth ten minutes before
  anyone promises a percentage bar — an indeterminate spinner with honest copy
  ("Fetching the Dutch voice, ~264 MB, one-time") beats a fake percentage.
- **Does the persona opt-out need a Settings home too?** Almost certainly yes,
  which makes it a Voice-tab change plus a hook change, not purely first-run.
- **Should pane 4 offer multiple agents at once?** The platform pref is single-
  valued (`selected_platform`), so multi-select would be a data-model change.
  Recommend: detect and list, apply one, mention the rest are switchable later.
- **Re-runnable after an update?** `resetAndRerun` exists. A new agent integration
  is exactly the case where you'd want to re-offer pane 4 — but silently
  re-opening onboarding after an update is obnoxious. Probably a menubar item.

## Sources

All claims marked **[verified]** were read from this repo at `4e7c0da`:
`SetupManager.swift`, `AppDelegate.swift:68-88`, `ConfigManager.swift:22-27,388-395`,
`Settings/` (1,697 lines), `Settings/SettingsWindow.swift:67-71`,
`Settings/GeneralTab.swift:215-265`, `DictationManager.swift:180-195`,
`SpeechTranscriber.swift:80-144`, `InstalledApps.swift`, `hooks/voice-shared.sh`,
`AGENTS.md:116`.
