//
//  StatsServiceTests.swift
//  SnowlyTests
//
//  Tests for StatsService pure functions.
//

import Testing
import Foundation
@testable import Snowly

struct StatsServiceTests {

    // MARK: - Aggregate Stats

    @Test func aggregateStats_emptySessions() {
        let stats = StatsService.aggregateStats(from: [])
        #expect(stats.totalSessions == 0)
        #expect(stats.totalRuns == 0)
        #expect(stats.totalDistance == 0)
        #expect(stats.totalVertical == 0)
        #expect(stats.maxSpeed == 0)
    }

    @Test func aggregateStats_singleSession() {
        let session = SkiSession(
            startDate: Date(),
            endDate: Date().addingTimeInterval(3600),
            totalDistance: 5000,
            totalVertical: 1200,
            maxSpeed: 15.0,
            runCount: 8
        )

        let stats = StatsService.aggregateStats(from: [session])
        #expect(stats.totalSessions == 1)
        #expect(stats.totalRuns == 8)
        #expect(stats.totalDistance == 5000)
        #expect(stats.totalVertical == 1200)
        #expect(stats.maxSpeed == 15.0)
        #expect(stats.averageRunsPerSession == 8.0)
    }

    @Test func aggregateStats_multipleSessions() {
        let s1 = SkiSession(
            totalDistance: 5000,
            totalVertical: 1200,
            maxSpeed: 15.0,
            runCount: 8
        )
        let s2 = SkiSession(
            totalDistance: 3000,
            totalVertical: 800,
            maxSpeed: 20.0,
            runCount: 5
        )

        let stats = StatsService.aggregateStats(from: [s1, s2])
        #expect(stats.totalSessions == 2)
        #expect(stats.totalRuns == 13)
        #expect(stats.totalDistance == 8000)
        #expect(stats.totalVertical == 2000)
        #expect(stats.maxSpeed == 20.0)
        #expect(stats.averageRunsPerSession == 6.5)
    }

    // MARK: - Personal Bests

    @Test func checkPersonalBests_allNew() {
        let session = SkiSession(
            totalDistance: 5000,
            totalVertical: 1200,
            maxSpeed: 15.0,
            runCount: 8
        )
        let profile = UserProfile()

        let records = StatsService.checkPersonalBests(session: session, profile: profile)
        #expect(records.count == 3)
        #expect(records.contains("Max Speed"))
        #expect(records.contains("Vertical Drop"))
        #expect(records.contains("Distance"))
    }

    @Test func checkPersonalBests_noNew() {
        let session = SkiSession(
            totalDistance: 3000,
            totalVertical: 800,
            maxSpeed: 10.0,
            runCount: 5
        )
        let profile = UserProfile(
            personalBestMaxSpeed: 20.0,
            personalBestVertical: 2000,
            personalBestDistance: 10000
        )

        let records = StatsService.checkPersonalBests(session: session, profile: profile)
        #expect(records.isEmpty)
    }

    @Test func checkPersonalBests_partialNew() {
        let session = SkiSession(
            totalDistance: 3000,
            totalVertical: 2500,  // new best
            maxSpeed: 25.0,       // new best
            runCount: 5
        )
        let profile = UserProfile(
            personalBestMaxSpeed: 20.0,
            personalBestVertical: 2000,
            personalBestDistance: 10000
        )

        let records = StatsService.checkPersonalBests(session: session, profile: profile)
        #expect(records.count == 2)
        #expect(records.contains("Max Speed"))
        #expect(records.contains("Vertical Drop"))
    }

    @Test func computePersonalBestUpdates_returnsOnlyImproved() {
        let session = SkiSession(
            totalDistance: 9000,   // new best
            totalVertical: 1500,   // not a best
            maxSpeed: 30.0,        // new best
            runCount: 10
        )
        let profile = UserProfile(
            personalBestMaxSpeed: 20.0,
            personalBestVertical: 2000,
            personalBestDistance: 5000
        )

        let update = StatsService.computePersonalBestUpdates(session: session, profile: profile)

        #expect(update.maxSpeed == 30.0)
        #expect(update.vertical == nil)
        #expect(update.distance == 9000)
        #expect(update.hasUpdates == true)
    }

