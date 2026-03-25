//
//  UserIdentityKeychainService.swift
//  Snowly
//
//  Stores a lightweight fingerprint in the iOS Keychain so the app can
//  distinguish returning users from brand-new users after an uninstall/reinstall
//  or store reset.  Uses kSecAttrAccessibleAfterFirstUnlock so the data
//  persists across app deletions.
//

import Foundation
import Security
import os

struct UserIdentityFingerprint: Codable, Sendable {
    let profileId: UUID
    let createdAt: Date
}

enum UserIdentityKeychainService {
    private static let service = "com.Snowly.UserIdentity"
    private static let account = "user-fingerprint"
    private static let logger = Logger(subsystem: "com.Snowly", category: "UserIdentityKeychain")

    static func save(_ fingerprint: UserIdentityFingerprint) throws {
        let data = try JSONEncoder().encode(fingerprint)

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
            logger.error("Keychain save failed: \(status)")
            throw KeychainError.saveFailed(status)
        }
    }

    static func load() -> UserIdentityFingerprint? {
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

        return try? JSONDecoder().decode(UserIdentityFingerprint.self, from: data)
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
