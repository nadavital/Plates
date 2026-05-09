import Foundation
import Security

protocol SessionTokenStoring {
    func loadTokens(for userID: String) -> BackendSessionTokens?
    func saveTokens(_ tokens: BackendSessionTokens, for userID: String)
    func deleteTokens(for userID: String)
}

final class KeychainSessionTokenStore: SessionTokenStoring {
    private let service: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(service: String = Bundle.main.bundleIdentifier ?? "app.trai.session") {
        self.service = "\(service).backend-session"
    }

    func loadTokens(for userID: String) -> BackendSessionTokens? {
        var query = baseQuery(for: userID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data else {
            return nil
        }

        return try? decoder.decode(BackendSessionTokens.self, from: data)
    }

    func saveTokens(_ tokens: BackendSessionTokens, for userID: String) {
        guard let data = try? encoder.encode(tokens) else { return }

        SecItemDelete(baseQuery(for: userID) as CFDictionary)

        var attributes = baseQuery(for: userID)
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(attributes as CFDictionary, nil)
    }

    func deleteTokens(for userID: String) {
        SecItemDelete(baseQuery(for: userID) as CFDictionary)
    }

    private func baseQuery(for userID: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: userID
        ]
    }
}