    @Test func applyPersonalBestUpdate_updatesProfile() {
        let profile = UserProfile(
            personalBestMaxSpeed: 20.0,
            personalBestVertical: 2000,
            personalBestDistance: 5000
        )

        let update = StatsService.PersonalBestUpdate(
            maxSpeed: 30.0,
            vertical: nil,
            distance: 9000
        )

        StatsService.applyPersonalBestUpdate(update, to: profile)

        #expect(profile.personalBestMaxSpeed == 30.0)
        #expect(profile.personalBestVertical == 2000)
        #expect(profile.personalBestDistance == 9000)
    }

    @Test func personalBestUpdate_noUpdates() {
        let update = StatsService.PersonalBestUpdate(
            maxSpeed: nil,
            vertical: nil,
            distance: nil
        )
        #expect(update.hasUpdates == false)
    }

    @Test func resetPersonalBests_clearsAllFields() {
        let profile = UserProfile(
            personalBestMaxSpeed: 30.0,
            personalBestVertical: 2500,
            personalBestDistance: 9000
        )

        StatsService.resetPersonalBests(for: profile)

        #expect(profile.personalBestMaxSpeed == 0)
        #expect(profile.personalBestVertical == 0)
        #expect(profile.personalBestDistance == 0)
    }

    // MARK: - Season Bests

    @Test func checkSeasonBests_allNew() {
        let session = SkiSession(
            totalDistance: 5000,
            totalVertical: 1200,
            maxSpeed: 15.0,
            runCount: 8
        )
        let profile = UserProfile()

        let records = StatsService.checkSeasonBests(session: session, profile: profile)
        #expect(records.count == 3)
        #expect(records.contains("Max Speed"))
        #expect(records.contains("Vertical Drop"))
        #expect(records.contains("Distance"))
    }

    @Test func checkSeasonBests_noNew() {
        let session = SkiSession(
            totalDistance: 3000,
            totalVertical: 800,
            maxSpeed: 10.0,
            runCount: 5
        )
        let profile = UserProfile(
            seasonBestMaxSpeed: 20.0,
            seasonBestVertical: 2000,
            seasonBestDistance: 10000
        )

        let records = StatsService.checkSeasonBests(session: session, profile: profile)
        #expect(records.isEmpty)
    }

    @Test func checkSeasonBests_partialNew() {
        let session = SkiSession(
            totalDistance: 3000,
            totalVertical: 2500,  // new best
            maxSpeed: 25.0,       // new best
            runCount: 5
        )
        let profile = UserProfile(
            seasonBestMaxSpeed: 20.0,
            seasonBestVertical: 2000,
            seasonBestDistance: 10000
        )

        let records = StatsService.checkSeasonBests(session: session, profile: profile)
        #expect(records.count == 2)
        #expect(records.contains("Max Speed"))
        #expect(records.contains("Vertical Drop"))
    }

    @Test func computeSeasonBestUpdates_returnsOnlyImproved() {
        let session = SkiSession(
            totalDistance: 9000,   // new best
            totalVertical: 1500,   // not a best
            maxSpeed: 30.0,        // new best
            runCount: 10
        )
        let profile = UserProfile(
            seasonBestMaxSpeed: 20.0,
            seasonBestVertical: 2000,
            seasonBestDistance: 5000
        )

        let update = StatsService.computeSeasonBestUpdates(session: session, profile: profile)

        #expect(update.maxSpeed == 30.0)
        #expect(update.vertical == nil)
        #expect(update.distance == 9000)
        #expect(update.hasUpdates == true)
    }

