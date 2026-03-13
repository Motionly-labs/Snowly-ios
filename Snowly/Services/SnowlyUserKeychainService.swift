//
//  SnowlyUserKeychainService.swift
//  Snowly
//
//  Stores and retrieves user auth credentials for ski data upload.
//  Keeps apiToken and deviceSecret across app launches.
//

import Foundation
import Security
import os

struct SnowlyUserCredentials: Codable, Sendable {
    let userId: String
    let deviceSecret: String
    let apiToken: String
}

enum SnowlyUserKeychainService {
    private static let service = "com.Snowly.UserAuth"
    private static let account = "user-credentials"
    private static let logger = Logger(subsystem: "com.Snowly", category: "UserKeychain")

    static func save(_ credentials: SnowlyUserCredentials) throws {
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

    static func load() -> SnowlyUserCredentials? {
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

        return try? JSONDecoder().decode(SnowlyUserCredentials.self, from: data)
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
