import AVFoundation
import Speech
import InterviewCore

/// Captures the candidate's replies with on-device speech recognition, with typed input as a fallback.
///
/// A reply ends when the candidate stops talking for the request's silence timeout, says
/// "that's my answer", taps Done (`finishListening`), or submits typed text.
@MainActor
final class SpeechInputService: VoiceInput {
    enum InputError: Error {
        case recognizerUnavailable
        case microphoneUnavailable
    }

    private(set) var isVoiceAvailable = false
    /// Microphone level, 0...1, for the listening indicator.
    var onLevel: ((Float) -> Void)?
    /// Called when voice input becomes unavailable mid-session so the UI can offer typing.
    var onVoiceAvailabilityChange: ((Bool) -> Void)?

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var recognitionGeneration = 0
    private var session: ListeningSession?
    private var lastLevelUpdate = Date.distantPast
    private var audioSessionConfigured = false

    private final class ListeningSession {
        let request: ListenRequest
        let continuation: CheckedContinuation<Utterance, Error>
        let onPartial: @MainActor (String) -> Void
        let startedAt = Date()
        /// Text from recognition tasks that have already ended.
        var committed = ""
        /// Text from the running recognition task.
        var current = ""
        var speechStartedAt: Date?
        var lastSpeechAt: Date?
        var finishCueHeardAt: Date?
        var restarts = 0

        init(request: ListenRequest, continuation: CheckedContinuation<Utterance, Error>, onPartial: @escaping @MainActor (String) -> Void) {
            self.request = request
            self.continuation = continuation
            self.onPartial = onPartial
        }

        var text: String {
            [committed, current].filter { !$0.isEmpty }.joined(separator: " ")
        }
    }

    // MARK: Permissions

    /// Asks for speech recognition and microphone access. Returns whether voice input can be used.
    func requestAuthorization() async -> Bool {
        let speechStatus = await withCheckedContinuation { (continuation: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        let micGranted = await AVAudioApplication.requestRecordPermission()
        setVoiceAvailable(speechStatus == .authorized && micGranted && (recognizer?.isAvailable ?? false))
        if isVoiceAvailable { configureAudioSession() }
        return isVoiceAvailable
    }

    private func setVoiceAvailable(_ available: Bool) {
        guard available != isVoiceAvailable else { return }
        isVoiceAvailable = available
        onVoiceAvailabilityChange?(available)
    }

    private func configureAudioSession() {
        guard !audioSessionConfigured else { return }
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playAndRecord, mode: .default, options: [])
            try audioSession.setActive(true)
            audioSessionConfigured = true
        } catch {
            print("Audio session setup failed: \(error)")
        }
    }

    // MARK: VoiceInput

