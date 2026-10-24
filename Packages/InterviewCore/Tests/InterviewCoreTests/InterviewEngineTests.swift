import XCTest
@testable import InterviewCore

@MainActor
final class InterviewEngineTests: XCTestCase {
    private var voice: RecordingVoice!
    private var stage: RecordingStage!
    private var attention: FakeAttention!

    override func setUp() async throws {
        voice = RecordingVoice()
        stage = RecordingStage()
        attention = FakeAttention()
    }

    private func makeEngine(
        input: ScriptedInput,
        configuration: InterviewConfiguration = InterviewConfiguration(questionCount: 3),
        questions: QuestionGenerating = FixedQuestions(questions: Fixtures.questions),
        reaction: ReactionGenerating? = FixedReaction(line: "Thanks, that's a useful detail."),
        evaluator: InterviewEvaluating = HeuristicEvaluator()
    ) -> InterviewEngine {
        InterviewEngine(
            candidate: Fixtures.candidate,
            configuration: configuration,
            voice: voice,
            input: input,
            stage: stage,
            attention: attention,
            questionGenerator: questions,
            reactionGenerator: reaction,
            evaluator: evaluator,
            seed: 1,
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )
    }

    func testFullInterviewFromReceptionToReport() async throws {
        let input = ScriptedInput([
            .say("I'm applying for a Technical Mechanic."),
            .say("Yes, I'm ready."),
            .say(Fixtures.strongAnswer + " That's my answer."),
            .say("I enjoy diagnosing problems and I work well with a team, for example on our weekend rota."),
            .say("Leading a workshop team. I'm done."),
        ])
        let engine = makeEngine(input: input)
        var phases: [InterviewPhase] = []
        engine.onStateChange = { state in
            if phases.last != state.phase { phases.append(state.phase) }
        }

        let maybeReport = await engine.run()
        let report = try XCTUnwrap(maybeReport)

        XCTAssertEqual(report.position, "Technical Mechanic")
        XCTAssertEqual(report.questions.count, 3)
        XCTAssertEqual(report.questions[0].answer, Fixtures.strongAnswer, "the spoken finish cue is removed")
        XCTAssertEqual(report.questions[2].answer, "Leading a workshop team.")
        XCTAssertTrue(report.eyeContact.isAvailable)
        XCTAssertEqual(engine.state.phase, .finished)

        XCTAssertEqual(input.requests.map(\.purpose), [.position, .readiness, .answer, .answer, .answer])
        XCTAssertTrue(input.requests[2].allowsFinishCue)
        XCTAssertFalse(input.requests[0].allowsFinishCue)

        let receptionist = voice.lines(by: .receptionist)
        XCTAssertTrue(receptionist.contains("What position are you applying for today, Ms. Rivera?"))
        XCTAssertTrue(receptionist.contains { $0.hasPrefix("Oh, I see your appointment right here: Technical Mechanic, with Daniel Park.") })

        let interviewer = voice.lines(by: .interviewer)
        XCTAssertTrue(interviewer.contains("Are you ready to begin, Ms. Rivera?"))
        for question in Fixtures.questions {
            XCTAssertTrue(interviewer.contains { $0.hasSuffix(question.text) }, question.text)
        }
        XCTAssertEqual(interviewer.filter { $0 == "Thanks, that's a useful detail." }.count, 2, "a reaction follows every answer but the last")
        XCTAssertTrue(interviewer.last?.hasPrefix("That's all the questions I have for today.") ?? false)

        for cue in [StageCue.enterReception, .walkToInterviewRoom, .interviewerStands, .focusOnInterviewer, .exitOffice] {
            XCTAssertTrue(stage.cues.contains(cue), "\(cue)")
        }
        XCTAssertLessThan(stage.cues.firstIndex(of: .walkToInterviewRoom)!, stage.cues.firstIndex(of: .focusOnInterviewer)!)
        XCTAssertTrue(attention.started)
        XCTAssertEqual(attention.segments, 6, "one listening and one answering segment per question")

        let order: [InterviewPhase] = [.reception, .walking, .meetingInterviewer, .waitingForReady, .preparingQuestions, .asking, .answering, .reacting, .closing, .analyzing, .finished]
        XCTAssertEqual(phases.filter(order.contains).reduce(into: [InterviewPhase]()) { if !$0.contains($1) { $0.append($1) } }, order)
        XCTAssertEqual(engine.state.conversation.filter { $0.speaker == .candidate }.count, 5)
    }

