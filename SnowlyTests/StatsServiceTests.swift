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

    // MARK: - Season Stats

    @Test func seasonStats_emptySessions() {
        let stats = StatsService.seasonStats(from: [])
        #expect(stats.totalSessions == 0)
        #expect(stats.totalRuns == 0)
        #expect(stats.totalDistance == 0)
        #expect(stats.totalVertical == 0)
        #expect(stats.maxSpeed == 0)
    }

    @Test func seasonStats_singleSession() {
        let session = SkiSession(
            startDate: Date(),
            endDate: Date().addingTimeInterval(3600),
            totalDistance: 5000,
            totalVertical: 1200,
            maxSpeed: 15.0,
            runCount: 8
        )

        let stats = StatsService.seasonStats(from: [session])
        #expect(stats.totalSessions == 1)
        #expect(stats.totalRuns == 8)
        #expect(stats.totalDistance == 5000)
        #expect(stats.totalVertical == 1200)
        #expect(stats.maxSpeed == 15.0)
        #expect(stats.averageRunsPerSession == 8.0)
    }

    @Test func seasonStats_multipleSessions() {
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

        let stats = StatsService.seasonStats(from: [s1, s2])
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
        #expect(records.count == 4)
        #expect(records.contains("Max Speed"))
        #expect(records.contains("Vertical Drop"))
        #expect(records.contains("Distance"))
        #expect(records.contains("Run Count"))
    }

    @Test func checkPersonalBests_noNew() {
        let session = SkiSession(
            totalDistance: 3000,
            totalVertical: 800,
            maxSpeed: 10.0,
            runCount: 5
        )
        let profile = UserProfile(
            seasonBestMaxSpeed: 20.0,
            seasonBestVertical: 2000,
            seasonBestDistance: 10000,
            seasonBestRunCount: 15
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
            seasonBestMaxSpeed: 20.0,
            seasonBestVertical: 2000,
            seasonBestDistance: 10000,
            seasonBestRunCount: 15
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
            runCount: 10           // not a best
        )
        let profile = UserProfile(
            seasonBestMaxSpeed: 20.0,
            seasonBestVertical: 2000,
            seasonBestDistance: 5000,
            seasonBestRunCount: 15
        )

        let update = StatsService.computePersonalBestUpdates(session: session, profile: profile)

        #expect(update.maxSpeed == 30.0)
        #expect(update.vertical == nil)
        #expect(update.distance == 9000)
        #expect(update.runCount == nil)
        #expect(update.hasUpdates == true)
    }

    @Test func applyPersonalBestUpdate_updatesProfile() {
        let profile = UserProfile(
            seasonBestMaxSpeed: 20.0,
            seasonBestVertical: 2000,
            seasonBestDistance: 5000,
            seasonBestRunCount: 15
        )

        let update = StatsService.PersonalBestUpdate(
            maxSpeed: 30.0,
            vertical: nil,
            distance: 9000,
            runCount: nil
        )

        StatsService.applyPersonalBestUpdate(update, to: profile)

        #expect(profile.seasonBestMaxSpeed == 30.0)
        #expect(profile.seasonBestVertical == 2000)
        #expect(profile.seasonBestDistance == 9000)
        #expect(profile.seasonBestRunCount == 15)
    }

    @Test func personalBestUpdate_noUpdates() {
        let update = StatsService.PersonalBestUpdate(
            maxSpeed: nil,
            vertical: nil,
            distance: nil,
            runCount: nil
        )
        #expect(update.hasUpdates == false)
    }
}
