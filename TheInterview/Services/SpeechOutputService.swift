import AVFoundation
import RealityKit
import InterviewCore

/// Speaks the receptionist's and interviewer's lines with distinct voices.
///
/// In the office, each line is rendered to audio and played from the character's mouth with
/// RealityKit spatial audio, so voices come from where people are standing. Anywhere else, or if
/// rendering fails, the line is spoken by the system voice instead.
@MainActor
final class SpeechOutputService: NSObject, VoiceOutput {
    /// AVSpeechUtterance rate, 0...1.
    var rate: Float = 0.48
    /// Called with the speaking character when a line starts, and `nil` when it ends.
    var onSpeakingChange: ((Speaker?) -> Void)?
    /// Where each character's voice should come from, when the office is open.
    var voiceSource: ((Speaker) -> Entity?)?

    private let synthesizer = AVSpeechSynthesizer()
    private let renderer = AVSpeechSynthesizer()
    private var continuation: CheckedContinuation<Void, Never>?
    private var currentUtteranceID: ObjectIdentifier?
    private var spatialPlayback: AudioPlaybackController?
    private var currentPlaybackID: UUID?
    private lazy var voices: [Speaker: AVSpeechSynthesisVoice] = Self.chooseVoices()

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String, as speaker: Speaker) async {
        stop()
        if let source = voiceSource?(speaker),
           let buffer = await render(makeUtterance(text, speaker)),
           !Task.isCancelled,
           let resource = try? AudioBufferResource(buffer: buffer, inputMode: .spatial, shouldLoop: false) {
            onSpeakingChange?(speaker)
            await playSpatially(resource, from: source)
        } else if !Task.isCancelled {
            onSpeakingChange?(speaker)
            await speakWithSystemVoice(makeUtterance(text, speaker))
        }
        onSpeakingChange?(nil)
    }

    /// Cuts off the current line, if any.
    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        spatialPlayback?.stop()
        spatialPlayback = nil
        resume()
    }

    private func makeUtterance(_ text: String, _ speaker: Speaker) -> AVSpeechUtterance {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voices[speaker]
        utterance.rate = rate
        utterance.pitchMultiplier = speaker == .receptionist ? 1.05 : 0.95
        utterance.postUtteranceDelay = 0.25
        return utterance
    }

    private func resume() {
        currentUtteranceID = nil
        currentPlaybackID = nil
        continuation?.resume()
        continuation = nil
    }

    // MARK: System voice

    private func speakWithSystemVoice(_ utterance: AVSpeechUtterance) async {
        currentUtteranceID = ObjectIdentifier(utterance)
        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                self.continuation = continuation
                self.synthesizer.speak(utterance)
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.stop() }
        }
    }

    fileprivate func utteranceEnded(_ id: ObjectIdentifier) {
        // Ignore late callbacks for a line that was already cut off and replaced.
        guard id == currentUtteranceID else { return }
        resume()
    }

    // MARK: Spatial voice

    /// Renders a line to a mono float buffer, or nil if the synthesizer can't.
    private func render(_ utterance: AVSpeechUtterance) async -> AVAudioPCMBuffer? {
        let collector = SpeechBufferCollector()
        let renderer = renderer
        return await withCheckedContinuation { (continuation: CheckedContinuation<AVAudioPCMBuffer?, Never>) in
            collector.onFinish = { continuation.resume(returning: $0) }
            renderer.write(utterance) { buffer in collector.add(buffer) }
            // Safety net in case the synthesizer never signals the end of the line.
            Task {
                try? await Task.sleep(for: .seconds(8))
                collector.finish()
            }
        }
    }

    private func playSpatially(_ resource: AudioBufferResource, from source: Entity) async {
        if source.components[SpatialAudioComponent.self] == nil {
            source.components.set(SpatialAudioComponent())
        }
        let id = UUID()
        currentPlaybackID = id
        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                self.continuation = continuation
                let playback = source.playAudio(resource)
                self.spatialPlayback = playback
                playback.completionHandler = { [weak self] in
                    Task { @MainActor in self?.playbackEnded(id) }
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.stop() }
        }
        try? await Task.sleep(for: .seconds(0.25))
    }

    private func playbackEnded(_ id: UUID) {
        guard id == currentPlaybackID else { return }
        spatialPlayback = nil
        resume()
    }

    /// Picks the best available English voices: female for the receptionist, male for the interviewer.
    private static func chooseVoices() -> [Speaker: AVSpeechSynthesisVoice] {
        let english = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("en") }
        func best(_ gender: AVSpeechSynthesisVoiceGender) -> AVSpeechSynthesisVoice? {
            english
                .filter { $0.gender == gender }
                .max { lhs, rhs in
                    (lhs.quality.rawValue, lhs.language == "en-US" ? 1 : 0) < (rhs.quality.rawValue, rhs.language == "en-US" ? 1 : 0)
                }
        }
        let fallback = AVSpeechSynthesisVoice(language: "en-US")
        var voices: [Speaker: AVSpeechSynthesisVoice] = [:]
        voices[.receptionist] = best(.female) ?? fallback
        voices[.interviewer] = best(.male) ?? fallback
        voices[.candidate] = fallback
        return voices
    }
}

extension SpeechOutputService: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in self.utteranceEnded(id) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in self.utteranceEnded(id) }
    }
}

/// Gathers the audio chunks AVSpeechSynthesizer renders (on a background thread) into one mono float buffer.
private final class SpeechBufferCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var samples: [Float] = []
    private var sampleRate: Double = 22_050
    private var failed = false
    private var finished = false
    var onFinish: ((AVAudioPCMBuffer?) -> Void)?

    func add(_ buffer: AVAudioBuffer) {
        guard let pcm = buffer as? AVAudioPCMBuffer else { return }
        let frames = Int(pcm.frameLength)
        // An empty buffer marks the end of the line.
        guard frames > 0 else {
            finish()
            return
        }
        let stride = max(Int(pcm.stride), 1)
        var chunk = [Float](repeating: 0, count: frames)
        switch pcm.format.commonFormat {
        case .pcmFormatFloat32:
            guard let data = pcm.floatChannelData?[0] else { return }
            for index in 0..<frames { chunk[index] = data[index * stride] }
        case .pcmFormatInt16:
            guard let data = pcm.int16ChannelData?[0] else { return }
            for index in 0..<frames { chunk[index] = Float(data[index * stride]) / 32_768 }
        default:
            lock.withLock { failed = true }
            finish()
            return
        }
        lock.withLock {
            guard !finished else { return }
            samples.append(contentsOf: chunk)
            sampleRate = pcm.format.sampleRate
        }
    }

    func finish() {
        let result: (samples: [Float], rate: Double, failed: Bool)? = lock.withLock {
            guard !finished else { return nil }
            finished = true
            return (samples, sampleRate, failed)
        }
        guard let result else { return }
        onFinish?(result.failed ? nil : Self.makeBuffer(result.samples, sampleRate: result.rate))
    }

    private static func makeBuffer(_ samples: [Float], sampleRate: Double) -> AVAudioPCMBuffer? {
        guard !samples.isEmpty,
              let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?[0]
        else { return nil }
        samples.withUnsafeBufferPointer { source in
            channel.update(from: source.baseAddress!, count: samples.count)
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        return buffer
    }
}