    @Test func applySeasonBestUpdate_updatesProfile() {
        let profile = UserProfile(
            seasonBestMaxSpeed: 20.0,
            seasonBestVertical: 2000,
            seasonBestDistance: 5000
        )

        let update = StatsService.SeasonBestUpdate(
            maxSpeed: 30.0,
            vertical: nil,
            distance: 9000
        )

        StatsService.applySeasonBestUpdate(update, to: profile)

        #expect(profile.seasonBestMaxSpeed == 30.0)
        #expect(profile.seasonBestVertical == 2000)
        #expect(profile.seasonBestDistance == 9000)
    }

    @Test func seasonBestUpdate_noUpdates() {
        let update = StatsService.SeasonBestUpdate(
            maxSpeed: nil,
            vertical: nil,
            distance: nil
        )
        #expect(update.hasUpdates == false)
    }

    @Test func resetSeasonBests_clearsAllFields() {
        let profile = UserProfile(
            seasonBestMaxSpeed: 30.0,
            seasonBestVertical: 2500,
            seasonBestDistance: 9000
        )

        StatsService.resetSeasonBests(for: profile)

        #expect(profile.seasonBestMaxSpeed == 0)
        #expect(profile.seasonBestVertical == 0)
        #expect(profile.seasonBestDistance == 0)
    }

    // MARK: - Gear Usage

    @Test func gearUsageSummary_emptySessions_returnsEmptySummary() {
        let setupId = UUID()

        let summary = StatsService.gearUsageSummary(for: setupId, sessions: [])

        #expect(summary.setupId == setupId)
        #expect(summary.skiDays == 0)
        #expect(summary.totalDistance == 0)
        #expect(summary.totalVertical == 0)
        #expect(summary.totalRuns == 0)
        #expect(summary.lastUsedDate == nil)
        #expect(summary.recentSessionIDs.isEmpty)
    }

    @Test func gearUsageSummary_countsUniqueDaysAndSkipsUnqualifiedSessions() {
        let setupId = UUID()
        let otherSetupId = UUID()
        let dayOneMorning = Date(timeIntervalSince1970: 1_700_000_000)
        let dayOneAfternoon = dayOneMorning.addingTimeInterval(3_600 * 4)
        let dayTwo = dayOneMorning.addingTimeInterval(86_400)

        let morning = SkiSession(
            startDate: dayOneMorning,
            endDate: dayOneMorning.addingTimeInterval(7_200),
            totalDistance: 10_000,
            totalVertical: 1_200,
            maxSpeed: 20,
            runCount: 8,
            gearSetupId: setupId,
            gearSetupSnapshotName: "Groomer"
        )
        let afternoon = SkiSession(
            startDate: dayOneAfternoon,
            endDate: dayOneAfternoon.addingTimeInterval(5_400),
            totalDistance: 8_000,
            totalVertical: 900,
            maxSpeed: 18,
            runCount: 6,
            gearSetupId: setupId,
            gearSetupSnapshotName: "Groomer"
        )
        let nextDay = SkiSession(
            startDate: dayTwo,
            endDate: dayTwo.addingTimeInterval(6_000),
            totalDistance: 12_000,
            totalVertical: 1_500,
            maxSpeed: 22,
            runCount: 10,
            gearSetupId: setupId,
            gearSetupSnapshotName: "Groomer"
        )
        let otherSetup = SkiSession(
            startDate: dayTwo.addingTimeInterval(3_600),
            endDate: dayTwo.addingTimeInterval(7_200),
            totalDistance: 5_000,
            totalVertical: 700,
            maxSpeed: 16,
            runCount: 4,
            gearSetupId: otherSetupId,
            gearSetupSnapshotName: "Powder"
        )
        let unqualified = SkiSession(
            startDate: dayTwo.addingTimeInterval(10_000),
            endDate: dayTwo.addingTimeInterval(11_000),
            totalDistance: 0,
            totalVertical: 0,
            maxSpeed: 0,
            runCount: 0,
            gearSetupId: setupId,
            gearSetupSnapshotName: "Groomer"
        )

        let summary = StatsService.gearUsageSummary(
            for: setupId,
            sessions: [morning, afternoon, nextDay, otherSetup, unqualified]
        )

        #expect(summary.skiDays == 2)
        #expect(summary.totalRuns == 24)
        #expect(summary.totalDistance == 30_000)
        #expect(summary.totalVertical == 3_600)
        #expect(summary.lastUsedDate == dayTwo)
        #expect(summary.recentSessionIDs.count == 3)
    }

