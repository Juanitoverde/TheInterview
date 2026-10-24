import Foundation

/// A follow-up question the interviewer asked about an answer, and the candidate's reply.
public struct FollowUpExchange: Codable, Equatable, Sendable {
    public var question: String
    public var utterance: Utterance
    public var metrics: SpeechMetrics
    /// Attention while the follow-up was asked and answered.
    public var attention: AttentionSummary

    public init(question: String, utterance: Utterance, metrics: SpeechMetrics, attention: AttentionSummary) {
        self.question = question
        self.utterance = utterance
        self.metrics = metrics
        self.attention = attention
    }
}

public struct AnswerRecord: Codable, Equatable, Sendable {
    public var index: Int
    public var question: InterviewQuestion
    public var utterance: Utterance
    public var metrics: SpeechMetrics
    /// Head-pose attention while the interviewer asked the question.
    public var attentionWhileListening: AttentionSummary
    /// Head-pose attention while the candidate answered.
    public var attentionWhileAnswering: AttentionSummary
    public var followUp: FollowUpExchange?

    public init(
        index: Int,
        question: InterviewQuestion,
        utterance: Utterance,
        metrics: SpeechMetrics,
        attentionWhileListening: AttentionSummary,
        attentionWhileAnswering: AttentionSummary,
        followUp: FollowUpExchange? = nil
    ) {
        self.index = index
        self.question = question
        self.utterance = utterance
        self.metrics = metrics
        self.attentionWhileListening = attentionWhileListening
        self.attentionWhileAnswering = attentionWhileAnswering
        self.followUp = followUp
    }

    /// The answer together with any follow-up reply; this is what gets scored.
    public var combinedText: String {
        [utterance.text, followUp?.utterance.text ?? ""]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    public var combinedMetrics: SpeechMetrics {
        SpeechMetrics.combined(metrics, followUp?.metrics)
    }

    /// Combined attention over the whole exchange, weighted by tracked time.
    public var combinedAttention: AttentionSummary {
        let parts = [attentionWhileListening, attentionWhileAnswering, followUp?.attention ?? .unavailable].filter(\.isAvailable)
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
    /// Whether the interviewer asked "Do you have any questions for me?"
    public var candidateQuestionsInvited: Bool
    public var candidateQuestions: [String]

    public init(
        candidate: CandidateProfile,
        position: String,
        configuration: InterviewConfiguration,
        plannedQuestionCount: Int,
        answers: [AnswerRecord],
        overallAttention: AttentionSummary,
        startedAt: Date,
        endedAt: Date,
        endedEarly: Bool,
        candidateQuestionsInvited: Bool = false,
        candidateQuestions: [String] = []
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
        self.candidateQuestionsInvited = candidateQuestionsInvited
        self.candidateQuestions = candidateQuestions
    }
}

public enum AnalysisSource: String, Codable, Sendable {
    case openAI
    /// Apple's on-device foundation model.
    case appleIntelligence
    /// The built-in rule-based evaluator.
    case onDevice
}

/// How the overall score is made up. Each part is 0...100; parts that couldn't be measured are nil.
public struct ScoreBreakdown: Codable, Equatable, Sendable {
    public var content: Int
    public var delivery: Int?
    public var eyeContact: Int?

    public static let contentWeight = 0.7
    public static let deliveryWeight = 0.15
    public static let eyeContactWeight = 0.15

    public init(content: Int, delivery: Int?, eyeContact: Int?) {
        self.content = content
        self.delivery = delivery
        self.eyeContact = eyeContact
    }

    /// Weighted overall score; missing parts' weight is shared among the rest.
    public var overall: Int {
        var total = Double(content) * Self.contentWeight
        var weight = Self.contentWeight
        if let delivery {
            total += Double(delivery) * Self.deliveryWeight
            weight += Self.deliveryWeight
        }
        if let eyeContact {
            total += Double(eyeContact) * Self.eyeContactWeight
            weight += Self.eyeContactWeight
        }
        return min(max(Int((total / weight).rounded()), 0), 100)
    }
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
    /// 0...100, or nil when nothing was spoken.
    public var score: Int?
    /// Pauses of two seconds or more, when word timings were available.
    public var longPauseCount: Int?
    public var longestPause: Double?

    public init(
        totalSpeakingSeconds: Double,
        totalWords: Int,
        averageWordsPerMinute: Int?,
        fillerCount: Int,
        topFillers: [String],
        feedback: String,
        score: Int? = nil,
        longPauseCount: Int? = nil,
        longestPause: Double? = nil
    ) {
        self.totalSpeakingSeconds = totalSpeakingSeconds
        self.totalWords = totalWords
        self.averageWordsPerMinute = averageWordsPerMinute
        self.fillerCount = fillerCount
        self.topFillers = topFillers
        self.feedback = feedback
        self.score = score
        self.longPauseCount = longPauseCount
        self.longestPause = longestPause
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
    public var followUpQuestion: String?
    public var followUpAnswer: String?
    /// How a stronger answer might sound (written by the AI evaluator).
    public var exampleAnswer: String?

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
        eyeContactPercent: Int?,
        followUpQuestion: String? = nil,
        followUpAnswer: String? = nil,
        exampleAnswer: String? = nil
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
        self.followUpQuestion = followUpQuestion
        self.followUpAnswer = followUpAnswer
        self.exampleAnswer = exampleAnswer
    }

    /// The answer plus any follow-up reply.
    public var fullAnswer: String {
        [answer, followUpAnswer ?? ""].filter { !$0.isEmpty }.joined(separator: " ")
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
    /// Questions the candidate asked at the end (nil in reports from older versions).
    public var candidateQuestions: [String]?
    public var breakdown: ScoreBreakdown?

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
        endedEarly: Bool = false,
        candidateQuestions: [String]? = nil,
        breakdown: ScoreBreakdown? = nil
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
        self.candidateQuestions = candidateQuestions
        self.breakdown = breakdown
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
        if let breakdown {
            var parts = ["answers \(breakdown.content)"]
            if let delivery = breakdown.delivery { parts.append("delivery \(delivery)") }
            if let eye = breakdown.eyeContact { parts.append("eye contact \(eye)") }
            lines.append("Breakdown: " + parts.joined(separator: ", "))
        }
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
        if let asked = candidateQuestions, !asked.isEmpty {
            lines.append("")
            lines.append("Your questions for the interviewer:")
            lines += asked.map { "• \($0)" }
        }
        for question in questions {
            lines.append("")
            lines.append("Q\(question.index + 1) [\(question.category.displayName)] \(question.question)")
            lines.append("Your answer: \(question.answer.isEmpty ? "(no answer)" : question.answer)")
            if let followUp = question.followUpQuestion {
                lines.append("Follow-up: \(followUp)")
                let reply = question.followUpAnswer ?? ""
                lines.append("Your reply: \(reply.isEmpty ? "(no answer)" : reply)")
            }
            lines.append("Score: \(question.score)/10. \(question.feedback)")
            if !question.suggestion.isEmpty { lines.append("Tip: \(question.suggestion)") }
            if let example = question.exampleAnswer { lines.append("A stronger answer: \(example)") }
        }
        return lines.joined(separator: "\n")
    }
}
