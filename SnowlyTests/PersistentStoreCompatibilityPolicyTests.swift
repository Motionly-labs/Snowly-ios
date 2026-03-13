//
//  PersistentStoreCompatibilityPolicyTests.swift
//  SnowlyTests
//
//  Tests for store reset vs migration launch policy.
//

import Testing
@testable import Snowly

struct PersistentStoreCompatibilityPolicyTests {

    @Test func firstLaunch_withNoStores_skipsCloudKitWithoutReset() {
        let decision = PersistentStoreCompatibilityPolicy.evaluate(
            storedStamp: nil,
            currentStamp: "current",
            storeFilesExist: false,
            hasMigrationStages: false
        )

        #expect(decision.shouldResetStores == false)
        #expect(decision.shouldSkipCloudKit == true)
    }

    @Test func firstTrackedLaunch_withoutMigrationStages_resetsExistingStores() {
        let decision = PersistentStoreCompatibilityPolicy.evaluate(
            storedStamp: nil,
            currentStamp: "current",
            storeFilesExist: true,
            hasMigrationStages: false
        )

        #expect(decision.shouldResetStores == true)
        #expect(decision.shouldSkipCloudKit == true)
    }

    @Test func stampChange_withMigrationStages_preservesStores() {
        let decision = PersistentStoreCompatibilityPolicy.evaluate(
            storedStamp: "old",
            currentStamp: "new",
            storeFilesExist: true,
            hasMigrationStages: true
        )

        #expect(decision.shouldResetStores == false)
        #expect(decision.shouldSkipCloudKit == false)
    }

    @Test func stampChange_withoutMigrationStages_resetsStores() {
        let decision = PersistentStoreCompatibilityPolicy.evaluate(
            storedStamp: "old",
            currentStamp: "new",
            storeFilesExist: true,
            hasMigrationStages: false
        )

        #expect(decision.shouldResetStores == true)
        #expect(decision.shouldSkipCloudKit == true)
    }

    @Test func matchingStamp_keepsStoresAndCloudKitBehavior() {
        let decision = PersistentStoreCompatibilityPolicy.evaluate(
            storedStamp: "same",
            currentStamp: "same",
            storeFilesExist: true,
            hasMigrationStages: false
        )

        #expect(decision.shouldResetStores == false)
        #expect(decision.shouldSkipCloudKit == false)
    }
}
