import Foundation

public struct SpeechMetrics: Codable, Equatable, Sendable {
    public var wordCount: Int
    public var sentenceCount: Int
    public var speakingSeconds: Double
    /// `nil` for typed answers, where pace isn't meaningful.
    public var wordsPerMinute: Double?
    public var fillerCount: Int
    public var fillerWords: [String: Int]
    /// Phrases that soften an answer ("I think", "maybe", "kind of").
    public var hedgeCount: Int

    public init(
        wordCount: Int,
        sentenceCount: Int,
        speakingSeconds: Double,
        wordsPerMinute: Double?,
        fillerCount: Int,
        fillerWords: [String: Int],
        hedgeCount: Int
    ) {
        self.wordCount = wordCount
        self.sentenceCount = sentenceCount
        self.speakingSeconds = speakingSeconds
        self.wordsPerMinute = wordsPerMinute
        self.fillerCount = fillerCount
        self.fillerWords = fillerWords
        self.hedgeCount = hedgeCount
    }

    public static let empty = SpeechMetrics(
        wordCount: 0, sentenceCount: 0, speakingSeconds: 0, wordsPerMinute: nil, fillerCount: 0, fillerWords: [:], hedgeCount: 0
    )

    public var fillerRatio: Double {
        wordCount == 0 ? 0 : Double(fillerCount) / Double(wordCount)
    }

    public var averageSentenceLength: Double {
        sentenceCount == 0 ? 0 : Double(wordCount) / Double(sentenceCount)
    }
}

public enum SpeechAnalyzer {
    /// Typical comfortable interview pace.
    public static let idealWordsPerMinute = 110.0...170.0

    static let singleWordFillers: [String: String] = [
        "um": "um", "umm": "um", "uhm": "um", "uh": "uh", "uhh": "uh", "er": "er", "erm": "er",
        "ah": "ah", "hmm": "hmm", "mm": "hmm", "basically": "basically", "literally": "literally", "actually": "actually",
    ]

    /// Fillers that are only fillers in certain positions, matched against the punctuated transcript.
    static let patternFillers: [(name: String, pattern: String)] = [
        ("like", #"(^|[,.!?]\s*)like\s*,"#),
        ("you know", #"(,\s*you know\b)|(\byou know\s*,)"#),
        ("i mean", #"(^|[,.!?]\s*)i mean\b"#),
    ]

    static let hedgePatterns = [
        #"\bi think\b"#, #"\bi guess\b"#, #"\bmaybe\b"#, #"\bprobably\b"#, #"\bkind of\b"#, #"\bsort of\b"#,
        #"\bi'?m not sure\b"#, #"\bi don'?t know\b"#,
    ]

    public static func analyze(_ utterance: Utterance) -> SpeechMetrics {
        analyze(text: utterance.text, speakingSeconds: utterance.speakingDuration, method: utterance.method)
    }

    public static func analyze(text: String, speakingSeconds: Double, method: InputMethod) -> SpeechMetrics {
        let normalized = TextTools.normalizeApostrophes(text)
        let words = TextTools.words(in: normalized)
        guard !words.isEmpty else { return .empty }

        var fillers: [String: Int] = [:]
        for word in words {
            if let filler = singleWordFillers[word] {
                fillers[filler, default: 0] += 1
            }
        }
        if words.first == "so", words.count > 3 {
            fillers["so", default: 0] += 1
        }
        for (name, pattern) in patternFillers {
            let count = TextTools.countMatches(of: pattern, in: normalized)
            if count > 0 { fillers[name, default: 0] += count }
        }
        let hedges = hedgePatterns.reduce(0) { $0 + TextTools.countMatches(of: $1, in: normalized) }

        let seconds = max(speakingSeconds, 0)
        var wpm: Double?
        if method == .voice, seconds >= 3 {
            wpm = Double(words.count) / (seconds / 60)
        }

        return SpeechMetrics(
            wordCount: words.count,
            sentenceCount: TextTools.sentenceCount(in: normalized),
            speakingSeconds: seconds,
            wordsPerMinute: wpm,
            fillerCount: fillers.values.reduce(0, +),
            fillerWords: fillers,
            hedgeCount: hedges
        )
    }
}
