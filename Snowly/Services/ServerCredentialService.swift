//
//  ServerCredentialService.swift
//  Snowly
//
//  Per-server Keychain credential storage.
//  Each server URL gets its own credential entry, replacing the
//  global SnowlyUserKeychainService for multi-server support.
//

import Foundation
import Security
import os

struct ServerCredential: Codable, Sendable {
    let serverURL: String
    let userId: String
    let username: String
    let deviceSecret: String
    let apiToken: String
}

enum ServerCredentialService {
    private static let service = "com.Snowly.ServerAuth"
    private static let logger = Logger(subsystem: "com.Snowly", category: "ServerCredential")

    static func save(_ credential: ServerCredential) throws {
        let data = try JSONEncoder().encode(credential)
        let account = normalizeURL(credential.serverURL)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]

        SecItemDelete(query as CFDictionary)

        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            logger.error("Keychain save failed for \(account, privacy: .public): \(status)")
            throw KeychainError.saveFailed(status)
        }
    }

    static func load(forServerURL url: String) -> ServerCredential? {
        let account = normalizeURL(url)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            if status != errSecItemNotFound {
                logger.warning("Keychain load failed for \(account, privacy: .public): \(status)")
            }
            return nil
        }

        return try? JSONDecoder().decode(ServerCredential.self, from: data)
    }

    static func update(apiToken: String? = nil, username: String? = nil, forServerURL url: String) throws {
        guard var credential = load(forServerURL: url) else {
            throw KeychainError.notFound
        }
        credential = ServerCredential(
            serverURL: credential.serverURL,
            userId: credential.userId,
            username: username ?? credential.username,
            deviceSecret: credential.deviceSecret,
            apiToken: apiToken ?? credential.apiToken
        )
        try save(credential)
    }

    static func delete(forServerURL url: String) {
        let account = normalizeURL(url)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }

    static func deleteAll() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
        SecItemDelete(query as CFDictionary)
    }

    /// Normalizes a URL to `scheme + host + port`, stripping path and trailing slash.
    static func normalizeURL(_ urlString: String) -> String {
        guard let components = URLComponents(string: urlString) else {
            return urlString
        }

        var normalized = "\(components.scheme ?? "https")://\(components.host ?? "")"
        if let port = components.port {
            normalized += ":\(port)"
        }
        return normalized
    }

    enum KeychainError: LocalizedError {
        case saveFailed(OSStatus)
        case notFound

        var errorDescription: String? {
            switch self {
            case .saveFailed(let status):
                return "Keychain save failed (OSStatus: \(status))"
            case .notFound:
                return "No credential found for this server"
            }
        }
    }
}
