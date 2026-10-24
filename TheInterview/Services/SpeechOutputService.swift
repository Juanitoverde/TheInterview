import AVFoundation
import InterviewCore

/// Speaks the receptionist's and interviewer's lines with distinct system voices.
@MainActor
final class SpeechOutputService: NSObject, VoiceOutput {
    /// AVSpeechUtterance rate, 0...1.
    var rate: Float = 0.48
    /// Called with the speaking character when a line starts, and `nil` when it ends.
    var onSpeakingChange: ((Speaker?) -> Void)?

    private let synthesizer = AVSpeechSynthesizer()
    private var continuation: CheckedContinuation<Void, Never>?
    private var currentUtteranceID: ObjectIdentifier?
    private lazy var voices: [Speaker: AVSpeechSynthesisVoice] = Self.chooseVoices()

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String, as speaker: Speaker) async {
        stop()
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voices[speaker]
        utterance.rate = rate
        utterance.pitchMultiplier = speaker == .receptionist ? 1.05 : 0.95
        utterance.postUtteranceDelay = 0.25
        currentUtteranceID = ObjectIdentifier(utterance)

        onSpeakingChange?(speaker)
        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                self.continuation = continuation
                self.synthesizer.speak(utterance)
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.stop() }
        }
        onSpeakingChange?(nil)
    }

    /// Cuts off the current line, if any.
    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        resume()
    }

    private func resume() {
        currentUtteranceID = nil
        continuation?.resume()
        continuation = nil
    }

    fileprivate func utteranceEnded(_ id: ObjectIdentifier) {
        // Ignore late callbacks for a line that was already cut off and replaced.
        guard id == currentUtteranceID else { return }
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
