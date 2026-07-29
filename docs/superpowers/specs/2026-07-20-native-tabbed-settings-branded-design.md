# Branded tabbed Settings window (custom tab bar) — design

**Date:** 2026-07-20
**Status:** Approved by user (design gate passed). Supersedes both the 1.10.0 native
Settings window ([`2026-07-08-native-settings-window-design.md`](2026-07-08-native-settings-window-design.md))
and the 1.10.1 branded pop-over ([`2026-07-19-restore-branded-popover-design.md`](2026-07-19-restore-branded-popover-design.md)).

## Goal

Replace the branded menubar **pop-over** with a **tabbed Settings window** that keeps the
app's warm cream/gold identity. The 1.10.0 native window was reverted because its **system
chrome felt "blunt" / identity-less**; the 1.10.1 pop-over restored identity but is one long
scroll. This design keeps the tabs *and* the identity by building a **fully custom, branded
window** — no system Settings scene, no un-themable gray.

### Why custom (not the native `Settings` scene)

A SwiftUI `Settings`-scene `TabView` renders its **toolbar-tab strip as a system AppKit
control** with **no public API to recolor it** — on macOS 14, 15, or 26. So the top strip
would stay system-gray (a two-tone seam), which is exactly the "blunt" bit the user rejected.
macOS 26 (Liquid Glass) does not change this, and targeting 26 would raise our floor from
macOS 14 and drop 14/15 users. Recoloring the native strip would require private-API
swizzling (fragile, App-Store-hostile) — explicitly rejected. The clean, supported way to a
fully cream window is our **own tab bar in a normal window**.

## Decisions (locked)

- **Fully replace** the pop-over (`MenuBarView`) — no dual mode.
- **Custom branded tab bar** in a standalone window — not the `Settings` scene.
- Background is **`OWColor.page`** (the same cream as the Wave overlay); branded `OW*`
  controls, Fraunces headers, gold accents throughout.
- **Overlay is untouched** (Wave/grip/cream all as shipped in 1.10.1).
- **macOS 14+** stays the floor. No OS bump.
- Window is **fixed-width (~520 pt), height per tab** (not user-resizable).
- Menubar keeps a **"Show Overlay"** item even though the Overlay picker also lives in Dictation.
- Tabs, in order: **General · Dictation · Voice · Agents · Advanced** (no reorder/rename).

## Architecture

- **Menubar:** `MenuBarExtra` drops `.menuBarExtraStyle(.window)` and becomes a plain **menu**
  dropdown: *Settings…* (⌘,), *Show Overlay* toggle, *Quit* (⌘Q). The always-visible status
  glyph (hourglass/speaker/waveform) stays as the menubar icon.
- **Window:** one reusable `SettingsWindow` — a standalone `NSWindow` hosting an
  `NSHostingView(SettingsView())`, following the proven `VocabularyWindow`/`InstructionWindow`
  pattern (sidesteps the `LSUIElement` Settings-scene presentation quirks the feasibility spike
  documented). Cream `window.backgroundColor` via `OWWindowBackground`; re-fronts if already
  open; ⌘, from the menubar opens/fronts it; auto-opens on first run / while setup incomplete.
- **Tab bar:** `OWTabBar` — a cream horizontal row of 5 SF-Symbol+label buttons with a **gold
  selected state**, driving `@State selectedTab`. Fully our chrome (no system strip). Needs
  deliberate accessibility (labels + `.accessibilityAddTraits(.isButton)`/selected trait +
  arrow-key selection) — the one thing native tabs would give free.
- **Body:** the selected tab's view, each a `VStack` of branded `OWCard`s on cream, fixed
  width, intrinsic height; the window resizes to the active tab.

## Tab map

### General — `gearshape`
Setup banner (conditional: `SetupManager.inProgress` progress / `.failed` + Retry) · model-loading
banner (conditional; STT-failed → Retry + Copy Diagnostics) · **Startup**: Launch at Login ·
**Permissions** (canonical): Accessibility, Microphone, Speech Recognition (Hands-Free only),
each grant-status + open-Settings · version footer. Auto-selected when a required grant is
missing or setup is incomplete.

### Dictation — `mic`
**How you talk:** Mode picker + footnote · PTT hotkey (Hold/Press) *or* silence-threshold
(Hands-Free) · live state row (Standby/Recording/Transcribing) · inline mic-grant button when
missing · Hands-Free Speech-Recognition-missing note · **Overlay** picker (one control:
OFF/Wave/LED Bars/Graph/Curtain) · hotkey-changed / error notices.
**Language & vocabulary:** Language picker · Custom vocabulary → **Edit…** opens the existing
`VocabularyWindow` pop-up (do not regress to inline `TextEditor`).
**App Focus:** Focus-target toggle · app picker (favorites/installed/custom) · custom-name
field · Return-to-previous toggle · "Press Enter after inserting" toggle · behavior footnote.