    func testFallsBackToPresetPositionAndHandlesNotReady() async throws {
        let input = ScriptedInput([
            .say("Sorry?"), .silence, .say("what"),
            .say("Not yet, give me a second."),
            .say("Okay, I'm ready now."),
            .say("Answer one"), .say("Answer two"), .say("Answer three"),
        ])
        let engine = makeEngine(input: input, configuration: InterviewConfiguration(questionCount: 3, presetPosition: "Welder"))
        let maybeReport = await engine.run()
        let report = try XCTUnwrap(maybeReport)

        XCTAssertEqual(report.position, "Welder")
        let receptionist = voice.lines(by: .receptionist)
        XCTAssertEqual(receptionist.filter { $0.contains("position") || $0.contains("job title") }.count, 3, "asks up to three times")
        XCTAssertTrue(receptionist.contains { $0.hasPrefix("No problem. I have you down for the Welder interview") })
        let interviewer = voice.lines(by: .interviewer)
        XCTAssertTrue(interviewer.contains("Of course, take your time. Just let me know when you're ready."))
        XCTAssertEqual(interviewer.filter { $0.hasPrefix("Are you ready") }.count, 1, "doesn't nag after the candidate asks for a moment")
    }

    func testRepeatRequestsReaskTheQuestion() async throws {
        var engine: InterviewEngine!
        let input = ScriptedInput([
            .say("A mechanic position"),
            .say("Yes"),
            .say("Could you repeat the question?"),
            .say("I trained as a mechanic for four years."),
            .action({ engine.requestRepeat() }, then: "I once fixed"),
            .say("a hydraulic leak on a crane and it saved the client 2 days of downtime."),
            .say("Running my own shop."),
        ])
        engine = makeEngine(input: input)
        let maybeReport = await engine.run()
        let report = try XCTUnwrap(maybeReport)

        XCTAssertEqual(report.position, "Mechanic")
        XCTAssertEqual(report.questions[0].answer, "I trained as a mechanic for four years.", "a pure repeat request is discarded")
        XCTAssertEqual(report.questions[1].answer, "I once fixed a hydraulic leak on a crane and it saved the client 2 days of downtime.", "a partial answer is kept and continued")
        let repeats = voice.lines(by: .interviewer).filter { $0.hasPrefix("Of course. ") }
        XCTAssertEqual(repeats, ["Of course. " + Fixtures.questions[0].text, "Of course. " + Fixtures.questions[1].text])
    }

    func testEndingEarlySkipsRemainingQuestions() async throws {
        var engine: InterviewEngine!
        let input = ScriptedInput([
            .say("Data analyst"),
            .say("Ready"),
            .say("I love data."),
            .action({ engine.endEarly() }, then: "I'd like to stop here."),
        ])
        engine = makeEngine(input: input)
        let maybeReport = await engine.run()
        let report = try XCTUnwrap(maybeReport)

        XCTAssertTrue(report.endedEarly)
        XCTAssertEqual(report.questions.count, 2)
        XCTAssertTrue(voice.lines(by: .interviewer).last?.hasPrefix("Understood, let's stop here.") ?? false)
        XCTAssertFalse(voice.lines(by: .interviewer).contains { $0.hasSuffix(Fixtures.questions[2].text) })
    }

    func testCancellationReturnsNoReport() async {
        let engine = makeEngine(input: ScriptedInput([]))
        let task = Task { await engine.run() }
        task.cancel()
        let report = await task.value
        XCTAssertNil(report)
        XCTAssertEqual(engine.state.phase, .cancelled)
        XCTAssertFalse(engine.hasAnswers)
    }

    func testQuestionGenerationFailureUsesBuiltInBank() async throws {
        let input = ScriptedInput([.say("Chef"), .say("Yes"), .say("A"), .say("B"), .say("C"), .say("D")])
        let engine = makeEngine(input: input, configuration: InterviewConfiguration(questionCount: 4), questions: FailingQuestions(), reaction: nil)
        let maybeReport = await engine.run()
        let report = try XCTUnwrap(maybeReport)
        XCTAssertEqual(report.questions.count, 4)
        XCTAssertEqual(report.questions.first?.category, .opener)
        XCTAssertTrue(report.questions.first?.question.contains("Chef") ?? false)
    }

    func testBlankAIReactionFallsBackToCannedLine() async throws {
        let input = ScriptedInput([.say("Chef"), .say("Yes"), .say("First answer"), .silence, .say("Third")])
        let engine = makeEngine(input: input, reaction: FixedReaction(line: "   "))
        let maybeReport = await engine.run()
        let report = try XCTUnwrap(maybeReport)
        let interviewer = voice.lines(by: .interviewer)
        XCTAssertFalse(interviewer.contains("   "))
        XCTAssertTrue(interviewer.contains("That's all right, let's move on."), "silence gets a gentle move-on line")
        XCTAssertEqual(report.questions[1].score, 0)
    }

    func testEvaluatorFailureStillProducesReport() async throws {
        struct Broken: InterviewEvaluating {
            func evaluate(_ record: InterviewRecord) async throws -> InterviewReport { throw OpenAIError.invalidResponse }
        }
        let input = ScriptedInput([.say("Chef"), .say("Yes"), .say("A"), .say("B"), .say("C")])
        let engine = makeEngine(input: input, evaluator: Broken())
        let maybeReport = await engine.run()
        let report = try XCTUnwrap(maybeReport)
        XCTAssertEqual(report.analysisSource, .onDevice)
        XCTAssertFalse(report.notes.isEmpty)
    }
}
