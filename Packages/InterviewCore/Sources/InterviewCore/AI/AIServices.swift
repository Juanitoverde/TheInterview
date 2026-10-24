import Foundation

/// Generates interview questions tailored to the position with a language model.
public struct AIQuestionGenerator: QuestionGenerating {
    private let client: any LanguageModelClient

    public init(client: any LanguageModelClient) {
        self.client = client
    }

    struct Response: Decodable {
        struct Item: Decodable {
            let text: String
            let category: QuestionCategory?
            let intent: String?
        }

        let questions: [Item]
    }

    public func generateQuestions(for request: QuestionRequest) async throws -> [InterviewQuestion] {
        let data = try await client.completeJSON(system: Prompts.questionSystem, user: Prompts.questionUser(for: request), timeout: 30)
        let response: Response
        do {
            response = try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw OpenAIError.decoding(error.localizedDescription)
        }
        return response.questions
            .compactMap { item -> InterviewQuestion? in
                guard let text = item.text.nilIfBlank else { return nil }
                return InterviewQuestion(text: text, category: item.category ?? .general, intent: item.intent?.nilIfBlank)
            }
            .prefix(request.count)
            .map { $0 }
    }
}

/// Writes the interviewer's short acknowledgement after each answer, decides on follow-up questions,
/// and answers the candidate's own questions at the end.
public struct AIReactionGenerator: ReactionGenerating {
    private let client: any LanguageModelClient

    public init(client: any LanguageModelClient) {
        self.client = client
    }

    struct Response: Decodable {
        let reaction: String
        let followUp: String?
    }

    public func reaction(to question: InterviewQuestion, answer: String, position: String, allowFollowUp: Bool) async throws -> InterviewerReaction {
        let data = try await client.completeJSON(
            system: Prompts.reactionSystem,
            user: Prompts.reactionUser(question: question, answer: answer, position: position, allowFollowUp: allowFollowUp),
            timeout: 8
        )
        let response = try JSONDecoder().decode(Response.self, from: data)
        let followUp = allowFollowUp ? response.followUp?.nilIfBlank : nil
        return InterviewerReaction(
            acknowledgement: Self.limit(response.reaction, words: 30),
            followUp: followUp.map { Self.limit($0, words: 40) }
        )
    }

    struct CandidateAnswer: Decodable {
        let answer: String
    }

    public func answer(candidateQuestion: String, position: String, companyName: String) async throws -> String {
        let data = try await client.completeJSON(
            system: Prompts.reactionSystem,
            user: Prompts.candidateQuestionUser(question: candidateQuestion, position: position, companyName: companyName),
            timeout: 10
        )
        return Self.limit(try JSONDecoder().decode(CandidateAnswer.self, from: data).answer, words: 60)
    }

    /// Guards against an over-long reply being read out in full.
    private static func limit(_ text: String, words limit: Int) -> String {
        let words = text.split(separator: " ")
        return words.count > limit ? words.prefix(limit).joined(separator: " ") + "." : text
    }
}

/// Asks a language model to grade the interview, layered over the on-device measurements.
///
/// Numbers that were measured (pace, filler words, pauses, eye contact) always come from the device;
/// the model contributes scores for answer quality and the written feedback.
public struct AIEvaluator: InterviewEvaluating {
    private let client: any LanguageModelClient
    private let baseline = HeuristicEvaluator()

    public init(client: any LanguageModelClient) {
        self.client = client
    }

    struct Response: Decodable {
        struct Question: Decodable {
            let index: Int
            let score: Double?
            let relevance: Double?
            let clarity: Double?
            let structure: Double?
            let feedback: String?
            let suggestion: String?
            let exampleAnswer: String?

            enum CodingKeys: String, CodingKey {
                case index, score, relevance, clarity, structure, feedback, suggestion, exampleAnswer
            }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                index = Int(try container.decodeLenientDouble(forKey: .index) ?? -1)
                score = try container.decodeLenientDouble(forKey: .score)
                relevance = try container.decodeLenientDouble(forKey: .relevance)
                clarity = try container.decodeLenientDouble(forKey: .clarity)
                structure = try container.decodeLenientDouble(forKey: .structure)
                feedback = try container.decodeIfPresent(String.self, forKey: .feedback)
                suggestion = try container.decodeIfPresent(String.self, forKey: .suggestion)
                exampleAnswer = try container.decodeIfPresent(String.self, forKey: .exampleAnswer)
            }
        }

        /// Answer quality alone, 0-100.
        let contentScore: Double?
        /// Older prompt versions returned an overall score instead.
        let overallScore: Double?
        let summary: String?
        let strengths: [String]?
        let improvements: [String]?
        let eyeContactFeedback: String?
        let deliveryFeedback: String?
        let questions: [Question]?

