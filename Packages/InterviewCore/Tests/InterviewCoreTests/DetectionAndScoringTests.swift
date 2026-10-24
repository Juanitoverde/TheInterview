import XCTest
@testable import InterviewCore

final class EndOfTurnDetectorTests: XCTestCase {
    private let longAnswer = Array(repeating: "I checked the wiring", count: 8).joined(separator: " ")

    func testWaitsLongerWhenTrailingOff() {
        XCTAssertEqual(EndOfTurnDetector.silenceNeeded(after: "I'd start with the brakes and", base: 5, isAnswer: true), 7.5, accuracy: 0.001)
        XCTAssertEqual(EndOfTurnDetector.silenceNeeded(after: "That's a good question, let me think", base: 5, isAnswer: true), 9, accuracy: 0.001)
        XCTAssertEqual(EndOfTurnDetector.silenceNeeded(after: "So, um", base: 5, isAnswer: true), 9, accuracy: 0.001)
    }

    func testMovesOnSoonerAfterAFinishedSubstantialAnswer() {
        XCTAssertEqual(EndOfTurnDetector.silenceNeeded(after: longAnswer + ".", base: 5, isAnswer: true), 3.5, accuracy: 0.001)
        // A single finished sentence early in an answer keeps the normal wait.
        XCTAssertEqual(EndOfTurnDetector.silenceNeeded(after: "I trained as a mechanic.", base: 5, isAnswer: true), 5, accuracy: 0.001)
        // Short replies ("Yes.") end quickly but never below the floor.
        XCTAssertEqual(EndOfTurnDetector.silenceNeeded(after: "Yes.", base: 1.6, isAnswer: false), 1.2, accuracy: 0.001)
        XCTAssertEqual(EndOfTurnDetector.silenceNeeded(after: "", base: 5, isAnswer: true), 5)
    }
}

final class ProsodyTests: XCTestCase {
    func testMeasuresPausesWithinEachStretch() {
        let first = [WordTiming(start: 0, duration: 0.4), WordTiming(start: 0.5, duration: 0.3), WordTiming(start: 3.0, duration: 0.5)]
        let second = [WordTiming(start: 0.2, duration: 0.3), WordTiming(start: 0.6, duration: 0.4), WordTiming(start: 4.0, duration: 0.5)]
        let prosody = try! XCTUnwrap(ProsodyAnalyzer.analyze([first, second, []]))
        XCTAssertEqual(prosody.longPauseCount, 2)
        XCTAssertEqual(prosody.longestPause, 3.0, accuracy: 0.001)
        XCTAssertEqual(prosody.speakingSeconds, 3.5 + 4.3, accuracy: 0.001)
        XCTAssertNil(ProsodyAnalyzer.analyze([]))
    }

    func testWordTimingsGiveAccuratePace() {
        let start = Date(timeIntervalSince1970: 0)
        let utterance = Utterance(
            text: Array(repeating: "word", count: 60).joined(separator: " "),
            method: .voice, startedAt: start, endedAt: start.addingTimeInterval(90),
            speechStartedAt: start, speechEndedAt: start.addingTimeInterval(80),
            prosody: Prosody(longPauseCount: 1, longestPause: 2.5, speakingSeconds: 30)
        )
        XCTAssertEqual(SpeechAnalyzer.analyze(utterance).wordsPerMinute ?? 0, 120, accuracy: 0.001)
    }
}

final class CandidateQuestionDetectionTests: XCTestCase {
    func testDistinguishesQuestionsFromPoliteDeclines() {
        for question in ["What does a typical day look like?", "Um, how big is the team", "Yes, I was wondering about training opportunities for new starters",
                         "No, but what are the next steps?"] {
            XCTAssertTrue(ResponseInterpreter.asksQuestion(question), question)
        }
        for decline in ["No.", "Not really, thanks.", "No, I think you've covered everything.", "Thank you, I think that covers it.",
                        "I'm all set", "I don't have any questions right now", ""] {
            XCTAssertFalse(ResponseInterpreter.asksQuestion(decline), decline)
        }
    }

    func testMorePositionPhrasings() {
        XCTAssertEqual(ResponseInterpreter.extractPosition(from: "I'm here about the accounts payable job"), "Accounts Payable")
        XCTAssertEqual(ResponseInterpreter.extractPosition(from: "It's for the warehouse supervisor opening."), "Warehouse Supervisor")
        XCTAssertEqual(ResponseInterpreter.extractPosition(from: "I'm interviewing to be a dental hygienist"), "Dental Hygienist")
        XCTAssertEqual(ResponseInterpreter.extractPosition(from: "IT support"), "IT Support")
    }
}

