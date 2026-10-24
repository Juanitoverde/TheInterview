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
        configuration: InterviewConfiguration = InterviewConfiguration(questionCount: 3, maxFollowUps: 0, invitesCandidateQuestions: false),
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
        let engine = makeEngine(input: input, configuration: InterviewConfiguration(questionCount: 3, presetPosition: "Welder", maxFollowUps: 0, invitesCandidateQuestions: false))
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
        let engine = makeEngine(input: input, configuration: InterviewConfiguration(questionCount: 4, maxFollowUps: 0, invitesCandidateQuestions: false), questions: FailingQuestions(), reaction: nil)
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

    // MARK: Follow-ups

    func testAIFollowUpIsAskedRecordedAndCapped() async throws {
        let input = ScriptedInput([
            .say("Mechanic"), .say("Yes"),
            .say("I like engines."),
            .say("I rebuilt a gearbox for a delivery van and it ran for another 80,000 miles."),
            .say("Second answer"),
            .say("Third answer"),
        ])
        let engine = makeEngine(
            input: input,
            configuration: InterviewConfiguration(questionCount: 3, maxFollowUps: 1, invitesCandidateQuestions: false),
            reaction: FixedReaction(line: "Thanks.", followUp: "What's the hardest repair you've done?")
        )
        let maybeReport = await engine.run()
        let report = try XCTUnwrap(maybeReport)

        let interviewer = voice.lines(by: .interviewer)
        XCTAssertEqual(interviewer.filter { $0.hasSuffix("What's the hardest repair you've done?") }, ["Thanks. What's the hardest repair you've done?"],
                       "only one follow-up is allowed")
        XCTAssertEqual(input.requests.map(\.purpose), [.position, .readiness, .answer, .answer, .answer, .answer])
        XCTAssertEqual(report.questions[0].followUpQuestion, "What's the hardest repair you've done?")
        XCTAssertEqual(report.questions[0].followUpAnswer, "I rebuilt a gearbox for a delivery van and it ran for another 80,000 miles.")
        XCTAssertNil(report.questions[1].followUpQuestion)
        XCTAssertEqual(report.questions[0].metrics.wordCount, 3 + 15, "follow-up words count toward the answer")
    }

    func testOfflineFollowUpProbesBriefAnswers() async throws {
        let input = ScriptedInput([
            .say("Mechanic"), .say("Yes"),
            .say("Cars."),
            .say("I've worked on cars since I was sixteen and I trained at the city technical college for two years."),
            .say(Fixtures.strongAnswer),
            .say("Running my own workshop one day, with a team of three or four mechanics, focusing on electric vehicle repairs."),
        ])
        let engine = makeEngine(input: input, configuration: InterviewConfiguration(questionCount: 3, maxFollowUps: 2, invitesCandidateQuestions: false), reaction: nil)
        let maybeReport = await engine.run()
        let report = try XCTUnwrap(maybeReport)

        XCTAssertNotNil(report.questions[0].followUpQuestion, "a one-word answer gets probed")
        XCTAssertNil(report.questions[1].followUpQuestion, "a full STAR answer with a result needs no follow-up")
        XCTAssertNil(report.questions[2].followUpQuestion)
        XCTAssertEqual(input.requests.filter { $0.purpose == .answer }.count, 4)
    }

    func testFollowUpsCanBeTurnedOff() async throws {
        let input = ScriptedInput([.say("Chef"), .say("Yes"), .say("Food."), .say("Pasta."), .say("Soon.")])
        let engine = makeEngine(input: input, configuration: InterviewConfiguration(questionCount: 3, maxFollowUps: 0, invitesCandidateQuestions: false),
                                reaction: FixedReaction(line: "Okay.", followUp: "Why?"))
        let maybeReport = await engine.run()
        let report = try XCTUnwrap(maybeReport)
        XCTAssertTrue(report.questions.allSatisfy { $0.followUpQuestion == nil })
        XCTAssertFalse(voice.lines(by: .interviewer).contains { $0.contains("Why?") })
    }

    // MARK: Candidate questions

    func testInterviewerAnswersCandidateQuestions() async throws {
        let input = ScriptedInput([
            .say("Mechanic"), .say("Yes"), .say("A"), .say("B"), .say("C"),
            .say("What does a typical day look like for the team?"),
            .say("No, I think you've covered everything, thank you."),
        ])
        let engine = makeEngine(
            input: input,
            configuration: InterviewConfiguration(questionCount: 3, maxFollowUps: 0, invitesCandidateQuestions: true),
            reaction: FixedReaction(line: "Thanks.")
        )
        let maybeReport = await engine.run()
        let report = try XCTUnwrap(maybeReport)

        let interviewer = voice.lines(by: .interviewer)
        XCTAssertTrue(interviewer.contains("Before we wrap up, do you have any questions for me?"))
        XCTAssertTrue(interviewer.contains("Great question. The team is small and friendly."))
        XCTAssertTrue(interviewer.contains { $0.hasPrefix("Is there anything else") || $0.hasPrefix("Anything else") })
        XCTAssertTrue(interviewer.last?.hasPrefix("Thank you for your time today") ?? false)
        XCTAssertEqual(report.candidateQuestions, ["What does a typical day look like for the team?"])
        XCTAssertEqual(input.requests.filter { $0.purpose == .candidateQuestion }.count, 2)
        XCTAssertTrue(report.strengths.contains("You asked the interviewer thoughtful questions at the end."))
    }

    func testOfflineAnswerAndNoQuestions() async throws {
        // Substantive answers, so the four-item improvements list has room for the note about questions.
        let declining = ScriptedInput([.say("Chef"), .say("Yes"), .say(Fixtures.strongAnswer), .say(Fixtures.strongAnswer), .say(Fixtures.strongAnswer), .say("No, I'm good, thanks.")])
        let engine = makeEngine(input: declining, configuration: InterviewConfiguration(questionCount: 3, maxFollowUps: 0, invitesCandidateQuestions: true), reaction: nil)
        let maybeReport = await engine.run()
        let report = try XCTUnwrap(maybeReport)
        XCTAssertEqual(report.candidateQuestions, [])
        XCTAssertTrue(voice.lines(by: .interviewer).contains("No problem at all."))
        XCTAssertTrue(report.improvements.contains { $0.hasPrefix("Prepare one or two questions") })

        let script = InterviewScript(candidate: Fixtures.candidate, configuration: InterviewConfiguration(), seed: 1)
        XCTAssertTrue(script.answer(toCandidateQuestion: "When will I hear back about next steps?").contains("next steps"))
        XCTAssertTrue(script.answer(toCandidateQuestion: "What's the salary range?").contains("HR"))
        XCTAssertTrue(script.answer(toCandidateQuestion: "Is there training for new starters?").contains("development"))
    }
}