        enum CodingKeys: String, CodingKey {
            case contentScore, overallScore, summary, strengths, improvements, eyeContactFeedback, deliveryFeedback, questions
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            contentScore = try container.decodeLenientDouble(forKey: .contentScore)
            overallScore = try container.decodeLenientDouble(forKey: .overallScore)
            summary = try container.decodeIfPresent(String.self, forKey: .summary)
            strengths = try container.decodeIfPresent([String].self, forKey: .strengths)
            improvements = try container.decodeIfPresent([String].self, forKey: .improvements)
            eyeContactFeedback = try container.decodeIfPresent(String.self, forKey: .eyeContactFeedback)
            deliveryFeedback = try container.decodeIfPresent(String.self, forKey: .deliveryFeedback)
            questions = try container.decodeIfPresent([Question].self, forKey: .questions)
        }
    }

    public func evaluate(_ record: InterviewRecord) async throws -> InterviewReport {
        let report = baseline.makeReport(for: record)
        let data = try await client.completeJSON(
            system: Prompts.evaluationSystem,
            user: Prompts.evaluationUser(record: record, baseline: report, maxAnswerCharacters: client.maxAnswerCharacters),
            timeout: 60
        )
        let response: Response
        do {
            response = try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw OpenAIError.decoding(error.localizedDescription)
        }
        return Self.merge(response, into: report, model: client.modelName, source: client.analysisSource)
    }

    static func merge(_ response: Response, into baseline: InterviewReport, model: String, source: AnalysisSource) -> InterviewReport {
        var report = baseline
        report.analysisSource = source
        report.analysisModel = model

        if let content = response.contentScore, var breakdown = report.breakdown {
            // The model judges the answers; delivery and eye contact stay as measured.
            breakdown.content = clamp(Int(content.rounded()), 0, 100)
            report.breakdown = breakdown
            report.overallScore = breakdown.overall
        } else if let score = response.overallScore {
            report.overallScore = clamp(Int(score.rounded()), 0, 100)
        }
        if let summary = response.summary?.nilIfBlank { report.summary = summary }
        if let strengths = response.strengths?.compactMap(\.nilIfBlank), !strengths.isEmpty { report.strengths = Array(strengths.prefix(5)) }
        if let improvements = response.improvements?.compactMap(\.nilIfBlank), !improvements.isEmpty { report.improvements = Array(improvements.prefix(5)) }
        if report.eyeContact.isAvailable, let eye = response.eyeContactFeedback?.nilIfBlank { report.eyeContact.feedback = eye }
        if let delivery = response.deliveryFeedback?.nilIfBlank { report.delivery.feedback = delivery }

        for item in response.questions ?? [] {
            guard let position = report.questions.firstIndex(where: { $0.index == item.index }) else { continue }
            var question = report.questions[position]
            question.exampleAnswer = item.exampleAnswer?.nilIfBlank
            // An unanswered question stays at zero whatever the model says.
            guard !question.fullAnswer.isEmpty else {
                report.questions[position] = question
                continue
            }
            func scaled(_ value: Double?, _ fallback: Int) -> Int { value.map { clamp(Int($0.rounded()), 0, 10) } ?? fallback }
            question.score = scaled(item.score, question.score)
            question.relevance = scaled(item.relevance, question.relevance)
            question.clarity = scaled(item.clarity, question.clarity)
            question.structure = scaled(item.structure, question.structure)
            if let feedback = item.feedback?.nilIfBlank { question.feedback = feedback }
            if let suggestion = item.suggestion?.nilIfBlank { question.suggestion = suggestion }
            report.questions[position] = question
        }
        return report
    }
}

/// Uses the AI evaluator when available and falls back to on-device analysis on any failure.
public struct ResilientEvaluator: InterviewEvaluating {
    private let primary: InterviewEvaluating?
    private let fallback = HeuristicEvaluator()
    private let timeout: TimeInterval

    public init(primary: InterviewEvaluating?, timeout: TimeInterval = 75) {
        self.primary = primary
        self.timeout = timeout
    }

    public func evaluate(_ record: InterviewRecord) async throws -> InterviewReport {
        guard let primary else {
            return fallback.makeReport(for: record, notes: ["Analysed on device. Add an OpenAI API key in Settings for AI-written feedback on your answers."])
        }
        do {
            return try await withTimeout(seconds: timeout) { try await primary.evaluate(record) }
        } catch {
            let reason = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return fallback.makeReport(for: record, notes: ["AI analysis wasn't available (\(reason)), so this report uses on-device analysis."])
        }
    }
}

extension KeyedDecodingContainer {
    /// Decodes a number that a model may have written as a number or as a string.
    func decodeLenientDouble(forKey key: Key) throws -> Double? {
        if let value = try? decodeIfPresent(Double.self, forKey: key) { return value }
        if let text = try? decodeIfPresent(String.self, forKey: key) {
            // Accept "8", "8/10" or "85%".
            let head = text.split(separator: "/").first.map(String.init) ?? text
            return Double(head.trimmingCharacters(in: CharacterSet(charactersIn: " %")))
        }
        return nil
    }
}
