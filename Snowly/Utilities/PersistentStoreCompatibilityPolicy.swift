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
    /// - First launch always skips CloudKit so local schema setup completes first.
    /// - If migration stages exist, trust SwiftData migration and preserve stores.
    /// - If no migration stages exist, treat a stamp change as incompatible and reset.
    nonisolated static func evaluate(
        storedStamp: String?,
        currentStamp: String,
        storeFilesExist: Bool,
        hasMigrationStages: Bool
    ) -> Decision {
        guard let storedStamp else {
            return Decision(
                shouldResetStores: storeFilesExist && !hasMigrationStages,
                shouldSkipCloudKit: true
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

        return Decision(
            shouldResetStores: storeFilesExist,
            shouldSkipCloudKit: storeFilesExist
        )
    }
}
