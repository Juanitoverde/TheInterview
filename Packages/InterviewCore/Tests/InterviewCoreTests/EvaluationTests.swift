import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import InterviewCore

final class HeuristicEvaluatorTests: XCTestCase {
    func testStrongAnswerOutscoresWeakAndEmpty() {
        let evaluator = HeuristicEvaluator()
        let strong = evaluator.feedback(for: Fixtures.answerRecord(Fixtures.strongAnswer, seconds: 45), position: "Technical Mechanic")
        let weak = evaluator.feedback(for: Fixtures.answerRecord("Um, I fixed it I guess. It was, like, fine.", seconds: 6), position: "Technical Mechanic")
        let empty = evaluator.feedback(for: Fixtures.answerRecord("", seconds: 0), position: "Technical Mechanic")

        XCTAssertGreaterThanOrEqual(strong.score, 8)
        XCTAssertLessThan(weak.score, strong.score)
        XCTAssertLessThanOrEqual(weak.score, 6)
        XCTAssertEqual(empty.score, 0)
        XCTAssertEqual(empty.feedback, "No answer was captured for this question.")
        XCTAssertTrue(weak.feedback.contains("brief"))
        XCTAssertGreaterThanOrEqual(HeuristicEvaluator.starComponents(in: Fixtures.strongAnswer), 3)
    }

    func testFollowUpReplyCountsTowardTheScore() {
        let evaluator = HeuristicEvaluator()
        let brief = Fixtures.answerRecord("I fixed a truck once.", seconds: 4)
        var withFollowUp = brief
        let reply = Fixtures.answerRecord(Fixtures.strongAnswer, seconds: 45)
        withFollowUp.followUp = FollowUpExchange(question: "Can you walk me through it?", utterance: reply.utterance, metrics: reply.metrics, attention: .unavailable)

        let before = evaluator.feedback(for: brief, position: "Technical Mechanic")
        let after = evaluator.feedback(for: withFollowUp, position: "Technical Mechanic")
        XCTAssertGreaterThan(after.score, before.score)
        XCTAssertEqual(after.answer, "I fixed a truck once.")
        XCTAssertEqual(after.followUpQuestion, "Can you walk me through it?")
        XCTAssertTrue(after.fullAnswer.hasSuffix("about 30 percent."))
        XCTAssertTrue(HeuristicEvaluator().makeReport(for: Fixtures.record(answers: [withFollowUp])).plainText.contains("Follow-up: Can you walk me through it?"))
    }

    func testReportAggregatesAndMentionsWorstCategoryForEyeContact() {
        var technical = Fixtures.answerRecord(Fixtures.strongAnswer, category: .technical, index: 0)
        technical.attentionWhileAnswering = AttentionSummary(sampleCount: 100, trackedSeconds: 30, engagedRatio: 0.3, lookAwayCount: 4, longestLookAwaySeconds: 6, averageDeviationDegrees: 25)
        var behavioral = Fixtures.answerRecord(Fixtures.strongAnswer, category: .behavioral, index: 1)
        behavioral.attentionWhileAnswering = AttentionSummary(sampleCount: 100, trackedSeconds: 30, engagedRatio: 0.95, lookAwayCount: 0, longestLookAwaySeconds: 0, averageDeviationDegrees: 5)
        let overall = AttentionSummary(sampleCount: 200, trackedSeconds: 60, engagedRatio: 0.625, lookAwayCount: 4, longestLookAwaySeconds: 6, averageDeviationDegrees: 15)

        let report = HeuristicEvaluator().makeReport(for: Fixtures.record(answers: [technical, behavioral], attention: overall))

        XCTAssertEqual(report.questions.count, 2)
        XCTAssertTrue(report.eyeContact.isAvailable)
        XCTAssertEqual(report.eyeContact.engagedPercent, 63)
        XCTAssertTrue(report.eyeContact.feedback.contains("questions about technical skills"), report.eyeContact.feedback)
        XCTAssertTrue(report.eyeContact.feedback.contains("6 seconds"))
        XCTAssertEqual(report.analysisSource, .onDevice)
        XCTAssertFalse(report.strengths.isEmpty)
        XCTAssertFalse(report.improvements.isEmpty)
        XCTAssertTrue((0...100).contains(report.overallScore))
        XCTAssertTrue(report.summary.contains("Technical Mechanic"))
        XCTAssertTrue(report.plainText.contains("Overall score: \(report.overallScore)/100"))
    }

    func testEyeContactUnavailableIsExplained() {
        let report = HeuristicEvaluator().makeReport(for: Fixtures.record(answers: [Fixtures.answerRecord(Fixtures.strongAnswer)]))
        XCTAssertFalse(report.eyeContact.isAvailable)
        XCTAssertTrue(report.eyeContact.feedback.contains("wasn't available"))
    }

