import Foundation
import AppKit
import OpenWhispererKit

/// Orchestrates in-process TTS playback: splits text into sentences, synthesizes each via
/// `KokoroTTS`, and schedules them onto a gapless `AudioPlaybackEngine` so the first sentence plays
/// while later ones synthesize. Owns the `tts_playing.lock` file and publishes the same
/// "Speaking…" state in-process via `TTSPlaybackState` (overlay waveform + hands-free
/// mic-muting subscribe to it). Barge-in cancels pending synthesis — freeing
/// the ANE for STT — and stops audio instantly.
actor TTSPlaybackController {
    private let tts: TTSEngines
    private let engine = AudioPlaybackEngine()
    private var playTask: Task<Void, Never>?

    private struct QueueItem {
        let text: String
        let voice: String
        let speed: Float
        let parentGeneration: Int
    }

    private var playQueue: [QueueItem] = []
    private var currentItem: QueueItem?
    private var drainWatchdog: Task<Void, Never>?

    /// Slack added to the scheduled audio's own duration before the drain watchdog gives up.
    /// Generous on purpose: firing early would cut off a reply, and the failure it catches
    /// is permanent, so being late costs nothing.
    private static let drainGrace: TimeInterval = 10

    /// Bumped on barge-in to invalidate the entire queue and any active playback.
    private var generation = 0
    /// Bumped on starting any item to identify the currently active item's task/callbacks.
    private var activeItemGen = 0
    private var synthDone = false

    init(tts: TTSEngines) {
        self.tts = tts
    }

    /// Longest single utterance accepted. The 1 MB request cap already lets one call queue
    /// hours of speech; spoken summaries are a paragraph at most.
    private static let maxTextLength = 8_000
    /// Queue depth cap. A caller looping `/v1/audio/play` would otherwise grow this without
    /// bound. Barge-in clears it, so this only bounds the damage between barge-ins.
    private static let maxQueueDepth = 32

    /// Speak `text`, queueing it for sequential playback.
    func play(text: String, voice: String, speed: Float) {
        guard !text.isEmpty, playQueue.count < Self.maxQueueDepth else { return }
        let clipped = text.count > Self.maxTextLength
            ? String(text.prefix(Self.maxTextLength)) : text
        let item = QueueItem(text: clipped, voice: voice, speed: speed, parentGeneration: generation)
        playQueue.append(item)
        if currentItem == nil {
            startNext()
        }
    }

    /// Barge in and speak `text` — one actor hop, so it cannot interleave with another caller.
    ///
    /// `await bargeIn()` followed by `await play()` is two separate entries: a second preview
    /// can land its `bargeIn()` between the first's two calls, which re-stamps the first item
    /// with the *bumped* generation so it passes the staleness guard and plays anyway, and the
    /// second then queues behind it. Both previews play in sequence instead of the second
    /// replacing the first. Callers that mean "replace whatever is playing" must use this.
    func replaceNow(text: String, voice: String, speed: Float) {
        bargeIn()
        play(text: text, voice: voice, speed: speed)
    }

    private func startNext() {
        guard !playQueue.isEmpty else {
            removeLock()
            return
        }
        let item = playQueue.removeFirst()
        startItem(item)
    }

    private func startItem(_ item: QueueItem) {
        guard item.parentGeneration == generation else { return }
        activeItemGen += 1
        let itemGen = activeItemGen
        let parentGen = item.parentGeneration

        currentItem = item
        synthDone = false

        let sentences = SentenceSplitter.split(item.text)
        guard !sentences.isEmpty else {
            itemFinished(itemGen: itemGen, parentGen: parentGen)
            return
        }
        let volume = Self.readVolume()

        engine.onDrained = { [weak self] in
            Task { await self?.handleDrain(itemGen: itemGen, parentGen: parentGen) }
        }
        engine.onPlaybackError = { [weak self] in
            Task { await self?.handlePlaybackError(itemGen: itemGen, parentGen: parentGen) }
        }

        playTask = Task {
            var scheduledFrames = 0
            // Hold off playing if the user is currently speaking/recording.
            while await self.isUserRecording() {
                if Task.isCancelled || parentGen != self.generation || itemGen != self.activeItemGen { return }
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            }

            if Task.isCancelled || parentGen != self.generation || itemGen != self.activeItemGen { return }
            self.writeLock()

            for sentence in sentences {
                if Task.isCancelled || parentGen != self.generation || itemGen != self.activeItemGen { break }
                do {
                    let (samples, _) = try await self.tts.synthesizeSamples(sentence, voice: item.voice, speed: item.speed)
                    if Task.isCancelled || parentGen != self.generation || itemGen != self.activeItemGen { break }
                    scheduledFrames += samples.count
                    self.engine.schedule(samples, volume: volume)
                } catch {
                    NSLog("TTSPlaybackController: synthesis failed: \(error)")
                    break
                }
            }
            self.synthFinished(itemGen: itemGen, parentGen: parentGen,
                               scheduledFrames: scheduledFrames)
        }
    }

    /// Stop playback and cancel pending synthesis immediately (barge-in / supersede).
    func bargeIn() {
        generation += 1
        playQueue.removeAll()
        currentItem = nil
        playTask?.cancel()
        playTask = nil
        drainWatchdog?.cancel()
        drainWatchdog = nil
        engine.stop()
        removeLock()
    }

    // MARK: - Completion coordination

    private func itemFinished(itemGen: Int, parentGen: Int) {
        guard parentGen == generation && itemGen == activeItemGen else { return }
        drainWatchdog?.cancel()
        drainWatchdog = nil
        currentItem = nil
        startNext()
  }

    /// The audio queue drained. Finish only if synthesis is also done — otherwise more sentences
    /// are still on the way and will re-fill the queue.
    private func handleDrain(itemGen: Int, parentGen: Int) {
        guard parentGen == generation && itemGen == activeItemGen && synthDone else { return }
        itemFinished(itemGen: itemGen, parentGen: parentGen)
    }

    /// The synthesis loop ended. Finish now if the queue is already empty; otherwise the final
    /// drain callback will.
    private func synthFinished(itemGen: Int, parentGen: Int, scheduledFrames: Int) {
        guard parentGen == generation && itemGen == activeItemGen else { return }
        synthDone = true
        if engine.isIdle {
            itemFinished(itemGen: itemGen, parentGen: parentGen)
            return
        }
        // Everything is scheduled; normally the drain callback finishes the item. But that
        // callback only arrives if the output device actually renders — with an aggregate /
        // multi-output device whose member is disconnected, `engine.start()` succeeds and
        // nothing plays, so `pending` never returns to zero. Without this watchdog the lock
        // is never released and the overlay's 33 fps "Speaking…" animation runs for the life
        // of the process (~12% of a core, observed 2026-09-06).
        let expected = Double(scheduledFrames) / AudioPlaybackEngine.defaultSampleRate
        startDrainWatchdog(itemGen: itemGen, parentGen: parentGen, after: expected + Self.drainGrace)
    }

    private func startDrainWatchdog(itemGen: Int, parentGen: Int, after seconds: TimeInterval) {
        drainWatchdog?.cancel()
        drainWatchdog = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(max(1, seconds) * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await self?.drainTimedOut(itemGen: itemGen, parentGen: parentGen)
        }
    }

    /// The scheduled audio outlived its own duration plus slack without draining. Treat it
    /// like a playback failure: stop the graph (which resets `pending`, so the next utterance
    /// isn't queued behind a count that will never clear) and release the UI.
    private func drainTimedOut(itemGen: Int, parentGen: Int) {
        guard parentGen == generation, itemGen == activeItemGen, !engine.isIdle else { return }
        NSLog("TTSPlaybackController: playback never drained — output device may not be rendering")
        drainWatchdog = nil
        playTask?.cancel()
        engine.stop()
        playQueue.removeAll()
        currentItem = nil
        removeLock()
    }

    /// The audio engine failed to start (e.g. the output device was removed mid-reply). Drop the
    /// lock so the UI doesn't hang in "Speaking…", and stop any further synthesis.
    private func handlePlaybackError(itemGen: Int, parentGen: Int) {
        guard parentGen == generation && itemGen == activeItemGen else { return }
        playTask?.cancel()
        drainWatchdog?.cancel()
        drainWatchdog = nil
        playQueue.removeAll()
        currentItem = nil
        removeLock()
    }

    // MARK: - Lock file + volume

    private var lockURL: URL { Paths.appSupport.appendingPathComponent("tts_playing.lock") }
    // The lock file stays — it is part of the documented Application Support bus — but the
    // app no longer polls it back off disk to learn its own state; `TTSPlaybackState` is the
    // in-process signal the overlay and DictationManager subscribe to.
    private func writeLock() {
        try? Data().write(to: lockURL)
        TTSPlaybackState.shared.set(true)
    }
    private func removeLock() {
        try? FileManager.default.removeItem(at: lockURL)
        TTSPlaybackState.shared.set(false)
        // Playback has fully stopped (queue drained, barge-in, or playback error) —
        // clear the wave instead of leaving it frozen on the last levels.
        PlaybackLevelMeter.shared.reset()
    }

    private static func readVolume() -> Float {
        TTSVolume.parse(try? String(contentsOf: Paths.ttsVolume, encoding: .utf8))
    }

    private func isUserRecording() async -> Bool {
        await MainActor.run {
            guard let delegate = AppDelegate.shared else { return false }
            return delegate.dictationManager.recorder.state == .recording
        }
    }
}
