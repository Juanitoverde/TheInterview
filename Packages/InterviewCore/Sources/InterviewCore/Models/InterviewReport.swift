import Foundation

public struct AnswerRecord: Codable, Equatable, Sendable {
    public var index: Int
    public var question: InterviewQuestion
    public var utterance: Utterance
    public var metrics: SpeechMetrics
    /// Head-pose attention while the interviewer asked the question.
    public var attentionWhileListening: AttentionSummary
    /// Head-pose attention while the candidate answered.
    public var attentionWhileAnswering: AttentionSummary

    public init(
        index: Int,
        question: InterviewQuestion,
        utterance: Utterance,
        metrics: SpeechMetrics,
        attentionWhileListening: AttentionSummary,
        attentionWhileAnswering: AttentionSummary
    ) {
        self.index = index
        self.question = question
        self.utterance = utterance
        self.metrics = metrics
        self.attentionWhileListening = attentionWhileListening
        self.attentionWhileAnswering = attentionWhileAnswering
    }

    /// Combined attention over the whole exchange, weighted by tracked time.
    public var combinedAttention: AttentionSummary {
        let parts = [attentionWhileListening, attentionWhileAnswering].filter(\.isAvailable)
        guard !parts.isEmpty else { return .unavailable }
        let tracked = parts.reduce(0) { $0 + $1.trackedSeconds }
        let samples = parts.reduce(0) { $0 + $1.sampleCount }
        return AttentionSummary(
            sampleCount: samples,
            trackedSeconds: tracked,
            engagedRatio: parts.reduce(0) { $0 + $1.engagedRatio * $1.trackedSeconds } / tracked,
            lookAwayCount: parts.reduce(0) { $0 + $1.lookAwayCount },
            longestLookAwaySeconds: parts.map(\.longestLookAwaySeconds).max() ?? 0,
            averageDeviationDegrees: parts.reduce(0) { $0 + $1.averageDeviationDegrees * Double($1.sampleCount) } / Double(samples)
        )
    }
}

/// Everything captured during one interview; the input to evaluation.
public struct InterviewRecord: Sendable {
    public var candidate: CandidateProfile
    public var position: String
    public var configuration: InterviewConfiguration
    public var plannedQuestionCount: Int
    public var answers: [AnswerRecord]
    public var overallAttention: AttentionSummary
    public var startedAt: Date
    public var endedAt: Date
    public var endedEarly: Bool

    public init(
        candidate: CandidateProfile,
        position: String,
        configuration: InterviewConfiguration,
        plannedQuestionCount: Int,
        answers: [AnswerRecord],
        overallAttention: AttentionSummary,
        startedAt: Date,
        endedAt: Date,
        endedEarly: Bool
    ) {
        self.candidate = candidate
        self.position = position
        self.configuration = configuration
        self.plannedQuestionCount = plannedQuestionCount
        self.answers = answers
        self.overallAttention = overallAttention
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.endedEarly = endedEarly
    }
}

public enum AnalysisSource: String, Codable, Sendable {
    case openAI
    case onDevice
}

public struct EyeContactReport: Codable, Equatable, Sendable {
    public var isAvailable: Bool
    /// 0...100
    public var score: Int
    public var engagedPercent: Int
    public var lookAwayCount: Int
    public var longestLookAwaySeconds: Double
    public var feedback: String

    public init(isAvailable: Bool, score: Int, engagedPercent: Int, lookAwayCount: Int, longestLookAwaySeconds: Double, feedback: String) {
        self.isAvailable = isAvailable
        self.score = score
        self.engagedPercent = engagedPercent
        self.lookAwayCount = lookAwayCount
        self.longestLookAwaySeconds = longestLookAwaySeconds
        self.feedback = feedback
    }
}

public struct DeliveryReport: Codable, Equatable, Sendable {
    public var totalSpeakingSeconds: Double
    public var totalWords: Int
    public var averageWordsPerMinute: Int?
    public var fillerCount: Int
    public var topFillers: [String]
    public var feedback: String

    public init(totalSpeakingSeconds: Double, totalWords: Int, averageWordsPerMinute: Int?, fillerCount: Int, topFillers: [String], feedback: String) {
        self.totalSpeakingSeconds = totalSpeakingSeconds
        self.totalWords = totalWords
        self.averageWordsPerMinute = averageWordsPerMinute
        self.fillerCount = fillerCount
        self.topFillers = topFillers
        self.feedback = feedback
    }
}