    func testDeliveryReportFlagsFillers() {
        let filler = "Um, so, uh, I basically, like, um, checked it and, um, it was, um, basically fine, you know, uh, yeah."
        let report = HeuristicEvaluator().makeReport(for: Fixtures.record(answers: [Fixtures.answerRecord(filler, seconds: 10)]))
        XCTAssertGreaterThan(report.delivery.fillerCount, 5)
        XCTAssertEqual(report.delivery.topFillers.first, "um")
        XCTAssertTrue(report.delivery.feedback.contains("Filler words came up"))
    }
}

final class OpenAITests: XCTestCase {
    func testRequestShape() throws {
        let client = OpenAIClient(apiKey: " sk-test ", model: "gpt-test", transport: MockTransport([]))
        let request = try client.makeRequest(system: "sys", user: "usr", timeout: 12)
        XCTAssertEqual(request.url?.absoluteString, "https://api.openai.com/v1/chat/completions")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-test")
        XCTAssertEqual(request.timeoutInterval, 12)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
        XCTAssertEqual(body["model"] as? String, "gpt-test")
        XCTAssertEqual((body["response_format"] as? [String: String])?["type"], "json_object")
        XCTAssertEqual((body["messages"] as? [[String: String]])?.map { $0["role"] ?? "" }, ["system", "user"])
        XCTAssertNil(body["temperature"])
    }

