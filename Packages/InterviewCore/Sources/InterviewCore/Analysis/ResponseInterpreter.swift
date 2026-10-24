import Foundation

public enum Readiness: Equatable, Sendable {
    case ready
    case notReady
    case unclear
}

/// Interprets the candidate's short spoken replies: the job title, "are you ready?", "can you repeat that?"
public enum ResponseInterpreter {
    // MARK: Position

    private static let leadingFillers: [[String]] = [
        ["hi"], ["hello"], ["hey"], ["um"], ["umm"], ["uh"], ["er"], ["well"], ["so"], ["yes"], ["yeah"], ["oh"],
        ["ok"], ["okay"], ["sure"], ["good"], ["morning"], ["afternoon"], ["evening"], ["thanks"], ["thank", "you"],
    ]

    private static let leadingPhrases: [[String]] = [
        ["i'm", "here", "to", "interview", "for"], ["i", "am", "here", "to", "interview", "for"],
        ["i'm", "interviewing", "for"], ["i", "am", "interviewing", "for"],
        ["i'd", "like", "to", "apply", "for"], ["i", "would", "like", "to", "apply", "for"],
        ["i", "want", "to", "apply", "for"], ["i", "applied", "for"],
        ["i'm", "applying", "for"], ["i", "am", "applying", "for"], ["im", "applying", "for"],
        ["i'm", "here", "for"], ["i", "am", "here", "for"], ["i'm", "applying", "to", "be"], ["i", "am", "applying", "to", "be"],
        ["applying", "for"], ["interviewing", "for"], ["here", "for"], ["i'm", "applying", "as"], ["applying", "as"],
        ["the", "position", "is"], ["position", "is"], ["the", "role", "is"], ["role", "is"], ["it's", "for"], ["it", "is", "for"],
        ["the", "position", "of"], ["the", "role", "of"], ["the", "job", "of"], ["a", "position", "as"], ["the", "position", "as"],
        ["position", "as"], ["role", "as"], ["job", "as"], ["i'm", "a"], ["i", "am", "a"], ["i'm", "an"], ["i", "am", "an"],
        ["for"], ["as"], ["the"], ["a"], ["an"], ["your"],
    ]

    private static let trailingPhrases: [[String]] = [
        ["position"], ["role"], ["job"], ["opening"], ["vacancy"], ["please"], ["thanks"], ["thank", "you"], ["today"],
        ["here"], ["interview"], ["with", "you"], ["at", "your", "company"],
    ]

    private static let nonAnswers: Set<String> = [
        "what", "sorry", "pardon", "huh", "i don't know", "i dont know", "not sure", "i'm not sure", "no", "nothing",
        "repeat", "can you repeat that", "what did you say",
    ]

    /// Extracts a job title from a reply such as "I'm applying for a Technical Mechanic." → "Technical Mechanic".
    public static func extractPosition(from reply: String) -> String? {
        let raw = TextTools.normalizeApostrophes(reply)
        let edgePunctuation = CharacterSet(charactersIn: ".,!?;:\"()[]")
        var tokens = raw.split(whereSeparator: \.isWhitespace)
            .map { String($0).trimmingCharacters(in: edgePunctuation) }
            .filter { !$0.isEmpty }
        guard !tokens.isEmpty else { return nil }

        if nonAnswers.contains(tokens.joined(separator: " ").lowercased()) { return nil }

        func lowered() -> [String] { tokens.map { $0.lowercased() } }

        var changed = true
        while changed, !tokens.isEmpty {
            changed = false
            for phrase in leadingFillers + leadingPhrases.sorted(by: { $0.count > $1.count }) where lowered().starts(with: phrase) {
                tokens.removeFirst(phrase.count)
                changed = true
                break
            }
        }
        changed = true
        while changed, !tokens.isEmpty {
            changed = false
            for phrase in trailingPhrases.sorted(by: { $0.count > $1.count }) where lowered().reversed().starts(with: phrase.reversed()) {
                tokens.removeLast(phrase.count)
                changed = true
                break
            }
        }

        guard !tokens.isEmpty, tokens.count <= 8 else { return nil }
        let title = TextTools.jobTitleCase(tokens)
        if nonAnswers.contains(title.lowercased()) { return nil }
        return String(title.prefix(80))
    }

    // MARK: Readiness

    private static let notReadyPhrases = [
        "not ready", "not yet", "hold on", "hang on", "one moment", "one second", "a moment", "a second", "a minute",
        "give me a", "just a sec", "wait", "not really", "nope",
    ]

    private static let readyPhrases = [
        "yes", "yeah", "yep", "yup", "sure", "ready", "absolutely", "definitely", "certainly", "of course", "let's go",
        "lets go", "let's begin", "let's start", "let's do it", "go ahead", "ok", "okay", "alright", "all right",
        "sounds good", "i am", "please", "let's get started", "fire away", "shoot", "i think so", "i guess so",
    ]

    public static func readiness(of reply: String) -> Readiness {
        let text = " " + TextTools.words(in: reply).joined(separator: " ") + " "
        guard text.trimmingCharacters(in: .whitespaces).isEmpty == false else { return .unclear }
        func contains(_ phrase: String) -> Bool { text.contains(" \(phrase) ") }

        if notReadyPhrases.contains(where: contains) { return .notReady }
        if readyPhrases.contains(where: contains) { return .ready }
        if contains("no") { return .notReady }
        return .unclear
    }

    // MARK: Repeat requests

    private static let repeatPhrases = [
        "repeat", "say that again", "say it again", "come again", "pardon", "didn't catch", "did not catch",
        "didn't hear", "did not hear", "one more time", "rephrase", "what was the question",
    ]

    /// True for short replies asking the interviewer to repeat the question.
    public static func isRepeatRequest(_ reply: String) -> Bool {
        let words = TextTools.words(in: reply)
        guard !words.isEmpty, words.count <= 14 else { return false }
        let text = words.joined(separator: " ")
        return repeatPhrases.contains { text.contains($0) }
    }

    // MARK: Finish cues

    private static let finishCues: [[String]] = [
        ["that's", "my", "answer"], ["that", "is", "my", "answer"], ["that", "concludes", "my", "answer"],
        ["end", "of", "answer"], ["end", "of", "my", "answer"], ["i'm", "done"], ["i", "am", "done"],
        ["i'm", "finished"], ["i", "am", "finished"], ["that's", "all"], ["that", "is", "all"],
    ]

    /// If the reply ends with a spoken cue like "that's my answer", returns the reply without it.
    public static func strippingFinishCue(from reply: String) -> (text: String, hadCue: Bool) {
        let words = TextTools.words(in: reply)
        for cue in finishCues.sorted(by: { $0.count > $1.count }) where words.count >= cue.count && Array(words.suffix(cue.count)) == cue {
            return (removeTrailingWords(cue.count, from: reply), true)
        }
        return (reply, false)
    }

    /// Removes the last `count` words from the original text while keeping its punctuation and casing.
    private static func removeTrailingWords(_ count: Int, from text: String) -> String {
        var remaining = count
        var index = text.endIndex
        var inWord = false
        while index > text.startIndex {
            let previous = text.index(before: index)
            let character = text[previous]
            let isWordCharacter = character.isLetter || character.isNumber || character == "'" || character == "\u{2019}"
            if isWordCharacter {
                inWord = true
            } else if inWord {
                remaining -= 1
                inWord = false
                if remaining == 0 { break }
            }
            index = previous
        }
        if inWord { remaining -= 1 }
        let kept = remaining <= 0 ? String(text[text.startIndex..<index]) : ""
        return kept.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ",;:-")))
    }
}
