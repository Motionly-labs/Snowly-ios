//
//  CrewKeychainService.swift
//  Snowly
//
//  Stores and retrieves crew auth credentials from the iOS Keychain.
//  Keeps memberToken across app launches.
//

import Foundation
import Security
import os

struct CrewCredentials: Codable, Sendable {
    let memberToken: String
    let crewId: String
    let userId: String
}

enum CrewKeychainService {
    private static let service = "com.Snowly.CrewAuth"
    private static let account = "crew-credentials"
    private static let logger = Logger(subsystem: "com.Snowly", category: "CrewKeychain")

    static func save(_ credentials: CrewCredentials) throws {
        let data = try JSONEncoder().encode(credentials)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]

        // Delete existing entry first
        SecItemDelete(query as CFDictionary)

        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            logger.error("Keychain save failed: \(status)")
            throw KeychainError.saveFailed(status)
        }
    }

    static func load() -> CrewCredentials? {
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
                logger.warning("Keychain load failed: \(status)")
            }
            return nil
        }

        return try? JSONDecoder().decode(CrewCredentials.self, from: data)
    }

    static func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }

    enum KeychainError: LocalizedError {
        case saveFailed(OSStatus)

        var errorDescription: String? {
            switch self {
            case .saveFailed(let status):
                return "Keychain save failed (OSStatus: \(status))"
            }
        }
    }
}
