import Foundation
import Security

enum BrowserCredentialKeychainError: LocalizedError {
    case unexpectedPasswordData
    case unhandledStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .unexpectedPasswordData:
            return "The stored password could not be decoded."
        case .unhandledStatus(let status):
            return SecCopyErrorMessageString(status, nil) as String? ?? "Keychain error \(status)."
        }
    }
}

enum BrowserCredentialKeychain {
    static func savePassword(_ password: String, for credential: StoredLoginCredential) throws {
        let passwordData = Data(password.utf8)
        var query = baseQuery(for: credential)
        query[kSecValueData as String] = passwordData

        let addStatus = SecItemAdd(query as CFDictionary, nil)
        if addStatus == errSecSuccess {
            return
        }

        if addStatus == errSecDuplicateItem {
            try updatePassword(password, for: credential)
            return
        }

        throw BrowserCredentialKeychainError.unhandledStatus(addStatus)
    }

    static func updatePassword(_ password: String, for credential: StoredLoginCredential) throws {
        let update: [String: Any] = [
            kSecValueData as String: Data(password.utf8)
        ]

        let status = SecItemUpdate(matchQuery(for: credential) as CFDictionary, update as CFDictionary)
        guard status == errSecSuccess else {
            throw BrowserCredentialKeychainError.unhandledStatus(status)
        }
    }

    static func password(for credential: StoredLoginCredential) throws -> String {
        var query = matchQuery(for: credential)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else {
            throw BrowserCredentialKeychainError.unhandledStatus(status)
        }

        guard let data = item as? Data,
              let password = String(data: data, encoding: .utf8) else {
            throw BrowserCredentialKeychainError.unexpectedPasswordData
        }

        return password
    }

    static func deletePassword(for credential: StoredLoginCredential) throws {
        let status = SecItemDelete(matchQuery(for: credential) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw BrowserCredentialKeychainError.unhandledStatus(status)
        }
    }

    private static func baseQuery(for credential: StoredLoginCredential) -> [String: Any] {
        var query = matchQuery(for: credential)
        query[kSecAttrLabel as String] = "Browser password for \(credential.displayHost)"
        query[kSecAttrDescription as String] = "Website password saved by Browser"
        return query
    }

    private static func matchQuery(for credential: StoredLoginCredential) -> [String: Any] {
        var query: [String: Any] = [
            kSecUseDataProtectionKeychain as String: true,
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrServer as String: credential.host,
            kSecAttrAccount as String: credential.username
        ]

        if let protocolValue = protocolValue(for: credential.scheme) {
            query[kSecAttrProtocol as String] = protocolValue
        }

        if let port = credential.port {
            query[kSecAttrPort as String] = port
        }

        return query
    }

    private static func protocolValue(for scheme: String) -> CFString? {
        switch scheme.lowercased() {
        case "http":
            return kSecAttrProtocolHTTP
        case "https":
            return kSecAttrProtocolHTTPS
        default:
            return nil
        }
    }
}
