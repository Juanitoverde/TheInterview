import SwiftUI
import Observation
import InterviewCore

/// App-wide state: settings, the running interview, past reports, and window/immersive-space coordination.
@MainActor
@Observable
final class AppModel {
    static let mainWindowID = "main"
    static let officeSpaceID = "office"

    enum Screen: Equatable {
        case home
        case preparing
        case interviewing
        case analyzing
        case report(InterviewReport)
    }

    var screen: Screen = .home
    var settings: AppSettings
    /// Mirrors the engine's state for the UI.
    private(set) var interview = InterviewState()
    private(set) var history: [InterviewReport] = []
    var alertMessage: String?

    private(set) var micLevel: Float = 0
    private(set) var isVoiceInputAvailable = false
    private(set) var liveEngagement: Bool?
    private(set) var hasAPIKey = false

    /// Set when the immersive office should close; the immersive view observes it.
    private(set) var exitImmersiveRequested = false
    private(set) var immersiveSpaceIsOpen = false
    var mainWindowIsOpen = true

    let speechOutput = SpeechOutputService()
    let speechInput = SpeechInputService()
    let attentionTracker = HeadPoseAttentionTracker()

    private let reportStore = ReportStore(directory: ReportStore.defaultDirectory())
    @ObservationIgnored private var engine: InterviewEngine?
    @ObservationIgnored private var engineTask: Task<Void, Never>?
    @ObservationIgnored private var stage: OfficeStage?

    init() {
        settings = AppSettings.load()
        history = reportStore.loadAll()
        hasAPIKey = Self.resolvedAPIKey() != nil

        speechInput.onLevel = { [weak self] level in self?.micLevel = level }
        speechInput.onVoiceAvailabilityChange = { [weak self] available in self?.isVoiceInputAvailable = available }
        speechOutput.onSpeakingChange = { [weak self] speaker in self?.stage?.setSpeaking(speaker) }
        speechOutput.voiceSource = { [weak self] speaker in self?.stage?.voiceSource(for: speaker) }
        attentionTracker.onEngagementChange = { [weak self] engaged in self?.liveEngagement = engaged }
    }

    // MARK: Settings & API key

    func saveSettings() {
        settings.save()
    }