    @Test func gearAssetUsageSummary_withoutLinkedSetup_returnsEmptySummary() {
        let asset = GearAsset(name: "Daily Driver", category: .skis)

        let summary = StatsService.gearAssetUsageSummary(for: asset, sessions: [])

        #expect(summary.assetId == asset.id)
        #expect(summary.skiDays == 0)
        #expect(summary.totalRuns == 0)
        #expect(summary.lastUsedDate == nil)
    }

    @Test func gearAssetUsageSummary_followsSetupLinkedSessions() {
        let setup = GearSetup(name: "Frontside")
        let asset = GearAsset(name: "Frontside Skis", category: .skis)
        asset.setupIDs = [setup.id]
        let start = Date(timeIntervalSince1970: 1_700_100_000)

        let qualifying = SkiSession(
            startDate: start,
            endDate: start.addingTimeInterval(10_000),
            totalDistance: 18_000,
            totalVertical: 2_500,
            maxSpeed: 22,
            runCount: 11,
            gearSetupId: setup.id
        )
        let ignored = SkiSession(
            startDate: start.addingTimeInterval(-86_400),
            endDate: start.addingTimeInterval(-76_400),
            totalDistance: 9_000,
            totalVertical: 1_100,
            maxSpeed: 18,
            runCount: 6,
            gearSetupId: UUID()
        )

        let summary = StatsService.gearAssetUsageSummary(for: asset, sessions: [qualifying, ignored])

        #expect(summary.assetId == asset.id)
        #expect(summary.skiDays == 1)
        #expect(summary.totalRuns == 11)
        #expect(summary.totalDistance == 18_000)
        #expect(summary.totalVertical == 2_500)
        #expect(summary.lastUsedDate == start)
    }

    @Test func gearMaintenanceStatus_skiDayRule_becomesDueSoonAndTracksRemainingDays() {
        let setup = GearSetup(name: "Daily Driver")
        let asset = GearAsset(
            name: "Skis",
            category: .skis,
            dueRuleType: .skiDays,
            dueEverySkiDays: 6
        )
        asset.setupIDs = [setup.id]
        let serviceDate = Date(timeIntervalSince1970: 1_700_200_000)
        let service = GearMaintenanceEvent(type: .wax, date: serviceDate, asset: asset)
        asset.maintenanceEvents.append(service)

        let sessions = (1...5).map { offset -> SkiSession in
            let day = serviceDate.addingTimeInterval(TimeInterval(offset * 86_400))
            return SkiSession(
                startDate: day,
                endDate: day.addingTimeInterval(8_000),
                totalDistance: 10_000,
                totalVertical: 1_200,
                maxSpeed: 20,
                runCount: 7,
                gearSetupId: setup.id
            )
        }

        let status = StatsService.gearMaintenanceStatus(for: asset, sessions: sessions)

        #expect(status.assetId == asset.id)
        #expect(status.state == .dueSoon)
        #expect(status.skiDaysSinceService == 5)
        #expect(status.remainingSkiDays == 1)
        #expect(status.lastServiceDate == serviceDate)
    }

    @Test func gearMaintenanceStatus_dateRule_becomesOverdueAfterDueDate() {
        let setup = GearSetup(name: "Powder")
        let asset = GearAsset(
            name: "Powder Boots",
            category: .boots,
            dueRuleType: .date,
            dueDate: Date(timeIntervalSince1970: 1_700_300_000)
        )
        asset.setupIDs = [setup.id]
        let now = Date(timeIntervalSince1970: 1_700_300_000 + 86_400)

        let status = StatsService.gearMaintenanceStatus(for: asset, sessions: [], now: now)

        #expect(status.assetId == asset.id)
        #expect(status.state == .overdue)
        #expect(status.dueDate == asset.dueDate)
        #expect(status.remainingSkiDays == nil)
    }
}