public struct QuestionFeedback: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var index: Int
    public var question: String
    public var category: QuestionCategory
    public var answer: String
    public var inputMethod: InputMethod
    /// 0...10
    public var score: Int
    public var relevance: Int
    public var clarity: Int
    public var structure: Int
    public var feedback: String
    public var suggestion: String
    public var metrics: SpeechMetrics
    public var eyeContactPercent: Int?

    public init(
        id: UUID = UUID(),
        index: Int,
        question: String,
        category: QuestionCategory,
        answer: String,
        inputMethod: InputMethod,
        score: Int,
        relevance: Int,
        clarity: Int,
        structure: Int,
        feedback: String,
        suggestion: String,
        metrics: SpeechMetrics,
        eyeContactPercent: Int?
    ) {
        self.id = id
        self.index = index
        self.question = question
        self.category = category
        self.answer = answer
        self.inputMethod = inputMethod
        self.score = score
        self.relevance = relevance
        self.clarity = clarity
        self.structure = structure
        self.feedback = feedback
        self.suggestion = suggestion
        self.metrics = metrics
        self.eyeContactPercent = eyeContactPercent
    }
}

public struct InterviewReport: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var createdAt: Date
    public var candidateName: String
    public var position: String
    public var difficulty: Difficulty
    public var durationSeconds: Double
    /// 0...100
    public var overallScore: Int
    public var summary: String
    public var strengths: [String]
    public var improvements: [String]
    public var eyeContact: EyeContactReport
    public var delivery: DeliveryReport
    public var questions: [QuestionFeedback]
    public var analysisSource: AnalysisSource
    public var analysisModel: String?
    public var notes: [String]
    public var endedEarly: Bool

    public init(
        id: UUID = UUID(),
        createdAt: Date,
        candidateName: String,
        position: String,
        difficulty: Difficulty,
        durationSeconds: Double,
        overallScore: Int,
        summary: String,
        strengths: [String],
        improvements: [String],
        eyeContact: EyeContactReport,
        delivery: DeliveryReport,
        questions: [QuestionFeedback],
        analysisSource: AnalysisSource,
        analysisModel: String? = nil,
        notes: [String] = [],
        endedEarly: Bool = false
    ) {
        self.id = id
        self.createdAt = createdAt
        self.candidateName = candidateName
        self.position = position
        self.difficulty = difficulty
        self.durationSeconds = durationSeconds
        self.overallScore = overallScore
        self.summary = summary
        self.strengths = strengths
        self.improvements = improvements
        self.eyeContact = eyeContact
        self.delivery = delivery
        self.questions = questions
        self.analysisSource = analysisSource
        self.analysisModel = analysisModel
        self.notes = notes
        self.endedEarly = endedEarly
    }

    public var rating: String {
        switch overallScore {
        case 85...: "Excellent"
        case 70..<85: "Strong"
        case 55..<70: "Developing"
        default: "Needs practice"
        }
    }

    /// A plain-text version of the report for sharing or copying.
    public var plainText: String {
        var lines: [String] = []
        lines.append("TheInterview: \(position)")
        lines.append("Overall score: \(overallScore)/100 (\(rating))")
        lines.append("")
        lines.append(summary)
        if !strengths.isEmpty {
            lines.append("")
            lines.append("Strengths:")
            lines += strengths.map { "• \($0)" }
        }
        if !improvements.isEmpty {
            lines.append("")
            lines.append("Areas to improve:")
            lines += improvements.map { "• \($0)" }
        }
        lines.append("")
        if eyeContact.isAvailable {
            lines.append("Eye contact: \(eyeContact.engagedPercent)% of the time. \(eyeContact.feedback)")
        }
        lines.append("Delivery: \(delivery.feedback)")
        for question in questions {
            lines.append("")
            lines.append("Q\(question.index + 1) [\(question.category.displayName)] \(question.question)")
            lines.append("Your answer: \(question.answer.isEmpty ? "(no answer)" : question.answer)")
            lines.append("Score: \(question.score)/10. \(question.feedback)")
            if !question.suggestion.isEmpty { lines.append("Tip: \(question.suggestion)") }
        }
        return lines.joined(separator: "\n")
    }
}
