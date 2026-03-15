//
//  FixtureReplayService.swift
//  Snowly
//
//  Debug-only fixture replay pipeline used by launch argument `-replay_recap`.
//  Replays fixture points through the production detection pipeline (filter + detect + dwell + segment validation).
//

import Foundation
import SwiftData

enum FixtureReplayService {
    private struct FixtureTrackPoint: Codable {
        let timestamp: TimeInterval
        let latitude: Double
        let longitude: Double
        let altitude: Double
        let speed: Double
        let horizontalAccuracy: Double
        let verticalAccuracy: Double
        let course: Double
    }

    private struct ReplayFixtureManifest: Decodable {
        let fixtures: [ReplayFixtureDefinition]
    }

    private struct ReplayFixtureDefinition: Decodable {
        let id: String
        let displayName: String?
        let trackpointsResource: String
        let sessionId: UUID
        let resort: ReplayFixtureResort
    }

    private struct ReplayFixtureResort: Decodable {
        let id: UUID
        let name: String
        let latitude: Double
        let longitude: Double
        let country: String
    }

    private struct ActivityCounters {
        var skiing = 0
        var lift = 0
        var walk = 0
        var idle = 0

        mutating func record(_ activity: DetectedActivity) {
            switch activity {
            case .skiing: skiing += 1
            case .lift: lift += 1
            case .walk: walk += 1
            case .idle: idle += 1
            }
        }

        var debugString: String {
            "skiing=\(skiing), lift=\(lift), walk=\(walk), idle=\(idle)"
        }
    }

    private struct ReplayRunBuildResult {
        let runs: [CompletedRunData]
        let rawActivityCounts: ActivityCounters
        let stableActivityCounts: ActivityCounters
    }

