//
//  HealthKitService.swift
//  Snowly
//
//  Manages HealthKit workout recording — builds an HKWorkout
//  with distance samples and GPS route during a ski session.
//

import Foundation
import HealthKit
import CoreLocation
import os
import Observation

enum HealthKitAuthorizationState: Sendable, Equatable {
    case notDetermined
    case denied
    case authorized
    case unavailable
}

@Observable
@MainActor
final class HealthKitService: HealthKitProviding {

    // MARK: - Published state

    private(set) var authorizationState: HealthKitAuthorizationState = .notDetermined
    private(set) var isAuthorized = false
    private(set) var isRecording = false

    /// Last HealthKit error encountered (nil when healthy).
    private(set) var lastError: Error?

    // MARK: - Private state

    private let healthStore: HKHealthStore?
    private static let logger = Logger(subsystem: "com.Snowly", category: "HealthKit")
    private var workoutBuilder: HKWorkoutBuilder?
    private var routeBuilder: HKWorkoutRouteBuilder?
    private var routePointBuffer: [CLLocation] = []

    private static let routeFlushThreshold = 100

    // MARK: - Init

    init() {
        if HKHealthStore.isHealthDataAvailable() {
            self.healthStore = HKHealthStore()
        } else {
            self.healthStore = nil
        }
        refreshAuthorizationStatus()
    }

    // MARK: - Authorization

    func requestAuthorization() async {
        guard let store = healthStore else {
            refreshAuthorizationStatus()
            return
        }

        let shareTypes: Set<HKSampleType> = [
            HKQuantityType.workoutType(),
            HKQuantityType(.distanceDownhillSnowSports),
            HKSeriesType.workoutRoute(),
        ]
        let readTypes: Set<HKObjectType> = [
            HKQuantityType.workoutType(),
        ]

        do {
            try await store.requestAuthorization(toShare: shareTypes, read: readTypes)
        } catch {
            Self.logger.error("HealthKit authorization failed: \(error.localizedDescription, privacy: .public)")
            lastError = error
        }

        refreshAuthorizationStatus()
    }

    func refreshAuthorizationStatus() {
        guard let store = healthStore else {
            authorizationState = .unavailable
            isAuthorized = false
            return
        }

        switch store.authorizationStatus(for: HKQuantityType.workoutType()) {
        case .sharingAuthorized:
            authorizationState = .authorized
            isAuthorized = true
        case .sharingDenied:
            authorizationState = .denied
            isAuthorized = false
        case .notDetermined:
            authorizationState = .notDetermined
            isAuthorized = false
        @unknown default:
            authorizationState = .denied
            isAuthorized = false
        }
    }

    // MARK: - Workout Lifecycle

    func beginWorkout(startDate: Date) async throws {
        guard let store = healthStore else {
            throw HealthKitError.notAvailable
        }

        refreshAuthorizationStatus()
        guard isAuthorized else {
            throw HealthKitError.notAuthorized
        }

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .downhillSkiing
        configuration.locationType = .outdoor

        let builder = HKWorkoutBuilder(
            healthStore: store,
            configuration: configuration,
            device: .local()
        )
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            builder.beginCollection(withStart: startDate) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }

        self.workoutBuilder = builder
        self.routeBuilder = HKWorkoutRouteBuilder(
            healthStore: store,
            device: .local()
        )
        self.routePointBuffer = []
        self.isRecording = true
    }

    func addRoutePoints(_ points: [FilteredTrackPoint]) async {
        guard let routeBuilder else { return }

        let locations = points.map(\.clLocation)
        routePointBuffer.append(contentsOf: locations)

        guard routePointBuffer.count >= Self.routeFlushThreshold else { return }

        let batch = routePointBuffer
        routePointBuffer = []

        do {
            try await routeBuilder.insertRouteData(batch)
        } catch {
            Self.logger.warning("Route data insertion failed: \(error.localizedDescription, privacy: .public)")
            lastError = error
            // Retry once
            do {
                try await routeBuilder.insertRouteData(batch)
            } catch {
                Self.logger.error("Route data retry failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func addDistanceSample(meters: Double, start: Date, end: Date) async {
        guard let builder = workoutBuilder, meters > 0 else { return }

        let quantity = HKQuantity(
            unit: .meter(),
            doubleValue: meters
        )
        let sample = HKQuantitySample(
            type: HKQuantityType(.distanceDownhillSnowSports),
            quantity: quantity,
            start: start,
            end: end
        )

        do {
            try await builder.addSamples([sample])
        } catch {
            Self.logger.warning("Distance sample failed: \(error.localizedDescription, privacy: .public)")
            lastError = error
        }
    }

    func finishWorkout(
        endDate: Date,
        totalVerticalAscent: Double,
        totalVerticalDescent: Double
    ) async throws -> UUID {
        guard let builder = workoutBuilder else {
            throw HealthKitError.builderNotStarted
        }

        // Flush remaining route points
        if let routeBuilder, !routePointBuffer.isEmpty {
            let remaining = routePointBuffer
            routePointBuffer = []
            do {
                try await routeBuilder.insertRouteData(remaining)
            } catch {
                Self.logger.warning("Final route flush failed: \(error.localizedDescription, privacy: .public)")
                lastError = error
            }
        }

        // End collection
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            builder.endCollection(withEnd: endDate) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }

        // Add elevation metadata
        var metadata: [String: Any] = [:]
        if totalVerticalAscent > 0 {
            metadata[HKMetadataKeyElevationAscended] = HKQuantity(
                unit: .meter(),
                doubleValue: totalVerticalAscent
            )
        }
        if totalVerticalDescent > 0 {
            metadata[HKMetadataKeyElevationDescended] = HKQuantity(
                unit: .meter(),
                doubleValue: totalVerticalDescent
            )
        }
        if !metadata.isEmpty {
            try await builder.addMetadata(metadata)
        }

        // Finalize workout
        guard let workout = try await builder.finishWorkout() else {
            throw HealthKitError.workoutFinalizationFailed("finishWorkout returned nil")
        }

        // Attach route (non-fatal if it fails)
        if let routeBuilder {
            do {
                try await routeBuilder.finishRoute(with: workout, metadata: nil)
            } catch {
                Self.logger.error("Route attachment failed: \(error.localizedDescription, privacy: .public)")
                lastError = error
            }
        }

        // Clean up
        self.workoutBuilder = nil
        self.routeBuilder = nil
        self.routePointBuffer = []
        self.isRecording = false

        return workout.uuid
    }

    func cancelWorkout() async {
        guard let builder = workoutBuilder else { return }
        builder.discardWorkout()
        self.workoutBuilder = nil
        self.routeBuilder = nil
        self.routePointBuffer = []
        self.isRecording = false
    }
}
