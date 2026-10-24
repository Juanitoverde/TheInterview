import Foundation

public enum InterviewPhase: String, Equatable, Sendable {
    case notStarted
    case reception
    case walking
    case meetingInterviewer
    case waitingForReady
    case preparingQuestions
    case asking
    case answering
    case reacting
    case candidateQuestions
    case closing
    case analyzing
    case finished
    case cancelled

    public var title: String {
        switch self {
        case .notStarted: "Getting ready"
        case .reception: "Reception"
        case .walking: "Heading to the interview room"
        case .meetingInterviewer: "Meeting the interviewer"
        case .waitingForReady: "About to begin"
        case .preparingQuestions: "Preparing questions"
        case .asking: "Question"
        case .answering: "Your answer"
        case .reacting: "Interviewer"
        case .candidateQuestions: "Your questions"
        case .closing: "Wrapping up"
        case .analyzing: "Analyzing your interview"
        case .finished: "Finished"
        case .cancelled: "Ended"
        }
    }

    /// Phases in which the interview proper (questions) is under way.
    public var isInQuestions: Bool {
        [.preparingQuestions, .asking, .answering, .reacting, .candidateQuestions].contains(self)
    }
}

/// A snapshot of the interview for the UI. The engine publishes a new value whenever anything changes.
public struct InterviewState: Equatable, Sendable {
    public var phase: InterviewPhase = .notStarted
    public var position: String?
    /// Who is talking right now, if anyone.
    public var currentSpeaker: Speaker?
    /// The last line a character said, shown as a caption.
    public var caption: String = ""
    public var captionSpeaker: Speaker?
    public var isListening = false
    public var listeningPurpose: ListenPurpose?
    /// The candidate's words as they're recognised.
    public var liveTranscript: String = ""
    /// 1-based number of the current question.
    public var questionNumber: Int?
    public var questionCount: Int = 0
    public var currentQuestion: String?
    /// True while the interviewer is asking, or the candidate answering, a follow-up question.
    public var isFollowUp = false
    public var conversation: [TranscriptEntry] = []

    public init() {}

    public var canFinishAnswer: Bool {
        isListening && (listeningPurpose == .answer || listeningPurpose == .candidateQuestion)
    }
}