    static func replayFixtureDataIfNeeded(
        in container: ModelContainer,
        launchArguments: [String]
    ) {
#if DEBUG
        guard let fixtureID = launchArgumentValue(for: "-replay_recap", in: launchArguments) else { return }
        let context = container.mainContext

        guard let fixture = loadReplayFixtureDefinition(id: fixtureID) else {
            print("replay_recap skipped: fixture id '\(fixtureID)' not found in ReplayFixtures.manifest.json")
            return
        }
        guard let source = loadReplayFixtureTrackPoints(resource: fixture.trackpointsResource), !source.isEmpty else {
            print("replay_recap skipped: missing or invalid fixture resource '\(fixture.trackpointsResource).json'")
            return
        }

        let profile = ensureReplayProfileAndSettings(in: context)
        let resort = upsertReplayResort(fixture.resort, in: context)
        deleteSessionIfExists(id: fixture.sessionId, in: context)

        // Keep replayed session near "now" so Summary defaults to latest.
        let startDate = Date().addingTimeInterval(-90 * 60)
        let anchoredPoints = anchorFixturePoints(source, startDate: startDate)
        let replayResult = buildCompletedRunsViaReplay(from: anchoredPoints)
        let replayRuns = replayResult.runs
            .filter { $0.activityType == .skiing || $0.activityType == .lift || $0.activityType == .walk }
        guard !replayRuns.isEmpty, let endDate = replayRuns.last?.endDate else {
            print("replay_recap skipped: replay produced no completed runs")
            return
        }

        let skiingRuns = replayRuns.filter { $0.activityType == .skiing }
        let totalDistance = skiingRuns.reduce(0.0) { $0 + $1.distance }
        let totalVertical = skiingRuns.reduce(0.0) { $0 + $1.verticalDrop }
        let maxSpeed = skiingRuns.map(\.maxSpeed).max() ?? 0
        let runCount = skiingRuns.count

        let session = SkiSession(
            id: fixture.sessionId,
            startDate: startDate,
            endDate: endDate,
            totalDistance: totalDistance,
            totalVertical: totalVertical,
            maxSpeed: maxSpeed,
            runCount: runCount,
            resort: resort
        )
        context.insert(session)

        for runData in replayRuns {
            let run = SkiRun(
                startDate: runData.startDate,
                endDate: runData.endDate,
                distance: runData.distance,
                verticalDrop: runData.verticalDrop,
                maxSpeed: runData.maxSpeed,
                averageSpeed: runData.averageSpeed,
                activityType: runData.activityType,
                trackData: runData.trackData
            )
            run.session = session
            context.insert(run)
        }

        let update = StatsService.computePersonalBestUpdates(session: session, profile: profile)
        if update.hasUpdates {
            StatsService.applyPersonalBestUpdate(update, to: profile)
        }

        try? context.save()

        let fixtureLabel = fixture.displayName ?? fixture.id
        print("replay_recap loaded: \(fixtureLabel), runs=\(replayRuns.count), skiingRuns=\(runCount)")
        print("replay_recap rawActivity: \(replayResult.rawActivityCounts.debugString)")
        print("replay_recap stableActivity: \(replayResult.stableActivityCounts.debugString)")
#else
        _ = container
        _ = launchArguments
#endif
    }

#if DEBUG
    static func buildCompletedRunData(
        activityType: RunActivityType,
        points: [FilteredTrackPoint]
    ) -> CompletedRunData? {
        guard let first = points.first, let last = points.last, points.count >= 2 else { return nil }

        let distance = zip(points, points.dropFirst()).reduce(0.0) { acc, pair in
            acc + pair.0.distance(to: pair.1)
        }
        let duration = max(last.timestamp.timeIntervalSince(first.timestamp), 1)
        let avgSpeed = distance / duration
        let maxSpeed = points.map(\.estimatedSpeed).max() ?? 0

        guard let effectiveType = SegmentValidator.effectiveType(
            activityType: activityType,
            firstPoint: first,
            lastPoint: last,
            duration: duration,
            averageSpeed: avgSpeed
        ) else { return nil }

        let verticalDrop = SegmentValidator.verticalDrop(
            effectiveType: effectiveType,
            firstAltitude: first.altitude,
            lastAltitude: last.altitude
        )

        return CompletedRunData(
            startDate: first.timestamp,
            endDate: last.timestamp,
            distance: distance,
            verticalDrop: verticalDrop,
            maxSpeed: maxSpeed,
            averageSpeed: avgSpeed,
            activityType: effectiveType,
            trackData: nil
        )
    }

    // MARK: - Replay loading

    private static func launchArgumentValue(
        for key: String,
        in launchArguments: [String]
    ) -> String? {
        guard let index = launchArguments.firstIndex(of: key),
              launchArguments.indices.contains(index + 1) else { return nil }
        let value = launchArguments[index + 1]
        return value.hasPrefix("-") ? nil : value
    }

    private static func loadReplayFixtureDefinition(id: String) -> ReplayFixtureDefinition? {
        guard let manifest = loadReplayFixtureManifest() else { return nil }
        return manifest.fixtures.first { $0.id == id }
    }

