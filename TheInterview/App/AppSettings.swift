import Foundation
import InterviewCore

/// User preferences, persisted in UserDefaults. The OpenAI key is stored separately in the Keychain.
struct AppSettings: Codable, Equatable {
    var candidateName = ""
    var formOfAddress: FormOfAddress = .firstName
    var presetPosition = ""
    var questionCount = 5
    var difficulty: Difficulty = .intermediate
    var focus: InterviewFocus = .balanced
    var companyName = "Meridian Works"
    var openAIModel = OpenAIClient.defaultModel
    var usesAIReactions = true
    /// Fade between rooms instead of the guided walk, for people sensitive to motion in VR.
    var comfortMode = false
    /// Shows a small live indicator of whether you're facing the interviewer.
    var showsLiveEyeContact = false
    /// AVSpeechUtterance rate (0...1).
    var speechRate = 0.48
    /// Seconds of silence that end an answer.
    var answerSilenceTimeout = 5.0

    private static let defaultsKey = "TheInterview.settings"

    static func load(from defaults: UserDefaults = .standard) -> AppSettings {
        guard let data = defaults.data(forKey: defaultsKey),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data)
        else { return AppSettings() }
        return settings
    }

    func save(to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) {
            defaults.set(data, forKey: Self.defaultsKey)
        }
    }

    var candidate: CandidateProfile {
        CandidateProfile(fullName: candidateName.trimmingCharacters(in: .whitespacesAndNewlines), formOfAddress: formOfAddress)
    }

    var interviewConfiguration: InterviewConfiguration {
        let position = presetPosition.trimmingCharacters(in: .whitespacesAndNewlines)
        let company = companyName.trimmingCharacters(in: .whitespacesAndNewlines)
        return InterviewConfiguration(
            questionCount: questionCount,
            difficulty: difficulty,
            focus: focus,
            companyName: company.isEmpty ? "Meridian Works" : company,
            presetPosition: position.isEmpty ? nil : position,
            usesAIReactions: usesAIReactions,
            answerSilenceTimeout: answerSilenceTimeout
        )
    }
}
