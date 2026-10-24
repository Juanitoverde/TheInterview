import Foundation

/// Runs one interview from the reception desk to the feedback report.
///
/// The engine owns the script and the order of events; everything platform-specific (speech, the 3D
/// scene, head tracking, the network) is injected through protocols so the whole flow can be tested.
@MainActor
public final class InterviewEngine {
    public private(set) var state = InterviewState() {
        didSet {
            if state != oldValue { onStateChange?(state) }
        }
    }

    /// Called on the main actor whenever `state` changes.
    public var onStateChange: ((InterviewState) -> Void)?

    public let candidate: CandidateProfile
    public let configuration: InterviewConfiguration

    private let voice: VoiceOutput
    private let input: VoiceInput
    private let stage: StageDirecting
    private let attention: AttentionTracking
    private let questionGenerator: QuestionGenerating
    private let reactionGenerator: ReactionGenerating?
    private let evaluator: InterviewEvaluating
    private let fallbackEvaluator = HeuristicEvaluator()
    private let questionBank = QuestionBank()
    private let now: () -> Date
    private var script: InterviewScript

    private var startedAt = Date()
    private var answers: [AnswerRecord] = []
    private var plannedQuestionCount = 0
    private var followUpsAsked = 0
    private var candidateQuestions: [String] = []
    private var candidateQuestionsInvited = false
    private var questionTask: Task<[InterviewQuestion], Never>?
    private var questionsReady = false
    private var earlyEndRequested = false
    private var repeatRequested = false

    /// Fallback position name when the candidate's reply can't be understood and none was preset.
    public static let defaultPosition = "General Applicant"

    public init(
        candidate: CandidateProfile,
        configuration: InterviewConfiguration,
        voice: VoiceOutput,
        input: VoiceInput,
        stage: StageDirecting,
        attention: AttentionTracking,
        questionGenerator: QuestionGenerating,
        reactionGenerator: ReactionGenerating?,
        evaluator: InterviewEvaluating,
        seed: UInt64 = UInt64.random(in: .min ... .max),
        now: @escaping () -> Date = Date.init
    ) {
        self.candidate = candidate
        self.configuration = configuration
        self.voice = voice
        self.input = input
        self.stage = stage
        self.attention = attention
        self.questionGenerator = questionGenerator
        self.reactionGenerator = reactionGenerator
        self.evaluator = evaluator
        self.now = now
        script = InterviewScript(candidate: candidate, configuration: configuration, seed: seed)
    }

    // MARK: Controls

    /// The candidate tapped "Done" while answering.
    public func finishAnswer() {
        input.finishListening()
    }

    /// The candidate asked to hear the current question again.
    public func requestRepeat() {
        guard state.phase == .answering else { return }
        repeatRequested = true
        input.finishListening()
    }

    /// Stop after the current answer and go straight to feedback.
    public func endEarly() {
        earlyEndRequested = true
        if state.isListening { input.finishListening() }
    }

    public var hasAnswers: Bool { !answers.isEmpty }

    // MARK: Flow

    /// Runs the whole interview. Returns the report, or `nil` if cancelled or nothing was answered.
    /// Cancel the surrounding task to abandon the interview without a report.
    public func run() async -> InterviewReport? {
        startedAt = now()
        do {
            try await reception()
            try await walkToInterviewRoom()
            try await meetInterviewer()
            try await askQuestions()
            try await inviteCandidateQuestions()
            try await close()
        } catch {
            questionTask?.cancel()
            _ = attention.stopTracking()
            update {
                $0.phase = .cancelled
                $0.isListening = false
                $0.currentSpeaker = nil
            }
            return nil
        }
        return await analyze()
    }

    private func reception() async throws {
        update { $0.phase = .reception }
        try await perform(.enterReception)

        let wave = cue(.receptionistWaves)
        try await say(.receptionist, script.receptionGreeting(at: now()))
        await wave.value

        var position: String?
        for attempt in 0..<3 {
            try await say(.receptionist, attempt == 0 ? script.askPosition() : script.askPositionAgain())
            let reply = try await listen(.position)
            if let extracted = ResponseInterpreter.extractPosition(from: reply.text) {
                position = extracted
                break
            }
        }

        let pointing = cue(.receptionistPointsTheWay)
        let resolved: String
        if let position {
            resolved = position
            update { $0.position = resolved }
            startGeneratingQuestions(for: resolved)
            try await say(.receptionist, script.confirmAppointment(position: resolved))
        } else {
            resolved = configuration.presetPosition?.nilIfBlank ?? Self.defaultPosition
            update { $0.position = resolved }
            startGeneratingQuestions(for: resolved)
            try await say(.receptionist, script.positionFallback(position: resolved))
        }
        await pointing.value
    }

