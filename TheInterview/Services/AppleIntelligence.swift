import Foundation
import InterviewCore
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Which language model writes questions, reactions and feedback.
enum AIProvider: String, Codable, CaseIterable, Identifiable {
    /// OpenAI when a key is saved, otherwise Apple Intelligence when available, otherwise built-in rules.
    case automatic
    case openAI
    case appleIntelligence
    case builtIn

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .automatic: "Automatic"
        case .openAI: "OpenAI"
        case .appleIntelligence: "Apple Intelligence (on device)"
        case .builtIn: "Built-in only"
        }
    }
}

/// Access to Apple's free on-device foundation model (visionOS 26 and later, with Apple Intelligence on).
enum AppleIntelligence {
    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(visionOS 26.0, *) {
            return AppleIntelligenceClient.isModelAvailable
        }
        #endif
        return false
    }

    static func client() -> (any LanguageModelClient)? {
        #if canImport(FoundationModels)
        if #available(visionOS 26.0, *), AppleIntelligenceClient.isModelAvailable {
            return AppleIntelligenceClient()
        }
        #endif
        return nil
    }
}

#if canImport(FoundationModels)
/// Runs prompts on the on-device model. It's free and private, but smaller than cloud models,
/// so prompts include shorter answer excerpts.
@available(visionOS 26.0, *)
struct AppleIntelligenceClient: LanguageModelClient {
    static var isModelAvailable: Bool { SystemLanguageModel.default.isAvailable }

    var modelName: String { "Apple Intelligence (on device)" }
    var analysisSource: AnalysisSource { .appleIntelligence }
    var maxAnswerCharacters: Int { 600 }

    func completeJSON(system: String, user: String, timeout: TimeInterval) async throws -> Data {
        let session = LanguageModelSession(instructions: system)
        let content = try await withTimeout(seconds: max(timeout, 15)) {
            try await session.respond(to: user).content
        }
        return Data(JSONText.extractObject(from: content).utf8)
    }
}
#endif
