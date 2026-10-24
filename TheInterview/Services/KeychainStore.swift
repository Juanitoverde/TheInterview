import Foundation
import Security

/// Stores the OpenAI API key in the Keychain rather than in preferences.
enum KeychainStore {
    private static let service = "com.theinterview.openai"
    private static let account = "api-key"

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    static func readAPIKey() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let key = String(data: data, encoding: .utf8)
        else { return nil }
        return key
    }

    /// Saves the key, or removes it when `key` is empty. Returns whether the Keychain accepted it.
    @discardableResult
    static func saveAPIKey(_ key: String) -> Bool {
        SecItemDelete(baseQuery as CFDictionary)
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        var query = baseQuery
        query[kSecValueData as String] = Data(trimmed.utf8)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }
}
