import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public protocol HTTPTransport {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionTransport: HTTPTransport {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw OpenAIError.invalidResponse }
        return (data, http)
    }
}

public enum OpenAIError: Error, LocalizedError, Equatable {
    case missingAPIKey
    case http(status: Int, message: String)
    case invalidResponse
    case emptyContent
    case decoding(String)

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            "No OpenAI API key is configured."
        case let .http(status, message):
            status == 401 ? "OpenAI rejected the API key (401). \(message)" : "OpenAI returned an error (\(status)): \(message)"
        case .invalidResponse:
            "OpenAI returned an unexpected response."
        case .emptyContent:
            "OpenAI returned an empty response."
        case let .decoding(detail):
            "Couldn't read OpenAI's response: \(detail)"
        }
    }
}

/// A minimal client for OpenAI's Chat Completions API that asks for JSON replies.
public struct OpenAIClient {
    public static let defaultModel = "gpt-4.1-mini"
    public static let defaultBaseURL = URL(string: "https://api.openai.com/v1")!

    public var apiKey: String
    public var model: String
    public var baseURL: URL
    private let transport: HTTPTransport

    public init(apiKey: String, model: String = OpenAIClient.defaultModel, baseURL: URL = OpenAIClient.defaultBaseURL, transport: HTTPTransport = URLSessionTransport()) {
        self.apiKey = apiKey
        self.model = model.trimmed.isEmpty ? Self.defaultModel : model.trimmed
        self.baseURL = baseURL
        self.transport = transport
    }

    struct ChatRequest: Encodable {
        struct Message: Encodable {
            let role: String
            let content: String
        }

        struct ResponseFormat: Encodable {
            let type: String
        }

        let model: String
        let messages: [Message]
        let response_format: ResponseFormat
    }

    struct ChatResponse: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable {
                let content: String?
            }

            let message: Message
        }

        let choices: [Choice]
    }

    struct ErrorEnvelope: Decodable {
        struct Detail: Decodable {
            let message: String
        }

        let error: Detail
    }

    func makeRequest(system: String, user: String, timeout: TimeInterval) throws -> URLRequest {
        guard !apiKey.trimmed.isEmpty else { throw OpenAIError.missingAPIKey }
        var request = URLRequest(url: baseURL.appendingPathComponent("chat/completions"))
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("Bearer \(apiKey.trimmed)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Temperature and token limits are left at their defaults: several newer models reject custom values.
        let body = ChatRequest(
            model: model,
            messages: [.init(role: "system", content: system), .init(role: "user", content: user)],
            response_format: .init(type: "json_object")
        )
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }

    /// Sends a system + user prompt and returns the JSON object the model replied with.
    public func completeJSON(system: String, user: String, timeout: TimeInterval = 45) async throws -> Data {
        let request = try makeRequest(system: system, user: user, timeout: timeout)
        let (data, response) = try await transport.send(request)
        guard (200..<300).contains(response.statusCode) else {
            let message = (try? JSONDecoder().decode(ErrorEnvelope.self, from: data))?.error.message
                ?? String(data: data, encoding: .utf8)?.prefix(200).description
                ?? ""
            throw OpenAIError.http(status: response.statusCode, message: message)
        }
        let decoded: ChatResponse
        do {
            decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
        } catch {
            throw OpenAIError.decoding(error.localizedDescription)
        }
        guard let content = decoded.choices.first?.message.content?.nilIfBlank else { throw OpenAIError.emptyContent }
        return Data(Self.extractJSONObject(from: content).utf8)
    }

    /// Strips Markdown code fences or surrounding prose from a reply that should be a JSON object.
    static func extractJSONObject(from content: String) -> String {
        guard let start = content.firstIndex(of: "{"), let end = content.lastIndex(of: "}"), start < end else {
            return content
        }
        return String(content[start...end])
    }

    /// Makes a tiny request to check the key and model work.
    public func verify() async throws {
        _ = try await completeJSON(system: "Reply with JSON only.", user: "Return {\"ok\": true} as JSON.", timeout: 20)
    }
}
