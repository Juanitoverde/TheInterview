import XCTest
@testable import InterviewCore

final class SpeechAnalyzerTests: XCTestCase {
    func testCountsWordsPaceAndFillers() {
        let text = "Um, so I think I would, like, basically start by checking the codes. Uh, I mean, then I'd test it."
        let metrics = SpeechAnalyzer.analyze(text: text, speakingSeconds: 10, method: .voice)
        XCTAssertEqual(metrics.wordCount, 20)
        XCTAssertEqual(metrics.sentenceCount, 2)
        XCTAssertEqual(metrics.wordsPerMinute ?? 0, 120, accuracy: 0.01)
        XCTAssertEqual(metrics.fillerWords["um"], 1)
        XCTAssertEqual(metrics.fillerWords["uh"], 1)
        XCTAssertEqual(metrics.fillerWords["like"], 1)
        XCTAssertEqual(metrics.fillerWords["basically"], 1)
        XCTAssertEqual(metrics.fillerWords["i mean"], 1)
        XCTAssertNil(metrics.fillerWords["so"], "'so' only counts as a filler when it opens the answer")
        XCTAssertEqual(metrics.hedgeCount, 1)
    }

    func testLikeAsAVerbIsNotAFiller() {
        let metrics = SpeechAnalyzer.analyze(text: "I like working on diesel engines because I like a challenge.", speakingSeconds: 5, method: .voice)
        XCTAssertNil(metrics.fillerWords["like"])
    }

    func testTypedAnswersHaveNoPace() {
        let metrics = SpeechAnalyzer.analyze(text: "I would check the wiring first.", speakingSeconds: 40, method: .typed)
        XCTAssertNil(metrics.wordsPerMinute)
        XCTAssertEqual(metrics.wordCount, 6)
    }

    func testNumbersWithSeparatorsAreOneWord() {
        XCTAssertEqual(TextTools.words(in: "It ran 80,000 miles, then 2.5 more. Done."), ["it", "ran", "80,000", "miles", "then", "2.5", "more", "done"])
    }

    func testEmptyText() {
        XCTAssertEqual(SpeechAnalyzer.analyze(text: "  ", speakingSeconds: 3, method: .voice), .empty)
    }

    func testCombinedMetrics() {
        let first = SpeechAnalyzer.analyze(text: "Um, I checked the brakes first.", speakingSeconds: 6, method: .voice)
        let second = SpeechAnalyzer.analyze(text: "Then, uh, I replaced the pads and tested them on the road.", speakingSeconds: 6, method: .voice)
        let combined = SpeechMetrics.combined(first, second)
        XCTAssertEqual(combined.wordCount, first.wordCount + second.wordCount)
        XCTAssertEqual(combined.speakingSeconds, 12)
        XCTAssertEqual(combined.wordsPerMinute ?? 0, Double(combined.wordCount) * 5, accuracy: 0.001)
        XCTAssertEqual(combined.fillerWords, ["um": 1, "uh": 1])
        XCTAssertEqual(SpeechMetrics.combined(first, nil), first)
        XCTAssertEqual(SpeechMetrics.combined(.empty, second), second)
    }
}

final class FollowUpAdvisorTests: XCTestCase {
    private func reason(_ text: String, _ category: QuestionCategory) -> FollowUpReason? {
        FollowUpAdvisor.reason(
            for: InterviewQuestion(text: "Tell me about a time you solved a hard problem.", category: category),
            answer: text,
            metrics: SpeechAnalyzer.analyze(text: text, speakingSeconds: 20, method: .voice)
        )
    }

    func testProbesWhatARealInterviewerWould() {
        XCTAssertEqual(reason("I'm good at fixing things.", .behavioral), .tooBrief)
        XCTAssertEqual(reason("I generally think staying calm and being organised is the most important thing, and I always try to communicate well with everyone around me.", .behavioral), .needsExample)
        XCTAssertEqual(reason("At my last job a customer's van kept stalling, so I decided to test the fuel pump and I replaced it and I talked them through what had gone wrong.", .behavioral), .needsOutcome)
        XCTAssertNil(reason(Fixtures.strongAnswer, .behavioral))
        XCTAssertEqual(reason("I would mostly use the diagnostic scanner, a multimeter and a good set of hand tools for that sort of job.", .technical), .needsExample)
        XCTAssertNil(reason("I'd use an OBD-II scanner, a multimeter, and a smoke machine for vacuum leaks; on my last job I used those daily on about 12 cars a day.", .technical))
        XCTAssertNil(reason("I've always loved taking things apart and I think this workshop would be a great place to grow my career.", .motivation))
        XCTAssertNil(reason("", .behavioral))
        XCTAssertNil(reason("Running my own workshop one day, ideally one focused on electric and hybrid vehicles.", .closing), "short answers are fine for closing questions")
        XCTAssertEqual(reason("Not sure yet.", .closing), .tooBrief)
    }
}

final class AttentionTests: XCTestCase {
    private let head = Vector3(0, 1.2, 0)
    private let interviewer = Vector3(0, 1.25, -1.7)

