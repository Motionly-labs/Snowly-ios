//
//  PersistentStoreCompatibilityPolicy.swift
//  Snowly
//
//  Decides whether an on-disk SwiftData store should be migrated,
//  preserved, or reset before launch.
//

import Foundation

enum PersistentStoreCompatibilityPolicy {
    struct Decision: Equatable {
        let shouldResetStores: Bool
        let shouldSkipCloudKit: Bool
    }

    /// Decides whether launch should reset incompatible stores.
    ///
    /// Rules:
    /// - First launch always skips CloudKit so local schema setup completes first,
    ///   **unless** the user is returning (Keychain fingerprint exists) — in that case
    ///   CloudKit must remain enabled so their data can sync back.
    /// - If migration stages exist, trust SwiftData migration and preserve stores.
    /// - If no migration stages exist, treat a stamp change as incompatible and reset.
    nonisolated static func evaluate(
        storedStamp: String?,
        currentStamp: String,
        storeFilesExist: Bool,
        hasMigrationStages: Bool,
        isReturningUser: Bool = false
    ) -> Decision {
        guard let storedStamp else {
            // First tracked launch.
            // Returning users need CloudKit enabled so their data can sync back
            // after a store reset or reinstall.
            let skipCloudKit = !isReturningUser
            return Decision(
                shouldResetStores: storeFilesExist && !hasMigrationStages,
                shouldSkipCloudKit: skipCloudKit
            )
        }

        guard storedStamp != currentStamp else {
            return Decision(
                shouldResetStores: false,
                shouldSkipCloudKit: false
            )
        }

        guard !hasMigrationStages else {
            return Decision(
                shouldResetStores: false,
                shouldSkipCloudKit: false
            )
        }

        // Stamp changed without migration stages — reset is needed.
        // Returning users still need CloudKit so they can recover.
        return Decision(
            shouldResetStores: storeFilesExist,
            shouldSkipCloudKit: storeFilesExist && !isReturningUser
        )
    }
}
