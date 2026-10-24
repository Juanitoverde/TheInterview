import Foundation

/// Why an interviewer would probe further on an answer.
public enum FollowUpReason: Equatable, Sendable {
    /// Only a sentence or two.
    case tooBrief
    /// General claims without a concrete example.
    case needsExample
    /// A story that never says how it turned out.
    case needsOutcome
}

/// Decides, without AI, whether an answer deserves a follow-up question, the way a real interviewer would.
public enum FollowUpAdvisor {
    public static func reason(for question: InterviewQuestion, answer: String, metrics: SpeechMetrics) -> FollowUpReason? {
        guard metrics.wordCount > 0 else { return nil }
        // Short answers are natural for "where do you see yourself" style questions.
        let briefLimit = question.category == .motivation || question.category == .closing ? 12 : 20
        if metrics.wordCount < briefLimit { return .tooBrief }
        switch question.category {
        case .behavioral:
            if HeuristicEvaluator.starComponents(in: answer) < 2 { return .needsExample }
            if !HeuristicEvaluator.mentionsOutcome(answer) { return .needsOutcome }
        case .technical, .general:
            if metrics.wordCount < 40 && !HeuristicEvaluator.isSpecific(answer) { return .needsExample }
        case .opener, .situational, .motivation, .closing:
            break
        }
        return nil
    }
}
