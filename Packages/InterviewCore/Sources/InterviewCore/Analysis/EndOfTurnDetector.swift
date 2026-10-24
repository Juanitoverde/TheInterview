import Foundation

/// Decides how much silence means the candidate has finished speaking, based on what they've said so far.
///
/// A fixed silence timeout either cuts people off while they think or leaves them waiting after a
/// finished answer. This adapts it: trailing off mid-thought ("…and", "um", "let me think") earns
/// more time, while a finished sentence after a substantial answer earns less.
public enum EndOfTurnDetector {
    static let thinkingPhrases = [
        "let me think", "let me see", "give me a second", "give me a moment", "good question", "that's a good question",
        "how do i put this", "hmm", "um", "umm", "uh", "er", "well",
    ]

    /// Words that, when last, signal the sentence isn't finished.
    static let continuers: Set<String> = [
        "and", "but", "so", "because", "or", "then", "which", "that", "when", "while", "if", "like", "the", "a", "an",
        "to", "of", "with", "for", "my", "our", "their", "was", "were", "is", "also", "plus", "after", "before",
    ]

    /// Seconds of silence to wait before treating the reply as finished.
    /// - Parameters:
    ///   - transcript: what has been recognised so far.
    ///   - base: the configured silence timeout.
    ///   - isAnswer: true for interview answers, false for short replies.
    public static func silenceNeeded(after transcript: String, base: TimeInterval, isAnswer: Bool) -> TimeInterval {
        let words = TextTools.words(in: transcript)
        guard let last = words.last else { return base }
        let tail = words.suffix(5).joined(separator: " ")

        if thinkingPhrases.contains(where: { tail.hasSuffix($0) }) {
            return base * 1.8
        }
        if continuers.contains(last) {
            return base * 1.5
        }
        let endsSentence = transcript.trimmingCharacters(in: .whitespacesAndNewlines).last.map { ".!?".contains($0) } ?? false
        // People often pause after a first sentence to gather their thoughts, so only shorten
        // once an answer has some substance.
        if endsSentence && (!isAnswer || words.count >= 25) {
            return max(base * 0.7, 1.2)
        }
        return base
    }
}