    private func walkToInterviewRoom() async throws {
        update { $0.phase = .walking }
        let walk = cue(.walkToInterviewRoom)
        try await say(.receptionist, script.walkingSmallTalk())
        try await wait(for: walk)
        try await say(.receptionist, script.arrival(position: state.position ?? Self.defaultPosition))
        _ = cue(.receptionistLeaves)
    }

    private func meetInterviewer() async throws {
        update { $0.phase = .meetingInterviewer }
        try await perform(.interviewerStands)
        try await say(.interviewer, script.interviewerIntro(position: state.position ?? Self.defaultPosition))
        let sit = cue(.interviewerSits)
        try await perform(.focusOnInterviewer)
        try await wait(for: sit)

        attention.startTracking()
        update { $0.phase = .waitingForReady }

        var askedAgain = false
        attempts: for attempt in 0..<4 {
            if attempt == 0 {
                try await say(.interviewer, script.askReady())
            } else if askedAgain {
                try await say(.interviewer, script.askReadyAgain())
            }
            askedAgain = true
            let reply = try await listen(.readiness)
            if earlyEndRequested { break }
            switch ResponseInterpreter.readiness(of: reply.text) {
            case .ready:
                break attempts
            case .notReady:
                try await say(.interviewer, script.notReadyResponse())
                // Wait for them to say they're ready without asking again.
                askedAgain = false
            case .unclear:
                if attempt >= 1 {
                    try await say(.interviewer, script.proceedAnyway())
                    break attempts
                }
            }
        }
    }

    private func askQuestions() async throws {
        guard !earlyEndRequested else { return }
        update { $0.phase = .preparingQuestions }
        if questionTask == nil { startGeneratingQuestions(for: state.position ?? Self.defaultPosition) }
        if !questionsReady {
            try await say(.interviewer, script.preparingQuestions())
        }
        let questions = await questionTask?.value ?? []
        try Task.checkCancellation()
        plannedQuestionCount = questions.count
        update { $0.questionCount = questions.count }

        try await say(.interviewer, script.startLine(questionCount: questions.count))

        for (index, question) in questions.enumerated() {
            if earlyEndRequested { break }
            let isLast = index == questions.count - 1
            update {
                $0.phase = .asking
                $0.questionNumber = index + 1
                $0.currentQuestion = question.text
                $0.isFollowUp = false
            }

            attention.beginSegment()
            try await say(.interviewer, script.transition(index: index, total: questions.count) + " " + question.text)
            let listeningAttention = attention.endSegment()

            attention.beginSegment()
            let utterance = try await listenAllowingRepeats(of: question.text)
            let answeringAttention = attention.endSegment()

            var record = AnswerRecord(
                index: index,
                question: question,
                utterance: utterance,
                metrics: SpeechAnalyzer.analyze(utterance),
                attentionWhileListening: listeningAttention,
                attentionWhileAnswering: answeringAttention
            )
            guard !earlyEndRequested else {
                answers.append(record)
                break
            }

            update { $0.phase = .reacting }
            let canFollowUp = followUpsAsked < configuration.maxFollowUps && !utterance.isEmpty
            let response = await interviewerResponse(to: question, answer: utterance, metrics: record.metrics, allowFollowUp: canFollowUp)

            if let followUp = response.followUp {
                followUpsAsked += 1
                update {
                    $0.phase = .asking
                    $0.currentQuestion = followUp
                    $0.isFollowUp = true
                }
                attention.beginSegment()
                let nod = cue(.interviewerNods)
                try await say(.interviewer, [response.acknowledgement, followUp].compactMap { $0 }.joined(separator: " "))
                await nod.value
                let reply = try await listenAllowingRepeats(of: followUp)
                record.followUp = FollowUpExchange(question: followUp, utterance: reply, metrics: SpeechAnalyzer.analyze(reply), attention: attention.endSegment())
                answers.append(record)
                if !isLast, !earlyEndRequested {
                    update {
                        $0.phase = .reacting
                        $0.isFollowUp = false
                    }
                    try await say(.interviewer, reply.isEmpty ? script.emptyAnswerReaction() : script.followUpThanks())
                }
            } else {
                answers.append(record)
                if !isLast {
                    let nod = cue(.interviewerNods)
                    try await say(.interviewer, response.acknowledgement ?? script.cannedReaction())
                    await nod.value
                }
            }
        }
    }