final class ScoringTests: XCTestCase {
    private let evaluator = HeuristicEvaluator()

    func testFlagsTeamCreditNegativityUncertaintyAndRepetition() {
        let teamOnly = "At our last company we had a broken conveyor, so we got together and we fixed it, and we were really proud of how our team handled it in the end, as a result we saved time."
        XCTAssertTrue(evaluator.feedback(for: Fixtures.answerRecord(teamOnly), position: "Mechanic").feedback.contains("\"we\""))

        let negative = "My last boss was incompetent and the place was toxic, so honestly I left because I hated it there, but I learned to keep working hard."
        let negativeFeedback = evaluator.feedback(for: Fixtures.answerRecord(negative, category: .motivation), position: "Mechanic")
        XCTAssertTrue(negativeFeedback.feedback.contains("negative"), negativeFeedback.feedback)

        let unsure = "Um, I don't know, I guess I would probably just look at the engine and see what happens with it and then decide."
        XCTAssertTrue(evaluator.feedback(for: Fixtures.answerRecord(unsure, category: .technical), position: "Mechanic").suggestion.contains("Let me think about that"))

        XCTAssertGreaterThan(HeuristicEvaluator.repetitionRatio(TextTools.words(in: "I fixed the car and I fixed the car and I fixed the car again")), 0.3)
        XCTAssertEqual(HeuristicEvaluator.repetitionRatio(TextTools.words(in: Fixtures.strongAnswer)), 0, accuracy: 0.05)
        XCTAssertEqual(HeuristicEvaluator.ownership(in: "I led it but we shipped it with our team").i, 1)
    }

    func testDeliveryScoreAndBreakdown() {
        XCTAssertEqual(HeuristicEvaluator.deliveryScore(words: 300, wordsPerMinute: 140, fillers: 2, hedges: 1, prosody: nil), 100)
        XCTAssertEqual(HeuristicEvaluator.deliveryScore(words: 300, wordsPerMinute: 200, fillers: 30, hedges: 15, prosody: Prosody(longPauseCount: 6, longestPause: 5, speakingSeconds: 120)), 25)
        XCTAssertNil(HeuristicEvaluator.deliveryScore(words: 0, wordsPerMinute: nil, fillers: 0, hedges: 0, prosody: nil))

        XCTAssertEqual(ScoreBreakdown(content: 80, delivery: 60, eyeContact: 40).overall, 71)
        XCTAssertEqual(ScoreBreakdown(content: 80, delivery: nil, eyeContact: nil).overall, 80)
        XCTAssertEqual(ScoreBreakdown(content: 80, delivery: 60, eyeContact: nil).overall, 76)

        let report = evaluator.makeReport(for: Fixtures.record(answers: [Fixtures.answerRecord(Fixtures.strongAnswer)]))
        let breakdown = try! XCTUnwrap(report.breakdown)
        XCTAssertEqual(report.overallScore, breakdown.overall)
        XCTAssertNil(breakdown.eyeContact)
        XCTAssertNotNil(breakdown.delivery)
        XCTAssertTrue(report.plainText.contains("Breakdown: answers"))
    }

    func testAIContentScoreKeepsMeasuredParts() async throws {
        let ai = #"{"contentScore": 90, "summary": "Good.", "questions": []}"#
        let transport = MockTransport([(200, MockTransport.chat(ai))])
        let evaluator = AIEvaluator(client: OpenAIClient(apiKey: "sk", transport: transport))
        var record = Fixtures.record(answers: [Fixtures.answerRecord(Fixtures.strongAnswer)], attention: AttentionSummary(
            sampleCount: 100, trackedSeconds: 60, engagedRatio: 0.5, lookAwayCount: 2, longestLookAwaySeconds: 3, averageDeviationDegrees: 20))
        record.candidateQuestionsInvited = true
        record.candidateQuestions = ["What does success look like in the first year?"]
        let report = try await evaluator.evaluate(record)
        let breakdown = try XCTUnwrap(report.breakdown)
        XCTAssertEqual(breakdown.content, 90)
        XCTAssertEqual(report.overallScore, breakdown.overall)
        XCTAssertEqual(breakdown.eyeContact, report.eyeContact.score)
        XCTAssertEqual(report.candidateQuestions, ["What does success look like in the first year?"])
        let body = try XCTUnwrap(transport.requests.first?.httpBody).flatMap { String(data: $0, encoding: .utf8) } ?? ""
        XCTAssertTrue(body.contains("What does success look like"), "the candidate's questions are sent for evaluation")
        XCTAssertTrue(body.contains("Most good answers are 6-8"), "the rubric is included")
    }
}