    private static func loadReplayFixtureManifest() -> ReplayFixtureManifest? {
        let url = Bundle.main.url(
            forResource: "ReplayFixtures.manifest",
            withExtension: "json"
        ) ?? Bundle.main.url(
            forResource: "fixtures.manifest",
            withExtension: "json",
            subdirectory: "Debug/Fixtures"
        )
        guard let url,
              let data = try? Data(contentsOf: url) else {
            return nil
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try? decoder.decode(ReplayFixtureManifest.self, from: data)
    }

    private static func loadReplayFixtureTrackPoints(resource: String) -> [FixtureTrackPoint]? {
        let url = Bundle.main.url(
            forResource: resource,
            withExtension: "json",
            subdirectory: "Debug/Fixtures"
        ) ?? Bundle.main.url(
            forResource: resource,
            withExtension: "json"
        )
        guard let url,
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? JSONDecoder().decode([FixtureTrackPoint].self, from: data)
    }

    private static func anchorFixturePoints(
        _ source: [FixtureTrackPoint],
        startDate: Date
    ) -> [TrackPoint] {
        let anchor = source.first?.timestamp ?? 0
        return source.map { point in
            TrackPoint(
                timestamp: startDate.addingTimeInterval(point.timestamp - anchor),
                latitude: point.latitude,
                longitude: point.longitude,
                altitude: point.altitude,
                speed: max(point.speed, 0),
                horizontalAccuracy: point.horizontalAccuracy,
                verticalAccuracy: point.verticalAccuracy,
                course: point.course
            )
        }
    }

    // MARK: - Replay pipeline

    private static func buildCompletedRunsViaReplay(from trackPoints: [TrackPoint]) -> ReplayRunBuildResult {
        let sortedPoints = trackPoints.sorted { $0.timestamp < $1.timestamp }
        guard !sortedPoints.isEmpty else {
            return ReplayRunBuildResult(
                runs: [],
                rawActivityCounts: ActivityCounters(),
                stableActivityCounts: ActivityCounters()
            )
        }

        var gpsFilter = GPSKalmanFilter()
        var recentPoints: [FilteredTrackPoint] = []
        var currentActivity: DetectedActivity = .idle
        var candidateActivity: DetectedActivity?
        var candidateStartTime: Date?

        var currentSegmentType: RunActivityType?
        var currentSegmentFilteredPoints: [FilteredTrackPoint] = []
        var lastActiveTime: Date?
        var rawActivityCounts = ActivityCounters()
        var stableActivityCounts = ActivityCounters()
        var result: [CompletedRunData] = []

        func finalizeSegment() {
            guard let segmentType = currentSegmentType,
                  !currentSegmentFilteredPoints.isEmpty else { return }

            guard let filteredRun = buildCompletedRunData(
                activityType: segmentType,
                points: currentSegmentFilteredPoints
            ) else {
                currentSegmentType = nil
                currentSegmentFilteredPoints = []
                lastActiveTime = nil
                return
            }

            let filteredTrackData = try? JSONEncoder().encode(currentSegmentFilteredPoints)
            result.append(
                CompletedRunData(
                    startDate: filteredRun.startDate,
                    endDate: filteredRun.endDate,
                    distance: filteredRun.distance,
                    verticalDrop: filteredRun.verticalDrop,
                    maxSpeed: filteredRun.maxSpeed,
                    averageSpeed: filteredRun.averageSpeed,
                    activityType: filteredRun.activityType,
                    trackData: filteredTrackData
                )
            )

            currentSegmentType = nil
            currentSegmentFilteredPoints = []
            lastActiveTime = nil
        }

        for rawPoint in sortedPoints {
            let filteredPoint = gpsFilter.update(point: rawPoint)
            let motionHint = replayMotionHint(
                point: filteredPoint,
                recentPoints: recentPoints,
                previousActivity: currentActivity
            )
            let rawActivity = RunDetectionService.detect(
                point: filteredPoint,
                recentPoints: recentPoints,
                previousActivity: currentActivity,
                motion: motionHint
            )
            rawActivityCounts.record(rawActivity)

            recentPoints.append(filteredPoint)
            RecentTrackWindow.trimFilteredPoints(&recentPoints, relativeTo: filteredPoint.timestamp)

            let dwellResult = SessionTrackingService.applyDwellTime(
                rawActivity: rawActivity,
                currentActivity: currentActivity,
                candidateActivity: candidateActivity,
                candidateStartTime: candidateStartTime,
                timestamp: filteredPoint.timestamp
            )
            currentActivity = dwellResult.activity
            stableActivityCounts.record(currentActivity)
            candidateActivity = dwellResult.candidate
            candidateStartTime = dwellResult.candidateStart

            let targetType: RunActivityType?
            switch currentActivity {
            case .skiing: targetType = .skiing
            case .lift: targetType = .lift
            case .walk: targetType = .walk
            case .idle: targetType = nil
            }

            if let targetType {
                if currentSegmentType != targetType {
                    finalizeSegment()
                    currentSegmentType = targetType
                }
                currentSegmentFilteredPoints.append(filteredPoint)
                lastActiveTime = filteredPoint.timestamp
            } else if !currentSegmentFilteredPoints.isEmpty,
                      let lastActive = lastActiveTime,
                      RunDetectionService.shouldEndRun(lastActivityTime: lastActive, now: filteredPoint.timestamp) {
                finalizeSegment()
            }
        }

        finalizeSegment()

        return ReplayRunBuildResult(
            runs: result,
            rawActivityCounts: rawActivityCounts,
            stableActivityCounts: stableActivityCounts
        )
    }

    private static func replayMotionHint(
        point: FilteredTrackPoint,
        recentPoints: [FilteredTrackPoint],
        previousActivity: DetectedActivity
    ) -> MotionHint {
        let estimate = MotionEstimator.estimate(current: point, recentPoints: recentPoints)
        let inLiftSpeedBand = estimate.avgHorizontalSpeed >= SharedConstants.liftSpeedMin
            && estimate.avgHorizontalSpeed <= SharedConstants.liftSpeedMax

        if previousActivity == .lift,
           inLiftSpeedBand,
           estimate.avgVerticalSpeed >= SharedConstants.liftContinuityVerticalSpeedMin {
            return .automotive
        }

        if estimate.hasReliableAltitudeTrend,
           inLiftSpeedBand,
           estimate.avgVerticalSpeed >= SharedConstants.liftVerticalSpeedMin {
            return .automotive
        }

        return .unknown
    }

    // MARK: - Data persistence

    private static func ensureReplayProfileAndSettings(in context: ModelContext) -> UserProfile {
        var profileDescriptor = FetchDescriptor<UserProfile>(sortBy: [SortDescriptor(\.createdAt)])
        profileDescriptor.fetchLimit = 1
        let profile: UserProfile
        if let existing = try? context.fetch(profileDescriptor), let found = existing.first {
            if found.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                found.displayName = "Fixture Replay Rider"
            }
            profile = found
        } else {
            let created = UserProfile(displayName: "Fixture Replay Rider", preferredUnits: .metric)
            context.insert(created)
            profile = created
        }

        var settingsDescriptor = FetchDescriptor<DeviceSettings>(sortBy: [SortDescriptor(\.createdAt)])
        settingsDescriptor.fetchLimit = 1
        if let existing = try? context.fetch(settingsDescriptor), let settings = existing.first {
            settings.hasCompletedOnboarding = true
        } else {
            context.insert(DeviceSettings(hasCompletedOnboarding: true))
        }

        return profile
    }

    private static func upsertReplayResort(
        _ fixtureResort: ReplayFixtureResort,
        in context: ModelContext
    ) -> Resort {
        let descriptor = FetchDescriptor<Resort>()
        if let existing = try? context.fetch(descriptor),
           let found = existing.first(where: { $0.id == fixtureResort.id }) {
            found.name = fixtureResort.name
            found.latitude = fixtureResort.latitude
            found.longitude = fixtureResort.longitude
            found.country = fixtureResort.country
            return found
        }

        let resort = Resort(
            id: fixtureResort.id,
            name: fixtureResort.name,
            latitude: fixtureResort.latitude,
            longitude: fixtureResort.longitude,
            country: fixtureResort.country
        )
        context.insert(resort)
        return resort
    }

    private static func deleteSessionIfExists(id: UUID, in context: ModelContext) {
        let descriptor = FetchDescriptor<SkiSession>()
        guard let existingSessions = try? context.fetch(descriptor)
            .filter({ $0.id == id }),
            !existingSessions.isEmpty else { return }
        for session in existingSessions {
            context.delete(session)
        }
    }
#endif
}
