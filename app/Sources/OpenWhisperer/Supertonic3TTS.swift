import Foundation
import FluidAudio
import OpenWhispererKit

/// In-process Supertonic-3 text-to-speech via FluidAudio (CoreML / ANE) — the engine for the
/// languages Kokoro-82M has no voice for (Dutch, German, Polish, Russian, Ukrainian, …).
///
/// Actor-isolated for the same reasons as `KokoroTTS`: one compute unit, so synthesis calls
/// serialize, and concurrent callers dedup the one-time model load. FluidAudio caches the
/// CoreML chain under `~/.cache/fluidaudio/Models/supertonic-3` and loads from cache when
/// present, so an already-downloaded model survives a blocked or slow Hub.
///
/// Measured on this machine (M-series, warm cache, one short sentence): model load 0.10 s,
/// inference 0.12 s for 2.29 s of audio — ~19× realtime, about 10× faster than Kokoro's 1.93×.
/// That headroom is why the sentence-by-sentence streaming path needs no special handling.
actor Supertonic3TTS {
    enum Supertonic3TTSError: LocalizedError {
        case loadFailed(String)
        case unsupportedLanguage(String)
        var errorDescription: String? {
            switch self {
            case .loadFailed(let why): return "Multilingual TTS model failed to load: \(why)"
            case .unsupportedLanguage(let lang): return "Supertonic-3 does not support language '\(lang)'"
            }
        }
    }

    /// ANE-bucketed int8: ~94–96% on the Neural Engine and the closest of the quantized builds
    /// to FP16 ("transparent" per upstream). Deliberately *not* `.fp16Dynamic` — RangeDim shapes
    /// can't use the ANE, so FP16 measured both slower (0.67 s vs 0.12 s) *and* off-ANE. Also
    /// not the upstream `.default` (int4), which measured 0.16 s; int8 buys quality headroom for
    /// ~100 MB more on disk, and quality is the priority for these languages.
    private static let vectorEstimator: Supertonic3VectorEstimator = .aneBucketed(.int8)

    private let manager = Supertonic3Manager(
        computeUnits: .cpuAndNeuralEngine, vectorEstimator: Supertonic3TTS.vectorEstimator)
    private var loaded = false
    private var loadTask: Task<Void, Error>?
    /// Decoded style tensors, keyed by style name. `Supertonic3VoiceStyle` is `Sendable` and
    /// reusable across synthesize calls, so we fetch each style at most once per launch.
    private var styles: [String: Supertonic3VoiceStyle] = [:]

    var isReady: Bool { loaded }

    /// Download (first run) + load the 4-stage Supertonic-3 CoreML pipeline. Idempotent:
    /// concurrent callers await the same in-flight load.
    func prepare() async throws {
        if loaded { return }
        if let loadTask { try await loadTask.value; return }

        let task = Task<Void, Error> { try await manager.initialize() }
        loadTask = task
        do {
            try await task.value
            loaded = true
            loadTask = nil
        } catch {
            loadTask = nil
            throw Supertonic3TTSError.loadFailed(error.localizedDescription)
        }
    }

    /// Synthesize `text` → 44.1 kHz mono WAV `Data` for the blocking `/v1/audio/speech` path.
    /// Peak-normalizes, matching what FluidAudio's own CLI does for this backend.
    func synthesize(_ text: String, language: String, style: String, speed: Float = TTSSpeed.default)
        async throws -> Data {
        let result = try await synthesizeSamples(text, language: language, style: style, speed: speed)
        return try AudioWAV.data(from: result.samples, sampleRate: Double(result.sampleRate))
    }

    /// Synthesize `text` → raw 44.1 kHz mono fp32 PCM samples (no WAV wrapper) for in-process
    /// streaming playback. Same numeric pre-pass as `KokoroTTS` — the engine mishandles raw
    /// `$5.99`/`15%`, and `NumberNormalizer` is language-agnostic enough to be worth keeping.
    func synthesizeSamples(
        _ text: String, language: String, style: String, speed: Float = TTSSpeed.default
    ) async throws -> (samples: [Float], sampleRate: Int) {
        guard TTSVoiceRouter.supertonicLanguages.contains(language) else {
            throw Supertonic3TTSError.unsupportedLanguage(language)
        }
        if !loaded { try await prepare() }
        let voiceStyle = try await loadStyle(style)
        let spoken = NumberNormalizer.normalize(text)
        // `synthesize` returns (samples, *duration*) — not a sample rate. The rate is fixed at
        // 44.1 kHz by the vocoder; `AudioPlaybackEngine` takes it per item, so no resampling.
        let (samples, _) = try await manager.synthesize(
            text: spoken, language: language, style: voiceStyle, speed: speed)
        return (samples, Supertonic3Constants.sampleRate)
    }

    /// Fetch + decode a voice style, memoized. Unlike Kokoro's voice packs there's no hand-rolled
    /// download here: `Supertonic3ResourceDownloader.loadVoiceStyle` is public in FluidAudio and
    /// pulls the style JSON into the same hub cache the models use.
    private func loadStyle(_ style: String) async throws -> Supertonic3VoiceStyle {
        let name = TTSVoiceRouter.supertonicStyles.contains(style.uppercased())
            ? style.uppercased()
            : TTSVoiceRouter.defaultSupertonicStyle
        if let cached = styles[name] { return cached }
        let voice = Supertonic3Voice(name: name) ?? .default
        let loadedStyle = try await Supertonic3ResourceDownloader.loadVoiceStyle(voice)
        styles[name] = loadedStyle
        return loadedStyle
    }
}
