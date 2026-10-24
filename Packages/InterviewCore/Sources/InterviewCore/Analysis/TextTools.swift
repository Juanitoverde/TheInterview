import Foundation

enum TextTools {
    /// Replaces typographic apostrophes so "I’m" and "I'm" match the same patterns.
    static func normalizeApostrophes(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{2019}", with: "'").replacingOccurrences(of: "\u{2018}", with: "'")
    }

    /// Lowercased word tokens (letters, digits, inner apostrophes, and separators inside numbers such as
    /// "80,000" or "2.5"), with other punctuation removed.
    static func words(in text: String) -> [String] {
        var words: [String] = []
        var current = ""
        let characters = Array(normalizeApostrophes(text).lowercased())
        for (index, character) in characters.enumerated() {
            let isNumberSeparator = (character == "," || character == ".")
                && current.last?.isNumber == true
                && index + 1 < characters.count && characters[index + 1].isNumber
            if character.isLetter || character.isNumber || isNumberSeparator || (character == "'" && !current.isEmpty) {
                current.append(character)
            } else if !current.isEmpty {
                words.append(current.trimmingCharacters(in: CharacterSet(charactersIn: "'")))
                current = ""
            }
        }
        if !current.isEmpty {
            words.append(current.trimmingCharacters(in: CharacterSet(charactersIn: "'")))
        }
        return words.filter { !$0.isEmpty }
    }

    static func sentenceCount(in text: String) -> Int {
        let pieces = text.split { ".!?".contains($0) }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return max(pieces.count, text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0 : 1)
    }

    static func countMatches(of pattern: String, in text: String) -> Int {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return 0 }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.numberOfMatches(in: text, options: [], range: range)
    }

    static func containsDigits(_ text: String) -> Bool {
        text.contains { $0.isNumber }
    }

    static let stopwords: Set<String> = [
        "a", "about", "after", "all", "also", "an", "and", "any", "are", "as", "at", "be", "been", "being", "but", "by",
        "can", "could", "did", "do", "does", "doing", "for", "from", "had", "has", "have", "how", "i", "if", "in", "into",
        "is", "it", "its", "just", "me", "more", "most", "my", "of", "on", "or", "other", "our", "out", "over", "so",
        "some", "such", "than", "that", "the", "their", "them", "then", "there", "these", "they", "this", "those", "to",
        "up", "us", "very", "was", "we", "were", "what", "when", "where", "which", "while", "who", "why", "will", "with",
        "would", "you", "your", "tell", "describe", "time", "give", "example", "walk", "through", "think", "like",
        "something", "someone", "situation", "handle", "handled", "role", "position", "work", "job", "really",
    ]

    /// Distinctive words (length ≥ 4, not stopwords) used for rough relevance checks.
    static func contentWords(in text: String) -> Set<String> {
        Set(words(in: text).filter { $0.count >= 4 && !stopwords.contains($0) }.map(stem))
    }

    /// A deliberately tiny stemmer: enough to match "troubleshooting" with "troubleshoot".
    static func stem(_ word: String) -> String {
        for suffix in ["ing", "ed", "es", "s", "ly"] where word.count > suffix.count + 3 && word.hasSuffix(suffix) {
            return String(word.dropLast(suffix.count))
        }
        return word
    }

    static let acronyms: Set<String> = [
        "it", "qa", "hr", "ux", "ui", "ai", "ml", "cnc", "hvac", "rn", "lpn", "cna", "emt", "ceo", "cto", "cfo", "coo",
        "vp", "seo", "sql", "aws", "ios", "pr", "gis", "cad", "plc", "devops", "sre", "bi", "erp", "crm", "pm", "ehs",
    ]

    static let lowercaseTitleWords: Set<String> = ["of", "and", "for", "in", "the", "to", "a", "an", "at", "on", "with"]

    /// Formats a spoken job title: "technical mechanic" → "Technical Mechanic", "it support" → "IT Support".
    /// Tokens that already contain inner capitals (from the recogniser) keep their casing.
    static func jobTitleCase(_ tokens: [String]) -> String {
        tokens.enumerated().map { index, token in
            let lower = token.lowercased()
            if acronyms.contains(lower) { return lower == "devops" ? "DevOps" : lower == "ios" ? "iOS" : lower.uppercased() }
            if token.dropFirst().contains(where: \.isUppercase) { return token }
            if index > 0 && lowercaseTitleWords.contains(lower) { return lower }
            return lower.prefix(1).uppercased() + lower.dropFirst()
        }.joined(separator: " ")
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }

    var nilIfBlank: String? {
        let value = trimmed
        return value.isEmpty ? nil : value
    }
}