### Voice — `speaker.wave.2`
**Sound:** Voice picker (grouped by language) · Speed slider (0.7–1.5) · Volume slider (0.3–2.0).
**Response:** Reply detail (Terse/Normal/Rich — **reconcile `styleLevels`: drop the stray
"full"**) · Speak replies (when Voice / Always) + footnote.

### Agents — `wand.and.stars`
Platform picker (Claude Code / Codex / Pi / Antigravity) · Auto-Apply hook button + Applied
state + per-platform help · transient apply-feedback · "How it works…" sheet (per-platform
explainer + manual snippet).

### Advanced — `wrench.and.screwdriver`
**Models:** Parakeet STT status · Kokoro TTS status · Delete Downloaded Models… (`NSAlert`
confirm). **Server:** Start/Stop · Port (editable only when stopped) · "Server reachable".
**Diagnostics:** Server Log · Events Log · Copy Diagnostics.

## Permissions surfacing (3 layers)

1. **Menubar icon** — a subtle badge/tint on the existing glyph when a required grant is
   missing (the only signal with the window closed).
2. **General → Permissions** — the canonical, always-complete grant list.
3. **Dictation (inline)** — the specific missing grant mirrored next to the control it blocks
   (mic-grant button in place of the state row; Hands-Free note under the silence picker).

Deliberate duplication (1 canonical + 1 contextual), not an oversight. On open, if a required
grant is missing or setup is incomplete, select **General**.

## Code structure

New `app/Sources/OpenWhisperer/Settings/`:
- `SettingsWindow.swift` — `NSWindow` host (VocabularyWindow pattern); open/front/auto-open.
- `SettingsView.swift` — `OWTabBar` + selected-tab body; injects the four `@EnvironmentObject`
  managers (`ServerManager`, `SetupManager`, `DictationManager`, `AccessibilityManager`).
- `OWTabBar.swift` — the branded tab bar control (+ its accessibility).
- `GeneralTab.swift`, `DictationTab.swift`, `VoiceTab.swift`, `AgentsTab.swift`,
  `AdvancedTab.swift` — one per tab.
- `SettingsControls.swift` — the shared branded controls **extracted from `MenuBarView.swift`**
  (`OWCard`, `OWCollapsibleCard`→likely unused now, `OWMenuPicker`, `OWGroupedMenuPicker`,
  `OWAppPicker`, `OWCheckbox`, `OWInfoTip`, `OWPickerRow`, `OWInternalDivider`, button styles,
  `ModernStatusRow`, `ModernDiagnosticRow`, `PortField`). `OWColor`/`OWFont`/`OWWindowBackground`
  stay in `Theme.swift`.

**State ownership:** keep the current per-tab inline `@State` + `.onAppear` load / `.onChange`
flat-file save (no new view-model layer — simplest, matches today). The shared managers already
carry cross-tab live state (permission status, recording state, server status) as
`@EnvironmentObject`s, so no duplication risk there.

**Migration (incremental, not big-bang):**
1. Extract shared controls to `SettingsControls.swift` (pure move; pop-over still builds).
2. Build `SettingsWindow` + `SettingsView` + `OWTabBar` + the 5 tabs, porting each card's
   controls + load/save verbatim from `MenuBarView`.
3. Flip `OpenWhispererApp` to the menu-style `MenuBarExtra` + open `SettingsWindow`.
4. **Delete `MenuBarView.swift`** and the dead `Paths.*CardExpanded` flags.

## Testing

- **Pure logic** (`OpenWhispererKitTests`, CLT-safe): none new required; if `OWTabBar`
  selection or any pref parsing gains pure logic, add checks there.
- **Build**: `swift build` + `OpenWhispererKitTests` + `HookTests` green.
- **Manual (user-run — GUI unverifiable on the CLT box):** every setting reads/writes the same
  flat file as before (persistence parity); tab switch resizes the window; first-run opens to
  General with the setup banner; missing-permission badge + inline mirror; ⌘, opens/fronts;
  cream everywhere, **no gray strip**; overlay unchanged.
- Swift-expert review pass on the finished diff (as done for the overlay grip).

## Non-goals / cleanup

- Overlay untouched. macOS 14+ unchanged. No native `Settings` scene.
- Reconcile `styleLevels` to 3 (drop "full") as part of the Voice tab.
- The pop-over's collapsible-card expand prefs (`setupCardExpanded`,
  `voiceSettingsCardExpanded`, `serverCardExpanded`) become dead → delete.

## Success criteria

Clicking the menubar → *Settings…* opens a **fully cream/gold** window with a **branded tab
bar** (no system-gray strip anywhere), five well-homed tabs, every 1.10.1 setting reachable and
persisting identically, and the overlay untouched. It reads as *the app*, not as System Settings.