    /// The OpenAI key from the Keychain, or from the OPENAI_API_KEY environment variable (handy in the simulator).
    static func resolvedAPIKey() -> String? {
        let stored = KeychainStore.readAPIKey() ?? ProcessInfo.processInfo.environment["OPENAI_API_KEY"] ?? ""
        let trimmed = stored.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func updateAPIKey(_ key: String) -> Bool {
        let saved = KeychainStore.saveAPIKey(key)
        hasAPIKey = Self.resolvedAPIKey() != nil
        return saved
    }

    private func makeClient() -> OpenAIClient? {
        Self.resolvedAPIKey().map { OpenAIClient(apiKey: $0, model: settings.openAIModel) }
    }

    /// Sends a tiny request to check the key and model. Returns an error message, or nil on success.
    func testOpenAIConnection() async -> String? {
        guard let client = makeClient() else { return OpenAIError.missingAPIKey.localizedDescription }
        do {
            try await client.verify()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    // MARK: Interview lifecycle

    /// Step 1, from the home screen: ask for microphone and speech permission.
    /// The caller then opens the immersive space.
    func prepareInterview() async {
        saveSettings()
        screen = .preparing
        exitImmersiveRequested = false
        isVoiceInputAvailable = await speechInput.requestAuthorization()
        speechOutput.rate = Float(settings.speechRate)
    }

    func immersiveSpaceFailedToOpen() {
        screen = .home
        alertMessage = "The office couldn't be opened. Please try again."
    }

    /// Step 2, from the immersive view once the office is built: start the interview.
    func officeDidLoad(_ stage: OfficeStage) {
        self.stage = stage
        immersiveSpaceIsOpen = true
        attentionTracker.target = { [weak stage] in stage?.interviewerEyePosition }
        stage.start()
        startEngine(stage: stage)
    }

    private func startEngine(stage: OfficeStage) {
        guard engineTask == nil else { return }

        let questionGenerator: QuestionGenerating
        let reactionGenerator: ReactionGenerating?
        let evaluator: InterviewEvaluating
        if let client = makeClient() {
            questionGenerator = OpenAIQuestionGenerator(client: client)
            reactionGenerator = OpenAIReactionGenerator(client: client)
            evaluator = ResilientEvaluator(primary: OpenAIEvaluator(client: client))
        } else {
            questionGenerator = OfflineQuestionGenerator()
            reactionGenerator = nil
            evaluator = ResilientEvaluator(primary: nil)
        }
        let attention: AttentionTracking = HeadPoseAttentionTracker.isSupported ? attentionTracker : NullAttentionTracker()

        let engine = InterviewEngine(
            candidate: settings.candidate,
            configuration: settings.interviewConfiguration,
            voice: speechOutput,
            input: speechInput,
            stage: stage,
            attention: attention,
            questionGenerator: questionGenerator,
            reactionGenerator: reactionGenerator,
            evaluator: evaluator
        )
        engine.onStateChange = { [weak self] state in self?.engineStateChanged(state) }
        self.engine = engine
        interview = engine.state
        screen = .interviewing

        engineTask = Task { [weak self] in
            let report = await engine.run()
            self?.engineFinished(with: report)
        }
    }

    private func engineStateChanged(_ state: InterviewState) {
        let previousPhase = interview.phase
        interview = state
        stage?.setListening(state.isListening)
        if state.phase == .analyzing, previousPhase != .analyzing {
            // The interview is over; analysis continues while we return to the window.
            screen = .analyzing
            requestImmersiveExit()
        }
    }

    private func engineFinished(with report: InterviewReport?) {
        engineTask = nil
        engine = nil
        if let report {
            do {
                try reportStore.save(report)
            } catch {
                print("Couldn't save report: \(error)")
            }
            history.insert(report, at: 0)
            screen = .report(report)
        } else if screen != .home {
            screen = .home
        }
        requestImmersiveExit()
    }

    private func requestImmersiveExit() {
        if immersiveSpaceIsOpen { exitImmersiveRequested = true }
    }

    // MARK: Controls from the in-office panel

    func finishAnswer() {
        engine?.finishAnswer()
    }

    func repeatQuestion() {
        engine?.requestRepeat()
    }

    func submitTypedReply(_ text: String) {
        speechInput.submitTyped(text)
    }

    /// Stops after the current answer and goes to feedback; before the questions start, simply leaves.
    func endInterviewEarly() {
        if interview.phase.isInQuestions {
            engine?.endEarly()
        } else {
            leaveInterview()
        }
    }

    /// Abandons the interview without a report.
    func leaveInterview() {
        engineTask?.cancel()
        speechOutput.stop()
        speechInput.cancel()
        screen = .home
        requestImmersiveExit()
    }

    // MARK: Window & immersive space coordination

    /// Reopens the main window if it isn't already showing (it's dismissed while in the office).
    func reopenMainWindow(_ openWindow: OpenWindowAction) {
        guard !mainWindowIsOpen else { return }
        mainWindowIsOpen = true
        openWindow(id: Self.mainWindowID)
    }

    func immersiveSpaceDidClose() {
        immersiveSpaceIsOpen = false
        exitImmersiveRequested = false
        attentionTracker.stopSession()
        stage?.tearDown()
        stage = nil
        // Closed from the system (e.g. Digital Crown) mid-interview: abandon it unless it's already being analysed.
        if engineTask != nil, interview.phase != .analyzing {
            leaveInterview()
        }
    }

    // MARK: History

    func showReport(_ report: InterviewReport) {
        screen = .report(report)
    }

    func deleteReport(_ report: InterviewReport) {
        try? reportStore.delete(id: report.id)
        history.removeAll { $0.id == report.id }
        if case .report(let shown) = screen, shown.id == report.id {
            screen = .home
        }
    }

    func goHome() {
        screen = .home
    }
}
