import Foundation
import OpenWhispererKit

/// Whether anything is currently displaying the analyzer bands.
///
/// Both audio taps — the mic input tap in `AudioRecorder` and the TTS output tap in
/// `AudioPlaybackEngine` — reduce every buffer to `SpectrumBands.bandCount` band energies
/// on a real-time render thread. Only three of the four overlay styles draw that result:
/// the default `.wave` style reads `levelHistory` instead (see `OverlayStyle
/// .usesSpectrumBands`). So on default settings the filterbank was computed and thrown
/// away on every callback, and with the overlay hidden it was computed for nobody at all.
///
/// It cost more than it looks on the playback side. `AudioPlaybackEngine` installs its tap
/// once for the engine's lifetime, and the only things that stop that engine are barge-in
/// and an `AVAudioEngineConfigurationChange` (sleep/wake, output-device switch) — a normal
/// drain does not. So after the first spoken reply it keeps running and keeps delivering
/// *silent* buffers; taps are not skipped for silence. At a 44.1 kHz mixer with 2048-frame
/// buffers that is ~21.5 callbacks/s indefinitely (the rate follows the output device's
/// sample rate), ~0.5 ms of Goertzel each — about 1% of a core, forever, plus a main-queue
/// hop per callback publishing all-zero bands nobody read.
///
/// **`TranscriptionOverlay` is the sole writer.** The gate encodes "does anyone need bands?"
/// as "is the overlay visible on a band-drawing style", so deleting or replacing the overlay
/// silently disables every analyzer style with no compiler or test failure — relevant to
/// `docs/superpowers/plans/2026-07-13-notch-status-indicator.md`, which retires
/// `TranscriptionOverlay`. A *second* simultaneous consumer (a Settings live preview, a notch
/// indicator) must turn this into a demand count rather than add a second writer.
///
/// Deliberately unsynchronized, unlike `AudioRecorder`'s `_bufferingForSTT` /
/// `silenceDetectionEnabled`, which guard the same main-writes/RT-reads shape with
/// `bufferLock` per an earlier review (C-2 / C-3). The difference is intentional: this is a
/// single-writer `Bool` read exactly once per tap invocation, so it cannot tear and cannot be
/// hoisted across callbacks, and a stale read costs one analyzed-or-skipped frame — not worth
/// taking a lock on an audio thread for. `nonisolated(unsafe)` marks the departure explicitly
/// so it fails loudly rather than silently if this target ever moves to strict concurrency.
enum SpectrumGate {
    nonisolated(unsafe) private static var _isEnabled = false

    /// Read from audio render threads.
    static var isEnabled: Bool { _isEnabled }

    /// Recompute from the overlay's live state. Call whenever visibility or style changes.
    /// Main thread only — the overlay's `isVisible`/`analyzerStyle` are main-thread state.
    static func update(visible: Bool, style: OverlayStyle) {
        dispatchPrecondition(condition: .onQueue(.main))
        let enabled = visible && style.usesSpectrumBands
        guard enabled != _isEnabled else { return }
        _isEnabled = enabled
        // Going dark: drop the last frame so re-enabling can't flash stale bands. A tap
        // callback that passed the guard microseconds earlier can still land its push after
        // this, leaving one stale frame behind a closed gate — harmless, since nothing reads
        // playback bands while the gate is off and the next enable overwrites within a frame.
        if !enabled { PlaybackLevelMeter.shared.reset() }
    }
}
