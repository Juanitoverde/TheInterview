import Foundation

public enum Speaker: String, Codable, Sendable {
    case receptionist
    case interviewer
    case candidate
}

public struct TranscriptEntry: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var speaker: Speaker
    public var text: String
    public var timestamp: Date

    public init(id: UUID = UUID(), speaker: Speaker, text: String, timestamp: Date) {
        self.id = id
        self.speaker = speaker
        self.text = text
        self.timestamp = timestamp
    }
}

public enum InputMethod: String, Codable, Sendable {
    case voice
    case typed
    case none
}

/// One reply captured from the candidate, with the timing needed to compute speaking pace.
public struct Utterance: Codable, Equatable, Sendable {
    public var text: String
    public var method: InputMethod
    /// When the app started listening.
    public var startedAt: Date
    /// When listening ended.
    public var endedAt: Date
    /// When the first words were recognised.
    public var speechStartedAt: Date?
    /// When the last words were recognised.
    public var speechEndedAt: Date?
    /// Pauses and speaking time measured from word timings, when the recogniser provided them.
    public var prosody: Prosody?

    public init(
        text: String,
        method: InputMethod,
        startedAt: Date,
        endedAt: Date,
        speechStartedAt: Date? = nil,
        speechEndedAt: Date? = nil,
        prosody: Prosody? = nil
    ) {
        self.text = text
        self.method = method
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.speechStartedAt = speechStartedAt
        self.speechEndedAt = speechEndedAt
        self.prosody = prosody
    }

    public static func silence(startedAt: Date, endedAt: Date) -> Utterance {
        Utterance(text: "", method: .none, startedAt: startedAt, endedAt: endedAt)
    }

    public var isEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Seconds the candidate was actually talking: from word timings when available, then from when
    /// words were first and last recognised, then the whole listening window.
    public var speakingDuration: TimeInterval {
        if let measured = prosody?.speakingSeconds, measured > 0 {
            return measured
        }
        if let start = speechStartedAt, let end = speechEndedAt, end > start {
            return end.timeIntervalSince(start)
        }
        return max(endedAt.timeIntervalSince(startedAt), 0)
    }

    /// Joins a follow-up reply (e.g. after asking for the question to be repeated) onto this one.
    public func appending(_ other: Utterance) -> Utterance {
        if isEmpty { return other }
        if other.isEmpty { return self }
        return Utterance(
            text: text + " " + other.text,
            method: method == other.method ? method : .voice,
            startedAt: startedAt,
            endedAt: other.endedAt,
            speechStartedAt: speechStartedAt ?? other.speechStartedAt,
            speechEndedAt: other.speechEndedAt ?? speechEndedAt,
            prosody: Prosody.combined(prosody, other.prosody)
        )
    }

    public func replacingText(_ newText: String) -> Utterance {
        var copy = self
        copy.text = newText
        return copy
    }
}
