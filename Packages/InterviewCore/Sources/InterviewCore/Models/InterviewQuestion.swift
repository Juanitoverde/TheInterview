import Foundation

public enum QuestionCategory: String, Codable, CaseIterable, Sendable {
    case opener
    case technical
    case behavioral
    case situational
    case motivation
    case closing
    case general

    public var displayName: String {
        switch self {
        case .opener: "Introduction"
        case .technical: "Role & technical"
        case .behavioral: "Behavioral"
        case .situational: "Situational"
        case .motivation: "Motivation"
        case .closing: "Closing"
        case .general: "General"
        }
    }

    /// Phrase used in feedback such as "during the technical questions".
    var feedbackPhrase: String {
        switch self {
        case .opener: "introductory questions"
        case .technical: "questions about technical skills"
        case .behavioral: "behavioral questions"
        case .situational: "situational questions"
        case .motivation: "questions about your motivation"
        case .closing: "closing questions"
        case .general: "general questions"
        }
    }

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = QuestionCategory(loose: raw)
    }

    /// Maps the free-form category names a language model might return onto known categories.
    init(loose raw: String) {
        let value = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if let exact = QuestionCategory(rawValue: value) {
            self = exact
            return
        }
        let mapping: [(String, QuestionCategory)] = [
            ("intro", .opener), ("open", .opener), ("background", .opener),
            ("tech", .technical), ("role", .technical), ("skill", .technical), ("knowledge", .technical),
            ("behav", .behavioral), ("star", .behavioral), ("experience", .behavioral),
            ("situation", .situational), ("scenario", .situational), ("hypothetical", .situational),
            ("motiv", .motivation), ("goal", .motivation), ("career", .motivation), ("culture", .motivation),
            ("clos", .closing), ("final", .closing),
        ]
        self = mapping.first { value.contains($0.0) }?.1 ?? .general
    }
}

public struct InterviewQuestion: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var text: String
    public var category: QuestionCategory
    /// What a strong answer demonstrates. Used to guide evaluation.
    public var intent: String?

    public init(id: UUID = UUID(), text: String, category: QuestionCategory, intent: String? = nil) {
        self.id = id
        self.text = text
        self.category = category
        self.intent = intent
    }
}

public struct QuestionRequest: Equatable, Sendable {
    public var position: String
    public var count: Int
    public var difficulty: Difficulty
    public var focus: InterviewFocus
    /// Random token included in AI prompts so repeated sessions for the same role get different questions.
    public var varietyToken: String

    public init(position: String, count: Int, difficulty: Difficulty, focus: InterviewFocus, varietyToken: String = UUID().uuidString) {
        self.position = position
        self.count = count
        self.difficulty = difficulty
        self.focus = focus
        self.varietyToken = varietyToken
    }
}
