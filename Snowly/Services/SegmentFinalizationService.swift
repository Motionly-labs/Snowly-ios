//
//  SegmentFinalizationService.swift
//  Snowly
//
//  Owns segment state tracking and run finalization.
//  Extracted from SessionTrackingService to reduce complexity.
//

import Foundation
import Observation

/// Immutable snapshot of a completed run or lift segment.
struct CompletedRunData: Sendable, Equatable {
    let startDate: Date
    let endDate: Date
    let distance: Double
    let verticalDrop: Double
    let maxSpeed: Double
    let averageSpeed: Double
    let activityType: RunActivityType
    let trackData: Data?
}

@Observable
@MainActor
final class SegmentFinalizationService {

    private(set) var completedRuns: [CompletedRunData] = []
    private(set) var runCount: Int = 0

    private var currentSegmentPoints: [TrackPoint] = []
    private var currentSegmentType: RunActivityType?
    private var lastActiveTime: Date?

    /// Process a track point with its detected activity to update segment state.
    func processPoint(_ point: TrackPoint, activity: DetectedActivity) {
        let targetType: RunActivityType?
        switch activity {
        case .skiing: targetType = .skiing
        case .lift:   targetType = .lift
        case .walk:   targetType = .walk
        case .idle:   targetType = nil
        }

        if let targetType {
            if currentSegmentType != targetType {
                finalizeCurrentSegment()
                currentSegmentType = targetType
                currentSegmentPoints = [point]
            } else {
                currentSegmentPoints.append(point)
            }
            lastActiveTime = point.timestamp
            return
        }

        if !currentSegmentPoints.isEmpty,
           let lastActive = lastActiveTime,
           RunDetectionService.shouldEndRun(lastActivityTime: lastActive, now: point.timestamp) {
            finalizeCurrentSegment()
        }
    }

    /// Finalize the current in-progress segment into a CompletedRunData.
    func finalizeCurrentSegment() {
        guard let segmentType = currentSegmentType,
              !currentSegmentPoints.isEmpty,
              let first = currentSegmentPoints.first,
              let last = currentSegmentPoints.last else { return }

        let runDistance = zip(currentSegmentPoints, currentSegmentPoints.dropFirst())
            .reduce(0.0) { $0 + $1.0.distance(to: $1.1) }

        let duration = last.timestamp.timeIntervalSince(first.timestamp)
        let avgSpeed = duration > 0 ? runDistance / duration : 0
        let runMaxSpeed = derivedMaxSpeed(from: currentSegmentPoints)

        let runVertical = SegmentValidator.verticalDrop(
            effectiveType: segmentType,
            firstAltitude: first.altitude,
            lastAltitude: last.altitude
        )

        // Capture points for background encoding
        let points = currentSegmentPoints

        let run = CompletedRunData(
            startDate: first.timestamp,
            endDate: last.timestamp,
            distance: runDistance,
            verticalDrop: runVertical,
            maxSpeed: runMaxSpeed,
            averageSpeed: avgSpeed,
            activityType: segmentType,
            trackData: nil
        )

        completedRuns.append(run)
        let runIndex = completedRuns.count - 1

        if segmentType == .skiing {
            runCount += 1
        }

        resetCurrentSegment()

        // Encode track data off MainActor, then patch the completed run
        Task.detached { [weak self] in
            let trackData = try? JSONEncoder().encode(points)
            await self?.patchTrackData(trackData, at: runIndex)
        }
    }

    /// Patches encoded track data back into a completed run after background encoding.
    private func patchTrackData(_ data: Data?, at index: Int) {
        guard index < completedRuns.count, let data else { return }
        let existing = completedRuns[index]
        completedRuns[index] = CompletedRunData(
            startDate: existing.startDate,
            endDate: existing.endDate,
            distance: existing.distance,
            verticalDrop: existing.verticalDrop,
            maxSpeed: existing.maxSpeed,
            averageSpeed: existing.averageSpeed,
            activityType: existing.activityType,
            trackData: data
        )
    }

    /// Reset all state for a new session.
    func reset() {
        resetCurrentSegment()
        completedRuns = []
        runCount = 0
    }

    // MARK: - Private

    private func resetCurrentSegment() {
        currentSegmentPoints = []
        currentSegmentType = nil
        lastActiveTime = nil
    }

    private func derivedMaxSpeed(from points: [TrackPoint]) -> Double {
        guard points.count > 1 else { return 0 }
        var maxSpeed = 0.0
        for (a, b) in zip(points, points.dropFirst()) {
            let dt = b.timestamp.timeIntervalSince(a.timestamp)
            guard dt >= 0.5 else { continue }  // GPS clock batching guard
            let s = min(a.distance(to: b) / dt, 70.0)  // physical speed cap
            maxSpeed = max(maxSpeed, s)
        }
        return maxSpeed
    }

    /// Restores finalized runs from persisted crash-recovery state.
    func restoreCompletedRuns(_ runs: [CompletedRunData], runCount: Int) {
        completedRuns = runs
        let skiingRuns = runs.filter { $0.activityType == .skiing }.count
        self.runCount = max(runCount, skiingRuns)
        resetCurrentSegment()
    }

}