    /// Listens for an answer, re-asking the question if the candidate asks for a repeat.
    private func listenAllowingRepeats(of questionText: String) async throws -> Utterance {
        update { $0.phase = .answering }
        var utterance = try await listen(.answer)
        var repeats = 0
        while repeats < 2, !earlyEndRequested, repeatRequested || ResponseInterpreter.isRepeatRequest(utterance.text) {
            let replyWasOnlyARequest = ResponseInterpreter.isRepeatRequest(utterance.text)
            repeatRequested = false
            repeats += 1
            update { $0.phase = .asking }
            try await say(.interviewer, script.repeatPreface() + questionText)
            update { $0.phase = .answering }
            let next = try await listen(.answer)
            utterance = replyWasOnlyARequest ? next : utterance.appending(next)
        }
        repeatRequested = false
        return utterance.replacingText(ResponseInterpreter.strippingFinishCue(from: utterance.text).text)
    }

    private struct Response {
        var acknowledgement: String?
        var followUp: String?
    }

    /// The AI's acknowledgement and follow-up when available; otherwise on-device rules decide on a follow-up.
    private func interviewerResponse(to question: InterviewQuestion, answer: Utterance, metrics: SpeechMetrics, allowFollowUp: Bool) async -> Response {
        if answer.isEmpty {
            return Response(acknowledgement: script.emptyAnswerReaction())
        }
        if configuration.usesAIReactions, let generator = reactionGenerator {
            let position = state.position ?? Self.defaultPosition
            let text = answer.text
            let reaction = try? await withTimeout(seconds: 5) {
                try await generator.reaction(to: question, answer: text, position: position, allowFollowUp: allowFollowUp)
            }
            if let reaction {
                return Response(acknowledgement: reaction.acknowledgement.nilIfBlank, followUp: allowFollowUp ? reaction.followUp?.nilIfBlank : nil)
            }
        }
        guard allowFollowUp, let reason = FollowUpAdvisor.reason(for: question, answer: answer.text, metrics: metrics) else {
            return Response()
        }
        return Response(followUp: script.followUpQuestion(for: reason))
    }

    /// "Do you have any questions for me?" — answers up to two of the candidate's questions.
    private func inviteCandidateQuestions() async throws {
        guard configuration.invitesCandidateQuestions, !earlyEndRequested, !answers.isEmpty else { return }
        candidateQuestionsInvited = true
        update {
            $0.phase = .candidateQuestions
            $0.currentQuestion = nil
            $0.questionNumber = nil
            $0.isFollowUp = false
        }
        try await say(.interviewer, script.inviteQuestions())
        for round in 0..<2 {
            let reply = try await listen(.candidateQuestion)
            if earlyEndRequested { return }
            let text = ResponseInterpreter.strippingFinishCue(from: reply.text).text
            guard ResponseInterpreter.asksQuestion(text) else {
                if round == 0 { try await say(.interviewer, script.noQuestionsResponse()) }
                return
            }
            candidateQuestions.append(text)
            let nod = cue(.interviewerNods)
            let answer = await answerToCandidate(text)
            try await say(.interviewer, answer)
            await nod.value
            if round == 0 {
                try await say(.interviewer, script.anythingElse())
            }
        }
    }

    private func answerToCandidate(_ question: String) async -> String {
        if configuration.usesAIReactions, let generator = reactionGenerator {
            let position = state.position ?? Self.defaultPosition
            let company = configuration.companyName
            if let answer = try? await withTimeout(seconds: 8, operation: {
                try await generator.answer(candidateQuestion: question, position: position, companyName: company)
            }), let line = answer.nilIfBlank {
                return line
            }
        }
        return script.answer(toCandidateQuestion: question)
    }

    /// True when the candidate stopped before every question had been asked.
    private var endedBeforeLastQuestion: Bool {
        earlyEndRequested && answers.count < plannedQuestionCount
    }

    private func close() async throws {
        update {
            $0.phase = .closing
            $0.currentQuestion = nil
            $0.isFollowUp = false
        }
        let line = endedBeforeLastQuestion ? script.endedEarlyClosing() : candidateQuestionsInvited ? script.closingAfterQuestions() : script.closing()
        try await say(.interviewer, line)
        try await perform(.interviewerStands)
        try await perform(.exitOffice)
    }

