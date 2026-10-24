import Foundation

public enum Difficulty: String, Codable, CaseIterable, Identifiable, Sendable {
    case entry
    case intermediate
    case senior

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .entry: "Entry level"
        case .intermediate: "Experienced"
        case .senior: "Senior"
        }
    }

    var promptDescription: String {
        switch self {
        case .entry:
            "an entry-level candidate; focus on fundamentals, motivation, learning ability and transferable experience"
        case .intermediate:
            "an experienced candidate; expect concrete examples, solid role-specific knowledge and independent problem solving"
        case .senior:
            "a senior candidate; probe depth of expertise, leadership, mentoring, trade-offs and decisions under ambiguity"
        }
    }
}

public enum InterviewFocus: String, Codable, CaseIterable, Identifiable, Sendable {
    case balanced
    case behavioral
    case technical
    case situational

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .balanced: "Balanced"
        case .behavioral: "Behavioral"
        case .technical: "Role & technical"
        case .situational: "Situational"
        }
    }

    var promptDescription: String {
        switch self {
        case .balanced:
            "a balanced mix of role-specific/technical, behavioral and situational questions"
        case .behavioral:
            "mostly behavioral questions about past experiences (answerable with the STAR method), plus a few role-specific ones"
        case .technical:
            "mostly role-specific and technical questions that test practical knowledge of the job, plus a few behavioral ones"
        case .situational:
            "mostly situational 'what would you do if…' questions grounded in realistic scenarios for the role"
        }
    }
}

public struct InterviewConfiguration: Codable, Equatable, Sendable {
    public static let questionCountRange = 3...10

    public var questionCount: Int
    public var difficulty: Difficulty
    public var focus: InterviewFocus
    public var companyName: String
    public var receptionistName: String
    public var interviewerName: String
    /// Used if the candidate's spoken answer to "What position are you applying for?" can't be understood.
    public var presetPosition: String?
    /// Whether the interviewer's short acknowledgement after each answer is written by the AI.
    public var usesAIReactions: Bool
    /// How many follow-up questions the interviewer may ask over the whole interview (0 turns them off).
    public var maxFollowUps: Int
    /// Whether the interviewer ends by asking "Do you have any questions for me?"
    public var invitesCandidateQuestions: Bool

    /// How long to wait for the candidate to start talking before giving up on a short reply.
    public var shortReplyStartTimeout: TimeInterval
    /// How much trailing silence ends a short reply ("yes", a job title).
    public var shortReplySilenceTimeout: TimeInterval
    /// How long to wait for the candidate to start answering a question.
    public var answerStartTimeout: TimeInterval
    /// How much trailing silence ends an answer. The candidate can also say "that's my answer" or tap Done.
    public var answerSilenceTimeout: TimeInterval

    public init(
        questionCount: Int = 5,
        difficulty: Difficulty = .intermediate,
        focus: InterviewFocus = .balanced,
        companyName: String = "Meridian Works",
        receptionistName: String = "Ava",
        interviewerName: String = "Daniel Park",
        presetPosition: String? = nil,
        usesAIReactions: Bool = true,
        maxFollowUps: Int = 2,
        invitesCandidateQuestions: Bool = true,
        shortReplyStartTimeout: TimeInterval = 9,
        shortReplySilenceTimeout: TimeInterval = 1.6,
        answerStartTimeout: TimeInterval = 25,
        answerSilenceTimeout: TimeInterval = 5
    ) {
        self.questionCount = min(max(questionCount, Self.questionCountRange.lowerBound), Self.questionCountRange.upperBound)
        self.difficulty = difficulty
        self.focus = focus
        self.companyName = companyName
        self.receptionistName = receptionistName
        self.interviewerName = interviewerName
        self.presetPosition = presetPosition
        self.usesAIReactions = usesAIReactions
        self.maxFollowUps = max(maxFollowUps, 0)
        self.invitesCandidateQuestions = invitesCandidateQuestions
        self.shortReplyStartTimeout = shortReplyStartTimeout
        self.shortReplySilenceTimeout = shortReplySilenceTimeout
        self.answerStartTimeout = answerStartTimeout
        self.answerSilenceTimeout = answerSilenceTimeout
    }

    public var interviewerFirstName: String {
        interviewerName.split(separator: " ").first.map(String.init) ?? interviewerName
    }
}
