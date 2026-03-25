//
//  PersistentStoreCompatibilityPolicyTests.swift
//  SnowlyTests
//
//  Tests for store reset vs migration launch policy.
//

import Testing
@testable import Snowly

struct PersistentStoreCompatibilityPolicyTests {

    // MARK: - Existing scenarios (isReturningUser = false)

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

    // MARK: - Returning user scenarios

    @Test func returningUser_firstLaunch_noStores_enablesCloudKit() {
        let decision = PersistentStoreCompatibilityPolicy.evaluate(
            storedStamp: nil,
            currentStamp: "current",
            storeFilesExist: false,
            hasMigrationStages: false,
            isReturningUser: true
        )

        #expect(decision.shouldResetStores == false)
        #expect(decision.shouldSkipCloudKit == false)
    }

    @Test func returningUser_firstLaunch_withStores_resetsButEnablesCloudKit() {
        let decision = PersistentStoreCompatibilityPolicy.evaluate(
            storedStamp: nil,
            currentStamp: "current",
            storeFilesExist: true,
            hasMigrationStages: false,
            isReturningUser: true
        )

        #expect(decision.shouldResetStores == true)
        #expect(decision.shouldSkipCloudKit == false)
    }

    @Test func returningUser_stampChange_withoutMigration_resetsButEnablesCloudKit() {
        let decision = PersistentStoreCompatibilityPolicy.evaluate(
            storedStamp: "old",
            currentStamp: "new",
            storeFilesExist: true,
            hasMigrationStages: false,
            isReturningUser: true
        )

        #expect(decision.shouldResetStores == true)
        #expect(decision.shouldSkipCloudKit == false)
    }

    @Test func returningUser_stampChange_withMigration_preservesStores() {
        let decision = PersistentStoreCompatibilityPolicy.evaluate(
            storedStamp: "old",
            currentStamp: "new",
            storeFilesExist: true,
            hasMigrationStages: true,
            isReturningUser: true
        )

        #expect(decision.shouldResetStores == false)
        #expect(decision.shouldSkipCloudKit == false)
    }

    @Test func returningUser_matchingStamp_normalBehavior() {
        let decision = PersistentStoreCompatibilityPolicy.evaluate(
            storedStamp: "same",
            currentStamp: "same",
            storeFilesExist: true,
            hasMigrationStages: false,
            isReturningUser: true
        )

        #expect(decision.shouldResetStores == false)
        #expect(decision.shouldSkipCloudKit == false)
    }

    @Test func newUser_firstLaunch_noStores_skipsCloudKit() {
        let decision = PersistentStoreCompatibilityPolicy.evaluate(
            storedStamp: nil,
            currentStamp: "current",
            storeFilesExist: false,
            hasMigrationStages: false,
            isReturningUser: false
        )

        #expect(decision.shouldResetStores == false)
        #expect(decision.shouldSkipCloudKit == true)
    }

    @Test func returningUser_firstLaunch_withMigrationStages_noReset() {
        let decision = PersistentStoreCompatibilityPolicy.evaluate(
            storedStamp: nil,
            currentStamp: "current",
            storeFilesExist: true,
            hasMigrationStages: true,
            isReturningUser: true
        )

        #expect(decision.shouldResetStores == false)
        #expect(decision.shouldSkipCloudKit == false)
    }
}