    func testMissingKeyFailsFast() async {
        let client = OpenAIClient(apiKey: "  ", transport: MockTransport([]))
        do {
            _ = try await client.completeJSON(system: "a", user: "b")
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? OpenAIError, .missingAPIKey)
        }
    }

    func testHTTPErrorMessageIsSurfaced() async {
        let transport = MockTransport([(401, #"{"error":{"message":"Incorrect API key provided"}}"#)])
        let client = OpenAIClient(apiKey: "sk", transport: transport)
        do {
            _ = try await client.completeJSON(system: "a", user: "b")
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? OpenAIError, .http(status: 401, message: "Incorrect API key provided"))
            XCTAssertTrue(error.localizedDescription.contains("401"))
        }
    }

    func testExtractsJSONFromFencedContent() {
        XCTAssertEqual(JSONText.extractObject(from: "```json\n{\"a\": 1}\n```"), "{\"a\": 1}")
        XCTAssertEqual(JSONText.extractObject(from: "{\"a\": {\"b\": 2}}"), "{\"a\": {\"b\": 2}}")
    }

    func testQuestionGeneratorParsesAndTrims() async throws {
        let content = #"{"questions":[{"text":"Tell me about yourself.","category":"opener","intent":"fit"},{"text":"  ","category":"technical"},{"text":"How do you diagnose a misfire?","category":"Technical Skills"},{"text":"Extra","category":"closing"}]}"#
        let transport = MockTransport([(200, MockTransport.chat(content))])
        let generator = AIQuestionGenerator(client: OpenAIClient(apiKey: "sk", transport: transport))
        let questions = try await generator.generateQuestions(for: QuestionRequest(position: "Mechanic", count: 2, difficulty: .entry, focus: .technical))
        XCTAssertEqual(questions.map(\.text), ["Tell me about yourself.", "How do you diagnose a misfire?"])
        XCTAssertEqual(questions.map(\.category), [.opener, .technical])
        XCTAssertEqual(questions.first?.intent, "fit")

        let prompt = try XCTUnwrap(transport.requests.first?.httpBody).flatMap { String(data: $0, encoding: .utf8) }
        XCTAssertTrue(prompt?.contains("Mechanic") ?? false)
    }

    func testEvaluatorMergesAIOntoMeasuredNumbers() async throws {
        let ai = """
        {"overallScore": "88", "summary": "Great job overall.", "strengths": ["Clear STAR story"], "improvements": ["Slow down"],
         "eyeContactFeedback": "Should be ignored: tracking unavailable", "deliveryFeedback": "Nice pace.",
         "questions": [{"index": 0, "score": "9/10", "relevance": 10, "clarity": 8, "structure": 9, "feedback": "You quantified impact.", "suggestion": "Mention safety."},
                       {"index": 1, "score": 7, "feedback": "Should be ignored: empty answer", "exampleAnswer": "I would start by checking the codes."}]}
        """
        let transport = MockTransport([(200, MockTransport.chat(ai))])
        let evaluator = AIEvaluator(client: OpenAIClient(apiKey: "sk", model: "gpt-x", transport: transport))
        let record = Fixtures.record(answers: [Fixtures.answerRecord(Fixtures.strongAnswer, index: 0), Fixtures.answerRecord("", index: 1)])

        let report = try await evaluator.evaluate(record)

        XCTAssertEqual(report.analysisSource, .openAI)
        XCTAssertEqual(report.analysisModel, "gpt-x")
        XCTAssertEqual(report.overallScore, 88)
        XCTAssertEqual(report.summary, "Great job overall.")
        XCTAssertEqual(report.strengths, ["Clear STAR story"])
        XCTAssertEqual(report.delivery.feedback, "Nice pace.")
        XCTAssertFalse(report.eyeContact.feedback.contains("Should be ignored"))
        XCTAssertEqual(report.questions[0].score, 9)
        XCTAssertEqual(report.questions[0].relevance, 10)
        XCTAssertEqual(report.questions[0].suggestion, "Mention safety.")
        XCTAssertNil(report.questions[0].exampleAnswer)
        XCTAssertEqual(report.questions[1].exampleAnswer, "I would start by checking the codes.", "unanswered questions still get an example")
        XCTAssertEqual(report.questions[1].score, 0)
        XCTAssertFalse(report.questions[1].feedback.contains("Should be ignored"))
        // Measured numbers are untouched.
        XCTAssertEqual(report.questions[0].metrics, record.answers[0].metrics)

        let body = try XCTUnwrap(transport.requests.first?.httpBody).flatMap { String(data: $0, encoding: .utf8) } ?? ""
        XCTAssertTrue(body.contains("fuel line"), "the transcript is sent for evaluation")
    }

    func testResilientEvaluatorFallsBack() async throws {
        let transport = MockTransport([(500, #"{"error":{"message":"server down"}}"#)])
        let evaluator = ResilientEvaluator(primary: AIEvaluator(client: OpenAIClient(apiKey: "sk", transport: transport)))
        let report = try await evaluator.evaluate(Fixtures.record(answers: [Fixtures.answerRecord(Fixtures.strongAnswer)]))
        XCTAssertEqual(report.analysisSource, .onDevice)
        XCTAssertTrue(report.notes.first?.contains("server down") ?? false, report.notes.description)

        let offline = try await ResilientEvaluator(primary: nil).evaluate(Fixtures.record(answers: [Fixtures.answerRecord("Hi")]))
        XCTAssertTrue(offline.notes.first?.contains("OpenAI API key") ?? false)
    }

    func testReactionIsTruncatedWhenTooLong() async throws {
        let long = Array(repeating: "word", count: 40).joined(separator: " ")
        let transport = MockTransport([(200, MockTransport.chat(#"{"reaction":"\#(long)"}"#))])
        let reaction = try await AIReactionGenerator(client: OpenAIClient(apiKey: "sk", transport: transport))
            .reaction(to: Fixtures.questions[0], answer: "Hello", position: "Mechanic", allowFollowUp: true)
        XCTAssertEqual(reaction.acknowledgement.split(separator: " ").count, 30)
        XCTAssertNil(reaction.followUp)
    }

    func testReactionFollowUpRespectsPermission() async throws {
        let body = MockTransport.chat(#"{"reaction":"Thanks.","followUp":"What was the result?"}"#)
        let allowed = try await AIReactionGenerator(client: OpenAIClient(apiKey: "sk", transport: MockTransport([(200, body)])))
            .reaction(to: Fixtures.questions[1], answer: "I fixed it.", position: "Mechanic", allowFollowUp: true)
        XCTAssertEqual(allowed, InterviewerReaction(acknowledgement: "Thanks.", followUp: "What was the result?"))

        let transport = MockTransport([(200, body)])
        let denied = try await AIReactionGenerator(client: OpenAIClient(apiKey: "sk", transport: transport))
            .reaction(to: Fixtures.questions[1], answer: "I fixed it.", position: "Mechanic", allowFollowUp: false)
        XCTAssertNil(denied.followUp, "a follow-up is dropped when not allowed")
        let prompt = try XCTUnwrap(transport.requests.first?.httpBody).flatMap { String(data: $0, encoding: .utf8) } ?? ""
        XCTAssertTrue(prompt.contains("Always null"))
    }
}

final class ReportStoreTests: XCTestCase {
    func testRoundTripAndDelete() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ReportStore(directory: directory)
        XCTAssertTrue(store.loadAll().isEmpty)

        var older = HeuristicEvaluator().makeReport(for: Fixtures.record(answers: [Fixtures.answerRecord(Fixtures.strongAnswer)]))
        older.createdAt = Date(timeIntervalSince1970: 100)
        var newer = older
        newer.id = UUID()
        newer.createdAt = Date(timeIntervalSince1970: 200)
        try store.save(older)
        try store.save(newer)
        try Data("not json".utf8).write(to: directory.appendingPathComponent("junk.json"))

        let loaded = store.loadAll()
        XCTAssertEqual(loaded.map(\.id), [newer.id, older.id])
        XCTAssertEqual(loaded.last, older)

        try store.delete(id: newer.id)
        XCTAssertEqual(store.loadAll().map(\.id), [older.id])
    }
}