    private func sample(_ time: Double, yawDegrees: Double, pitchDegrees: Double = 0) -> AttentionSample {
        // Rotate the "looking at the interviewer" direction by the given yaw / pitch.
        let base = (interviewer - head).normalized
        let baseYaw = atan2(base.x, -base.z)
        let basePitch = asin(base.y)
        let yaw = baseYaw + yawDegrees * .pi / 180
        let pitch = basePitch + pitchDegrees * .pi / 180
        let forward = Vector3(sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch))
        return AttentionSample(time: time, headPosition: head, headForward: forward, target: interviewer)
    }

    func testDeviationAngles() {
        let straight = AttentionAnalyzer.deviation(of: sample(0, yawDegrees: 0))
        XCTAssertEqual(straight.yaw, 0, accuracy: 0.01)
        XCTAssertEqual(straight.pitch, 0, accuracy: 0.01)

        let right = AttentionAnalyzer.deviation(of: sample(0, yawDegrees: 35))
        XCTAssertEqual(right.yaw, 35, accuracy: 0.5)

        let down = AttentionAnalyzer.deviation(of: sample(0, yawDegrees: 0, pitchDegrees: -30))
        XCTAssertEqual(down.pitch, 30, accuracy: 0.5)
        XCTAssertFalse(AttentionAnalyzer.isEngaged(sample(0, yawDegrees: 0, pitchDegrees: -30)))
        XCTAssertTrue(AttentionAnalyzer.isEngaged(sample(0, yawDegrees: 10, pitchDegrees: 5)))
    }

    func testSummaryCountsLookAwaysAndRatio() {
        var samples: [AttentionSample] = []
        // 10 s at 10 Hz: engaged 0-4 s, away 4-6 s, engaged 6-9.5 s, a 0.3 s glance, then engaged.
        for i in 0..<100 {
            let t = Double(i) / 10
            let away = (t >= 4 && t < 6) || (t >= 9.5 && t < 9.8)
            samples.append(sample(t, yawDegrees: away ? 45 : 5))
        }
        let summary = AttentionAnalyzer.summarize(samples)
        XCTAssertEqual(summary.sampleCount, 100)
        XCTAssertEqual(summary.trackedSeconds, 10, accuracy: 0.01)
        XCTAssertEqual(summary.engagedRatio, 0.77, accuracy: 0.011)
        XCTAssertEqual(summary.lookAwayCount, 1, "the 0.3 s glance is too short to count")
        XCTAssertEqual(summary.longestLookAwaySeconds, 2, accuracy: 0.01)
        XCTAssertTrue(summary.isAvailable)
    }

    func testTrackingGapsAreCapped() {
        let samples = [sample(0, yawDegrees: 0), sample(0.1, yawDegrees: 0), sample(30, yawDegrees: 0)]
        XCTAssertEqual(AttentionAnalyzer.summarize(samples).trackedSeconds, 0.1 + 0.5 + 0.5, accuracy: 0.001)
    }

    func testRecorderSegments() {
        let recorder = AttentionRecorder()
        recorder.record(sample(0, yawDegrees: 0))
        XCTAssertTrue(recorder.samples.isEmpty, "samples are ignored until recording starts")

        recorder.start()
        recorder.beginSegment()
        for i in 0..<10 { recorder.record(sample(Double(i) / 10, yawDegrees: 0)) }
        let first = recorder.endSegment()
        recorder.beginSegment()
        for i in 10..<20 { recorder.record(sample(Double(i) / 10, yawDegrees: 60)) }
        let second = recorder.endSegment()
        XCTAssertEqual(recorder.isCurrentlyEngaged, false)
        let overall = recorder.stop()

        XCTAssertEqual(first.engagedRatio, 1, accuracy: 0.001)
        XCTAssertEqual(second.engagedRatio, 0, accuracy: 0.001)
        XCTAssertEqual(overall.engagedRatio, 0.5, accuracy: 0.001)
        XCTAssertEqual(overall.sampleCount, 20)
    }
}

final class QuestionBankTests: XCTestCase {
    func testBuildsRequestedNumberOfDistinctQuestions() {
        var generator = SeededGenerator(seed: 42)
        for count in InterviewConfiguration.questionCountRange {
            for focus in InterviewFocus.allCases {
                let request = QuestionRequest(position: "Technical Mechanic", count: count, difficulty: .intermediate, focus: focus)
                let questions = QuestionBank().questions(for: request, using: &generator)
                XCTAssertEqual(questions.count, count)
                XCTAssertEqual(Set(questions.map(\.text)).count, count, "questions must not repeat")
                XCTAssertEqual(questions.first?.category, .opener)
                XCTAssertEqual(questions.last?.category, .closing)
                XCTAssertFalse(questions.contains { $0.text.contains("{position}") })
            }
        }
    }

    func testIsReproducibleWithSeed() {
        let request = QuestionRequest(position: "Nurse", count: 6, difficulty: .senior, focus: .behavioral)
        var a = SeededGenerator(seed: 7)
        var b = SeededGenerator(seed: 7)
        XCTAssertEqual(QuestionBank().questions(for: request, using: &a).map(\.text), QuestionBank().questions(for: request, using: &b).map(\.text))
    }

    func testRespectsDifficulty() {
        var generator = SeededGenerator(seed: 1)
        let request = QuestionRequest(position: "Analyst", count: 10, difficulty: .entry, focus: .behavioral)
        let texts = QuestionBank().questions(for: request, using: &generator).map(\.text)
        XCTAssertFalse(texts.contains { $0.contains("mentored someone") }, "senior-only questions shouldn't appear for entry level")
    }

    func testPaddingTopsUpAndKeepsClosingLast() {
        let request = QuestionRequest(position: "Chef", count: 5, difficulty: .intermediate, focus: .balanced)
        let existing = [
            InterviewQuestion(text: "Tell me about yourself.", category: .opener),
            InterviewQuestion(text: "Why do you want to cook here?", category: .closing),
        ]
        let padded = QuestionBank().padding(existing, toMatch: request)
        XCTAssertEqual(padded.count, 5)
        XCTAssertEqual(padded.first?.text, "Tell me about yourself.")
        XCTAssertEqual(padded.last?.text, "Why do you want to cook here?")
        XCTAssertEqual(Set(padded.map(\.text)).count, 5)
    }
}