    private func analyze() async -> InterviewReport? {
        let overallAttention = attention.stopTracking()
        guard !answers.isEmpty else {
            update { $0.phase = .finished }
            return nil
        }
        update {
            $0.phase = .analyzing
            $0.currentSpeaker = nil
            $0.isListening = false
        }
        let record = InterviewRecord(
            candidate: candidate,
            position: state.position ?? Self.defaultPosition,
            configuration: configuration,
            plannedQuestionCount: max(plannedQuestionCount, answers.count),
            answers: answers,
            overallAttention: overallAttention,
            startedAt: startedAt,
            endedAt: now(),
            endedEarly: endedBeforeLastQuestion,
            candidateQuestionsInvited: candidateQuestionsInvited,
            candidateQuestions: candidateQuestions
        )
        let report: InterviewReport
        do {
            report = try await evaluator.evaluate(record)
        } catch {
            report = fallbackEvaluator.makeReport(for: record, notes: ["AI analysis failed, so this report uses on-device analysis."])
        }
        update { $0.phase = .finished }
        return report
    }

    // MARK: Questions

    private func startGeneratingQuestions(for position: String) {
        questionTask?.cancel()
        questionsReady = false
        let request = QuestionRequest(
            position: position,
            count: configuration.questionCount,
            difficulty: configuration.difficulty,
            focus: configuration.focus
        )
        let generator = questionGenerator
        let bank = questionBank
        questionTask = Task { [weak self] in
            var questions: [InterviewQuestion] = []
            if let generated = try? await generator.generateQuestions(for: request) {
                questions = generated.filter { !$0.text.trimmed.isEmpty }
            }
            questions = questions.isEmpty ? bank.questions(for: request) : bank.padding(questions, toMatch: request)
            self?.questionsReady = true
            return questions
        }
    }

    // MARK: Helpers

    private func update(_ change: (inout InterviewState) -> Void) {
        var copy = state
        change(&copy)
        state = copy
    }

    private func say(_ speaker: Speaker, _ text: String) async throws {
        try Task.checkCancellation()
        let line = text.trimmed
        guard !line.isEmpty else { return }
        update {
            $0.currentSpeaker = speaker
            $0.caption = line
            $0.captionSpeaker = speaker
            $0.conversation.append(TranscriptEntry(speaker: speaker, text: line, timestamp: now()))
        }
        await voice.speak(line, as: speaker)
        update { $0.currentSpeaker = nil }
        try Task.checkCancellation()
    }

    private func listen(_ purpose: ListenPurpose) async throws -> Utterance {
        try Task.checkCancellation()
        let request: ListenRequest = switch purpose {
        case .answer:
            ListenRequest(purpose: purpose, startTimeout: configuration.answerStartTimeout, silenceTimeout: configuration.answerSilenceTimeout, allowsFinishCue: true)
        case .candidateQuestion:
            ListenRequest(purpose: purpose, startTimeout: min(configuration.answerStartTimeout, 12), silenceTimeout: configuration.answerSilenceTimeout, allowsFinishCue: true)
        case .position, .readiness:
            ListenRequest(purpose: purpose, startTimeout: configuration.shortReplyStartTimeout, silenceTimeout: configuration.shortReplySilenceTimeout, allowsFinishCue: false)
        }
        update {
            $0.isListening = true
            $0.listeningPurpose = purpose
            $0.liveTranscript = ""
        }
        defer {
            update {
                $0.isListening = false
                $0.listeningPurpose = nil
            }
        }
        let utterance = try await input.listen(request) { [weak self] partial in
            self?.update { $0.liveTranscript = partial }
        }
        try Task.checkCancellation()
        if !utterance.isEmpty {
            update { $0.conversation.append(TranscriptEntry(speaker: .candidate, text: utterance.text, timestamp: now())) }
        }
        return utterance
    }

    /// Starts a stage cue without waiting for it.
    private func cue(_ cue: StageCue) -> Task<Void, Never> {
        let stage = stage
        return Task { await stage.perform(cue) }
    }

    /// Runs a stage cue to completion, abandoning it if the interview is cancelled.
    private func perform(_ cue: StageCue) async throws {
        try await wait(for: self.cue(cue))
    }

    private func wait(for task: Task<Void, Never>) async throws {
        await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
        try Task.checkCancellation()
    }
}
