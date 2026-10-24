import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import InterviewCore

@MainActor
final class RecordingVoice: VoiceOutput {
    private(set) var lines: [(speaker: Speaker, text: String)] = []

    func speak(_ text: String, as speaker: Speaker) async {
        lines.append((speaker, text))
        await Task.yield()
    }

    func lines(by speaker: Speaker) -> [String] {
        lines.filter { $0.speaker == speaker }.map(\.text)
    }
}

/// Replies to each listen with the next scripted reply. Replies can trigger engine controls first.
@MainActor
final class ScriptedInput: VoiceInput {
    enum Reply {
        case say(String)
        case silence
        case typed(String)
        /// Runs an action (e.g. tapping "Repeat") while listening, then replies.
        case action(() -> Void, then: String)
    }

    private var replies: [Reply]
    private(set) var requests: [ListenRequest] = []
    private var clock = Date(timeIntervalSince1970: 1_000)
    var finishCount = 0

    init(_ replies: [Reply]) {
        self.replies = replies
    }

    func listen(_ request: ListenRequest, onPartial: @escaping @MainActor (String) -> Void) async throws -> Utterance {
        requests.append(request)
        await Task.yield()
        let reply = replies.isEmpty ? .silence : replies.removeFirst()
        let start = clock
        clock.addTimeInterval(20)
        switch reply {
        case let .say(text):
            onPartial(text)
            return Utterance(text: text, method: .voice, startedAt: start, endedAt: clock,
                             speechStartedAt: start.addingTimeInterval(1), speechEndedAt: clock.addingTimeInterval(-2))
        case let .typed(text):
            return Utterance(text: text, method: .typed, startedAt: start, endedAt: clock)
        case .silence:
            return .silence(startedAt: start, endedAt: clock)
        case let .action(action, text):
            action()
            return text.isEmpty
                ? .silence(startedAt: start, endedAt: clock)
                : Utterance(text: text, method: .voice, startedAt: start, endedAt: clock, speechStartedAt: start, speechEndedAt: clock)
        }
    }

    func finishListening() {
        finishCount += 1
    }
}

@MainActor
final class RecordingStage: StageDirecting {
    private(set) var cues: [StageCue] = []

    func perform(_ cue: StageCue) async {
        cues.append(cue)
        await Task.yield()
    }
}

@MainActor
final class FakeAttention: AttentionTracking {
    var segmentRatio = 0.8
    private(set) var started = false
    private(set) var segments = 0

    private var summary: AttentionSummary {
        AttentionSummary(sampleCount: 50, trackedSeconds: 10, engagedRatio: segmentRatio, lookAwayCount: 1, longestLookAwaySeconds: 1.5, averageDeviationDegrees: 9)
    }

    func startTracking() { started = true }
    func beginSegment() { segments += 1 }
    func endSegment() -> AttentionSummary { summary }
    func stopTracking() -> AttentionSummary { started ? summary : .unavailable }
}

struct FixedQuestions: QuestionGenerating {
    var questions: [InterviewQuestion]
    func generateQuestions(for request: QuestionRequest) async throws -> [InterviewQuestion] { questions }
}

struct FailingQuestions: QuestionGenerating {
    func generateQuestions(for request: QuestionRequest) async throws -> [InterviewQuestion] {
        throw OpenAIError.http(status: 500, message: "boom")
    }
}

struct FixedReaction: ReactionGenerating {
    var line: String
    func reaction(to question: InterviewQuestion, answer: String, position: String) async throws -> String { line }
}

/// Captures requests and returns canned HTTP responses.
final class MockTransport: HTTPTransport {
    var responses: [(status: Int, body: String)]
    private(set) var requests: [URLRequest] = []

    init(_ responses: [(status: Int, body: String)]) {
        self.responses = responses
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let next = responses.isEmpty ? (status: 500, body: "{}") : responses.removeFirst()
        let response = HTTPURLResponse(url: request.url!, statusCode: next.status, httpVersion: "HTTP/1.1", headerFields: nil)!
        return (Data(next.body.utf8), response)
    }

    /// Wraps a JSON string as the content of a Chat Completions response.
    static func chat(_ content: String) -> String {
        let escaped = String(data: try! JSONEncoder().encode(content), encoding: .utf8)!
        return #"{"choices":[{"message":{"role":"assistant","content":"# + escaped + "}}]}"
    }
}

enum Fixtures {
    static let candidate = CandidateProfile(fullName: "Jane Rivera", formOfAddress: .ms)

    static let questions = [
        InterviewQuestion(text: "Tell me about yourself.", category: .opener),
        InterviewQuestion(text: "Tell me about a time you fixed a difficult engine fault.", category: .behavioral),
        InterviewQuestion(text: "Where do you see yourself in five years?", category: .closing),
    ]

    static let strongAnswer = """
    At my last job at a fleet garage, a delivery truck kept stalling and two other mechanics couldn't find the cause. \
    My task was to get it back on the road within 48 hours. I started by pulling the fault codes, then I tested the fuel \
    pressure and found it dropped under load. I replaced a cracked fuel line and a clogged filter, and I tested it on a \
    20 mile drive. As a result the truck was back in service a day early, and I wrote up a checklist the team still uses, \
    which reduced repeat repairs by about 30 percent.
    """

    static func answerRecord(_ text: String, category: QuestionCategory = .behavioral, seconds: Double = 60, index: Int = 0) -> AnswerRecord {
        let start = Date(timeIntervalSince1970: 0)
        let utterance = Utterance(text: text, method: text.isEmpty ? .none : .voice, startedAt: start, endedAt: start.addingTimeInterval(seconds + 2),
                                  speechStartedAt: start.addingTimeInterval(1), speechEndedAt: start.addingTimeInterval(1 + seconds))
        return AnswerRecord(
            index: index,
            question: InterviewQuestion(text: "Tell me about a time you fixed a difficult engine fault.", category: category),
            utterance: utterance,
            metrics: SpeechAnalyzer.analyze(utterance),
            attentionWhileListening: .unavailable,
            attentionWhileAnswering: .unavailable
        )
    }

    static func record(answers: [AnswerRecord], attention: AttentionSummary = .unavailable) -> InterviewRecord {
        InterviewRecord(
            candidate: candidate,
            position: "Technical Mechanic",
            configuration: InterviewConfiguration(questionCount: 3),
            plannedQuestionCount: answers.count,
            answers: answers,
            overallAttention: attention,
            startedAt: Date(timeIntervalSince1970: 0),
            endedAt: Date(timeIntervalSince1970: 600),
            endedEarly: false
        )
    }
}
