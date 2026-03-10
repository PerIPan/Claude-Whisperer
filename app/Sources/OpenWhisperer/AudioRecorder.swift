import AVFoundation
import AppKit
import Combine

/// Records microphone audio, provides real-time RMS levels for waveform,
/// and exports 16kHz 16-bit mono WAV data for Whisper transcription.
class AudioRecorder: ObservableObject {
    enum State {
        case idle, recording, uploading
    }

    // @Published must only be mutated from main thread
    @Published var state: State = .idle
    @Published var audioLevel: Float = 0.0
    @Published var levelHistory: [Float] = Array(repeating: 0, count: 50)
    @Published var micPermission: Bool = false

    private var engine: AVAudioEngine?
    private var pcmBuffers: [AVAudioPCMBuffer] = []
    private let bufferLock = NSLock()
    /// Protected by bufferLock — accessed from audio tap thread and main thread.
    private var converter: AVAudioConverter?
    private let targetSampleRate: Double = 16000
    private let smoothing: Float = 0.3
    private let targetFormat = AVAudioFormat(commonFormat: .pcmFormatInt16,
                                              sampleRate: 16000,
                                              channels: 1,
                                              interleaved: true)!

    init(skipPermissionCheck: Bool = false) {
        if !skipPermissionCheck {
            checkPermission()
        }
    }

    // MARK: - Permissions

    func checkPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            DispatchQueue.main.async { self.micPermission = true }
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                DispatchQueue.main.async { self?.micPermission = granted }
            }
        default:
            DispatchQueue.main.async { self.micPermission = false }
        }
    }

    func openMicSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Recording (must be called from main thread)

    func startRecording() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard micPermission, state == .idle else { return }
        state = .recording

        let engine = AVAudioEngine()
        self.engine = engine

        let inputNode = engine.inputNode
        let hwFormat = inputNode.outputFormat(forBus: 0)

        guard let conv = AVAudioConverter(from: hwFormat, to: targetFormat) else {
            print("[AudioRecorder] Failed to create converter from \(hwFormat) to \(targetFormat)")
            state = .idle
            return
        }
        bufferLock.lock()
        converter = conv
        pcmBuffers = []
        bufferLock.unlock()

        let bufferSize: AVAudioFrameCount = 1024
        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: hwFormat) { [weak self] buffer, _ in
            guard let self else { return }

            let rms = self.computeRMS(buffer: buffer)
            DispatchQueue.main.async {
                self.audioLevel = self.audioLevel * (1 - self.smoothing) + rms * self.smoothing
                self.levelHistory.removeFirst()
                self.levelHistory.append(self.audioLevel)
            }

            if let converted = self.convert(buffer: buffer) {
                self.bufferLock.lock()
                self.pcmBuffers.append(converted)
                self.bufferLock.unlock()
            }
        }

        do {
            try engine.start()
        } catch {
            print("[AudioRecorder] Engine start failed: \(error)")
            cleanup()
        }
    }

    /// Stop recording and set state to uploading. Must be called from main thread.
    /// Returns immediately — call `exportWAV()` on a background thread to get the data.
    func stopRecording() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard state == .recording else { return }
        state = .uploading

        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        bufferLock.lock()
        converter = nil
        bufferLock.unlock()

        audioLevel = 0
        levelHistory = Array(repeating: 0, count: 50)
    }

    /// Merge accumulated PCM buffers into WAV data. Safe to call from any thread.
    func exportWAV() -> Data? {
        // Snapshot buffers under lock, then merge outside to avoid blocking audio tap
        bufferLock.lock()
        let snapshot = pcmBuffers
        pcmBuffers = []
        bufferLock.unlock()
        return mergeToWAV(from: snapshot)
    }

    func reset() {
        dispatchPrecondition(condition: .onQueue(.main))
        state = .idle
    }

    private func cleanup() {
        dispatchPrecondition(condition: .onQueue(.main))
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        bufferLock.lock()
        converter = nil
        pcmBuffers = []
        bufferLock.unlock()
        state = .idle
    }

    // MARK: - Audio Processing

    private func computeRMS(buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else { return 0 }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return 0 }
        let data = UnsafeBufferPointer(start: channelData[0], count: count)
        let sumSq = data.reduce(Float(0)) { $0 + $1 * $1 }
        let rms = sqrt(sumSq / Float(count))
        return min(rms * 50.0, 1.0)
    }

    private func convert(buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        bufferLock.lock()
        let conv = converter
        bufferLock.unlock()
        guard let conv else { return nil }
        let ratio = targetSampleRate / buffer.format.sampleRate
        let outputFrames = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 32
        guard outputFrames > 0 else { return nil }

        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputFrames) else {
            return nil
        }

        var error: NSError?
        var consumed = false
        conv.convert(to: outputBuffer, error: &error) { _, status in
            if consumed {
                status.pointee = .noDataNow
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return buffer
        }

        if let error {
            print("[AudioRecorder] Conversion error: \(error)")
            return nil
        }
        return outputBuffer.frameLength > 0 ? outputBuffer : nil
    }

    // MARK: - WAV Export

    private func mergeToWAV(from buffers: [AVAudioPCMBuffer]) -> Data? {
        guard !buffers.isEmpty else { return nil }

        let totalFrames = buffers.reduce(0) { $0 + Int($1.frameLength) }
        guard totalFrames > 0 else { return nil }

        let bytesPerSample = 2
        let numChannels = 1
        let dataSize = totalFrames * bytesPerSample * numChannels

        var wav = Data()

        wav.append(contentsOf: [UInt8]("RIFF".utf8))
        wav.append(uint32LE: UInt32(36 + dataSize))
        wav.append(contentsOf: [UInt8]("WAVE".utf8))

        wav.append(contentsOf: [UInt8]("fmt ".utf8))
        wav.append(uint32LE: 16)
        wav.append(uint16LE: 1)
        wav.append(uint16LE: UInt16(numChannels))
        wav.append(uint32LE: UInt32(targetSampleRate))
        wav.append(uint32LE: UInt32(targetSampleRate) * UInt32(numChannels * bytesPerSample))
        wav.append(uint16LE: UInt16(numChannels * bytesPerSample))
        wav.append(uint16LE: UInt16(bytesPerSample * 8))

        wav.append(contentsOf: [UInt8]("data".utf8))
        wav.append(uint32LE: UInt32(dataSize))

        for buffer in buffers {
            guard let int16Data = buffer.int16ChannelData else { continue }
            let count = Int(buffer.frameLength)
            guard count > 0 else { continue }
            let ptr = UnsafeBufferPointer(start: int16Data[0], count: count)
            guard let base = ptr.baseAddress else { continue }
            wav.append(UnsafeBufferPointer(start: UnsafeRawPointer(base).assumingMemoryBound(to: UInt8.self),
                                            count: count * bytesPerSample))
        }

        return wav
    }
}

// MARK: - Data helpers for WAV header

private extension Data {
    mutating func append(uint16LE value: UInt16) {
        var v = value.littleEndian
        withUnsafePointer(to: &v) { ptr in
            append(UnsafeBufferPointer(start: ptr, count: 1))
        }
    }
    mutating func append(uint32LE value: UInt32) {
        var v = value.littleEndian
        withUnsafePointer(to: &v) { ptr in
            append(UnsafeBufferPointer(start: ptr, count: 1))
        }
    }
}
