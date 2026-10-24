import Foundation

/// When one recognised word started and how long it lasted, in seconds from the start of its audio.
public struct WordTiming: Codable, Equatable, Sendable {
    public var start: Double
    public var duration: Double

    public init(start: Double, duration: Double) {
        self.start = start
        self.duration = duration
    }

    public var end: Double { start + duration }
}

/// Delivery measurements taken from word timings rather than estimated from the transcript.
public struct Prosody: Codable, Equatable, Sendable {
    /// Silences of at least `ProsodyAnalyzer.longPauseThreshold` seconds between words.
    public var longPauseCount: Int
    public var longestPause: Double
    /// From the first word's start to the last word's end, summed over each stretch of recognition.
    public var speakingSeconds: Double

    public init(longPauseCount: Int, longestPause: Double, speakingSeconds: Double) {
        self.longPauseCount = longPauseCount
        self.longestPause = longestPause
        self.speakingSeconds = speakingSeconds
    }

    static func combined(_ first: Prosody?, _ second: Prosody?) -> Prosody? {
        guard let first else { return second }
        guard let second else { return first }
        return Prosody(
            longPauseCount: first.longPauseCount + second.longPauseCount,
            longestPause: max(first.longestPause, second.longestPause),
            speakingSeconds: first.speakingSeconds + second.speakingSeconds
        )
    }
}

public enum ProsodyAnalyzer {
    /// A pause this long reads as hesitation rather than a natural breath.
    public static let longPauseThreshold = 2.0

    /// Analyses word timings. Each group is one stretch of recognition with its own time origin
    /// (the recogniser restarts during long answers), so gaps are only measured within a group.
    public static func analyze(_ groups: [[WordTiming]]) -> Prosody? {
        let groups = groups.map { $0.sorted { $0.start < $1.start } }.filter { !$0.isEmpty }
        guard !groups.isEmpty else { return nil }
        var pauses = 0
        var longest = 0.0
        var speaking = 0.0
        for words in groups {
            guard let first = words.first, let last = words.last else { continue }
            speaking += max(last.end - first.start, 0)
            for (current, next) in zip(words, words.dropFirst()) {
                let gap = next.start - current.end
                longest = max(longest, gap)
                if gap >= longPauseThreshold { pauses += 1 }
            }
        }
        guard speaking > 0 else { return nil }
        return Prosody(longPauseCount: pauses, longestPause: max(longest, 0), speakingSeconds: speaking)
    }
}