    func listen(_ request: ListenRequest, onPartial: @escaping @MainActor (String) -> Void) async throws -> Utterance {
        try Task.checkCancellation()
        cancel()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let session = ListeningSession(request: request, continuation: continuation, onPartial: onPartial)
                self.session = session
                if self.isVoiceAvailable {
                    do {
                        try self.startRecognition()
                    } catch {
                        print("Speech recognition couldn't start: \(error)")
                        self.setVoiceAvailable(false)
                    }
                }
                self.monitor(session)
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.cancel() }
        }
    }

    func finishListening() {
        if let session { complete(session) }
    }

    /// Ends the current listen with typed text instead of speech.
    func submitTyped(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let session, !trimmed.isEmpty else { return }
        self.session = nil
        stopRecognition()
        onLevel?(0)
        let now = Date()
        session.continuation.resume(returning: Utterance(text: trimmed, method: .typed, startedAt: session.startedAt, endedAt: now))
    }

    /// Abandons the current listen (the interview was cancelled).
    func cancel() {
        guard let session else { return }
        self.session = nil
        stopRecognition()
        onLevel?(0)
        session.continuation.resume(throwing: CancellationError())
    }

    // MARK: Session lifecycle

    private func complete(_ session: ListeningSession) {
        guard self.session === session else { return }
        self.session = nil
        stopRecognition()
        onLevel?(0)

        var text = session.text
        if session.request.allowsFinishCue {
            text = ResponseInterpreter.strippingFinishCue(from: text).text
        }
        let now = Date()
        let utterance = text.isEmpty
            ? Utterance.silence(startedAt: session.startedAt, endedAt: now)
            : Utterance(
                text: text,
                method: .voice,
                startedAt: session.startedAt,
                endedAt: now,
                speechStartedAt: session.speechStartedAt,
                speechEndedAt: session.lastSpeechAt
            )
        session.continuation.resume(returning: utterance)
    }

    /// Checks timeouts five times a second until the session ends.
    private func monitor(_ session: ListeningSession) {
        Task { @MainActor [weak self] in
            while true {
                try? await Task.sleep(for: .milliseconds(200))
                guard let self, self.session === session else { return }
                let now = Date()
                if let heard = session.finishCueHeardAt, now.timeIntervalSince(heard) >= 1.2 {
                    self.complete(session)
                    return
                }
                // Typing only: wait for the candidate to submit or tap Done.
                guard self.isVoiceAvailable else { continue }
                if let last = session.lastSpeechAt {
                    if now.timeIntervalSince(last) >= session.request.silenceTimeout {
                        self.complete(session)
                        return
                    }
                } else if now.timeIntervalSince(session.startedAt) >= session.request.startTimeout {
                    self.complete(session)
                    return
                }
            }
        }
    }

    // MARK: Recognition

    private func startRecognition() throws {
        guard let recognizer, recognizer.isAvailable else { throw InputError.recognizerUnavailable }
        stopRecognition()
        configureAudioSession()

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        request.taskHint = .dictation
        if recognizer.supportsOnDeviceRecognition {
            // On-device recognition keeps audio private and has no one-minute limit.
            request.requiresOnDeviceRecognition = true
        }

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw InputError.microphoneUnavailable }

        let levelHandler: @Sendable (Float) -> Void = { [weak self] level in
            Task { @MainActor in self?.updateLevel(level) }
        }
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format, block: Self.makeTapBlock(request: request, level: levelHandler))
        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            throw error
        }

        recognitionGeneration += 1
        let generation = recognitionGeneration
        let deliver: @Sendable (String?, Bool, Bool) -> Void = { [weak self] text, isFinal, failed in
            Task { @MainActor in self?.handleRecognition(text: text, isFinal: isFinal, failed: failed, generation: generation) }
        }
        recognitionRequest = request
        recognitionTask = recognizer.recognitionTask(with: request, resultHandler: Self.makeResultHandler(deliver))
    }

    private func stopRecognition() {
        recognitionGeneration += 1
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
    }

    private func handleRecognition(text: String?, isFinal: Bool, failed: Bool, generation: Int) {
        guard generation == recognitionGeneration, let session else { return }

        if let text, !text.isEmpty, text != session.current {
            session.current = text
            let now = Date()
            if session.speechStartedAt == nil { session.speechStartedAt = now }
            session.lastSpeechAt = now
            session.onPartial(session.text)
            if session.request.allowsFinishCue {
                // Wait briefly after the cue in case the sentence continues ("that's all there is to it").
                session.finishCueHeardAt = ResponseInterpreter.strippingFinishCue(from: session.text).hadCue ? now : nil
            }
        }

        if isFinal || failed {
            // The recogniser stopped (final result, time limit or error). Keep the text and start a fresh task.
            session.committed = session.text
            session.current = ""
            stopRecognition()
            guard session.restarts < 30 else { return }
            session.restarts += 1
            do {
                try startRecognition()
            } catch {
                setVoiceAvailable(false)
            }
        }
    }

    private func updateLevel(_ level: Float) {
        guard session != nil else { return }
        let now = Date()
        guard now.timeIntervalSince(lastLevelUpdate) > 0.06 else { return }
        lastLevelUpdate = now
        onLevel?(level)
    }

    // These are built outside the main actor because AVAudioEngine and Speech call them on background threads.

    nonisolated private static func makeTapBlock(request: SFSpeechAudioBufferRecognitionRequest, level: @escaping @Sendable (Float) -> Void) -> AVAudioNodeTapBlock {
        { buffer, _ in
            request.append(buffer)
            level(normalizedLevel(of: buffer))
        }
    }

    nonisolated private static func makeResultHandler(_ deliver: @escaping @Sendable (String?, Bool, Bool) -> Void) -> (SFSpeechRecognitionResult?, Error?) -> Void {
        { result, error in
            deliver(result?.bestTranscription.formattedString, result?.isFinal ?? false, error != nil)
        }
    }

    /// RMS level mapped from roughly -50 dB...0 dB onto 0...1.
    nonisolated private static func normalizedLevel(of buffer: AVAudioPCMBuffer) -> Float {
        guard let samples = buffer.floatChannelData?[0] else { return 0 }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return 0 }
        var sum: Float = 0
        for index in 0..<count {
            sum += samples[index] * samples[index]
        }
        let rms = (sum / Float(count)).squareRoot()
        let decibels = 20 * log10(max(rms, 0.000_01))
        return max(0, min(1, (decibels + 50) / 50))
    }
}
