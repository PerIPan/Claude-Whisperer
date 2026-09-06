import Foundation
import Combine

/// Live "TTS is speaking" state, published in-process.
///
/// `tts_playing.lock` is still written by `TTSPlaybackController` (it is part of the
/// documented Application Support bus), but nothing outside this process reads it — not the
/// hooks, not the Pi extension, not `scripts/`. The app used to learn its own playback state
/// by polling that file back off disk from two places: the overlay every 0.3 s and
/// `DictationManager` every 0.5 s. Apple's energy guidance is explicit that polling for a
/// state change you could be told about is the wrong shape, and here the writer is an actor
/// in the same process.
///
/// Publishing directly also fixes a real gap: `DictationManager`'s poll was only started by
/// `activateHandsFree()`, so in the default hold-to-talk mode `ttsPlaying` was permanently
/// false and the Settings → Voice preview button never showed playback.
final class TTSPlaybackState: ObservableObject {
    static let shared = TTSPlaybackState()

    /// True from the moment playback of an utterance starts until the queue drains, a
    /// barge-in cancels it, or playback fails.
    @Published private(set) var isPlaying = false

    private init() {}

    /// Callable from any thread — the playback actor and `DictationManager`'s barge-in both
    /// reach this. Hops to main like `PlaybackLevelMeter.push`.
    func set(_ playing: Bool) {
        DispatchQueue.main.async {
            if self.isPlaying != playing { self.isPlaying = playing }
        }
    }
}
