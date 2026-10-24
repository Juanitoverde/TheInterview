import Foundation

/// Speaks a line in a character's voice. Returns when the line has finished (or was cut short).
@MainActor
public protocol VoiceOutput: AnyObject {
    func speak(_ text: String, as speaker: Speaker) async
}

public enum ListenPurpose: String, Sendable {
    case position
    case readiness
    case answer
    /// The candidate's own questions at the end of the interview.
    case candidateQuestion
}

public struct ListenRequest: Equatable, Sendable {
    public var purpose: ListenPurpose
    /// Give up if the candidate hasn't started speaking within this many seconds.
    public var startTimeout: TimeInterval
    /// Finish once the candidate has been silent this long after speaking.
    public var silenceTimeout: TimeInterval
    /// Whether "that's my answer" ends listening immediately.
    public var allowsFinishCue: Bool

    public init(purpose: ListenPurpose, startTimeout: TimeInterval, silenceTimeout: TimeInterval, allowsFinishCue: Bool) {
        self.purpose = purpose
        self.startTimeout = startTimeout
        self.silenceTimeout = silenceTimeout
        self.allowsFinishCue = allowsFinishCue
    }
}

/// Captures one reply from the candidate, by voice or typed text.
@MainActor
public protocol VoiceInput: AnyObject {
    /// Listens until the reply is complete. `onPartial` receives the live transcript as it grows.
    func listen(_ request: ListenRequest, onPartial: @escaping @MainActor (String) -> Void) async throws -> Utterance
    /// Ends the current listen early, returning whatever has been captured so far.
    func finishListening()
}

/// Choreography in the immersive office. `perform` returns when the animation completes.
public enum StageCue: String, Sendable {
    case enterReception
    case receptionistWaves
    case receptionistPointsTheWay
    case walkToInterviewRoom
    case receptionistLeaves
    case interviewerStands
    case interviewerSits
    case focusOnInterviewer
    case interviewerNods
    case exitOffice
}

@MainActor
public protocol StageDirecting: AnyObject {
    func perform(_ cue: StageCue) async
}

/// Records where the candidate is looking (approximated from head pose) during the interview.
@MainActor
public protocol AttentionTracking: AnyObject {
    func startTracking()
    func beginSegment()
    func endSegment() -> AttentionSummary
    func stopTracking() -> AttentionSummary
}

public protocol QuestionGenerating {
    func generateQuestions(for request: QuestionRequest) async throws -> [InterviewQuestion]
}

/// What the interviewer says after an answer: a brief acknowledgement, and possibly a probing follow-up.
public struct InterviewerReaction: Equatable, Sendable {
    public var acknowledgement: String
    public var followUp: String?

    public init(acknowledgement: String, followUp: String? = nil) {
        self.acknowledgement = acknowledgement
        self.followUp = followUp
    }
}

public protocol ReactionGenerating {
    /// The interviewer's response to an answer. `followUp` must be nil when `allowFollowUp` is false.
    func reaction(to question: InterviewQuestion, answer: String, position: String, allowFollowUp: Bool) async throws -> InterviewerReaction

    /// The interviewer's in-character answer to a question the candidate asks at the end.
    func answer(candidateQuestion: String, position: String, companyName: String) async throws -> String
}

public protocol InterviewEvaluating {
    func evaluate(_ record: InterviewRecord) async throws -> InterviewReport
}

/// Used when no stage or tracker is available (tests, or devices without world tracking).
@MainActor
public final class NullStage: StageDirecting {
    public init() {}
    public func perform(_ cue: StageCue) async {}
}

@MainActor
public final class NullAttentionTracker: AttentionTracking {
    public init() {}
    public func startTracking() {}
    public func beginSegment() {}
    public func endSegment() -> AttentionSummary { .unavailable }
    public func stopTracking() -> AttentionSummary { .unavailable }
}
