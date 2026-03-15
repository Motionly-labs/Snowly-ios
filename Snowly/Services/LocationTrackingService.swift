//
//  LocationTrackingService.swift
//  Snowly
//
//  CLLocationManager wrapper that always keeps a recent in-memory GPS window
//  while only streaming points to the tracking pipeline during active sessions.
//

import Foundation
import CoreLocation
import os
import Observation
import UIKit

@Observable
@MainActor
final class LocationTrackingService: NSObject, LocationProviding, CLLocationManagerDelegate {
    private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
    private(set) var isTracking = false

    private(set) var currentLocation: CLLocationCoordinate2D?
    private(set) var currentAltitude: Double = 0
    private(set) var currentSpeed: Double = 0
    private(set) var currentCourse: Double = 0
    private(set) var currentHorizontalAccuracy: Double = 0
    private(set) var currentVerticalAccuracy: Double = 0
    private(set) var lastError: Error?

    var isGPSReadyForTracking: Bool {
        let isAuthorized = authorizationStatus == .authorizedWhenInUse
            || authorizationStatus == .authorizedAlways
#if DEBUG
        if gpxReplayName != nil { return isAuthorized }
#endif
        return isAuthorized && currentLocation != nil
    }

    private let locationManager = CLLocationManager()
    private var trackingContinuation: AsyncStream<TrackPoint>.Continuation?
    private var previousTrackingLocation: CLLocation?
    private var isCollectingLocationUpdates = false
    private var recentTrackPoints: [TrackPoint] = []

#if DEBUG
    // Set by -replay_gpx <name>. Drives startTracking() with a GPX stream instead of
    // CLLocationManager, while still running CLLocationManager passively for MapKit.
    private var gpxReplayName: String?
    private var gpxSpeedMultiplier: Double = 1.0
#endif

    nonisolated private static let logger = Logger(subsystem: "com.Snowly", category: "LocationTracking")

    override init() {
        super.init()
        locationManager.delegate = self
        refreshAuthorizationStatus()
#if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let idx = args.firstIndex(of: "-replay_gpx"), idx + 1 < args.count {
            gpxReplayName = args[idx + 1]
            if let sIdx = args.firstIndex(of: "-replay_speed"), sIdx + 1 < args.count {
                gpxSpeedMultiplier = Double(args[sIdx + 1]) ?? 1.0
            }
            // Bypass the permission prompt so the home screen is immediately usable.
            authorizationStatus = .authorizedAlways
        }
#endif
        startPassiveCollectionIfAuthorized()
    }

    func requestAuthorization() {
        switch authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse:
            locationManager.requestAlwaysAuthorization()
        default:
            break
        }
    }

    func refreshAuthorizationStatus() {
        authorizationStatus = locationManager.authorizationStatus
    }

    func recentTrackPointsSnapshot() -> [TrackPoint] {
        recentTrackPoints
    }

    func startTracking() -> AsyncStream<TrackPoint> {
#if DEBUG
        if let name = gpxReplayName,
           let stream = startGPXReplay(name: name) {
            return stream
        }
#endif
        isTracking = true
        configureLocationManager(forTracking: true)
        startLocationUpdatesIfNeeded()

        return AsyncStream { continuation in
            self.trackingContinuation?.finish()
            self.trackingContinuation = continuation

            continuation.onTermination = { @Sendable [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.trackingContinuation = nil
                    self.isTracking = false
                    self.configureLocationManager(forTracking: false)
                    self.startPassiveCollectionIfAuthorized()
                }
            }
        }
    }

    func stopTracking() {
        trackingContinuation?.finish()
        trackingContinuation = nil
        isTracking = false
        configureLocationManager(forTracking: false)
        startPassiveCollectionIfAuthorized()
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
#if DEBUG
            // In GPX replay mode, runGPXLoop owns currentLocation/altitude/speed/course.
            // Skip CLLocationManager updates entirely — on a real device the CLLocationManager
            // reports the actual physical location, which would overwrite the replayed Zermatt
            // coordinates and break resort detection at session end.
            if self.gpxReplayName != nil { return }
#endif
            self.currentLocation = location.coordinate
            self.currentAltitude = location.altitude
            let derivedCourse = self.derivedCourse(for: location)
            let normalizedHorizontalAccuracy = self.normalizedHorizontalAccuracy(for: location.horizontalAccuracy)
            let normalizedVerticalAccuracy = self.normalizedVerticalAccuracy(for: location.verticalAccuracy)
            self.currentSpeed = max(0, location.speed)
            self.currentCourse = derivedCourse
            self.currentHorizontalAccuracy = normalizedHorizontalAccuracy
            self.currentVerticalAccuracy = normalizedVerticalAccuracy
            self.lastError = nil

            let isSimulator: Bool = {
#if targetEnvironment(simulator)
                true
#else
                false
#endif
            }()

            if !isSimulator {
                guard normalizedHorizontalAccuracy >= 0,
                      normalizedHorizontalAccuracy <= 50 else {
                    self.previousTrackingLocation = location
                    return
                }
            } else if normalizedHorizontalAccuracy > 120 {
                self.previousTrackingLocation = location
                return
            }

            let point = TrackPoint(
                timestamp: location.timestamp,
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                altitude: location.altitude,
                speed: max(0, location.speed),
                horizontalAccuracy: normalizedHorizontalAccuracy,
                verticalAccuracy: normalizedVerticalAccuracy,
                course: derivedCourse
            )

            self.recentTrackPoints.append(point)
            RecentTrackWindow.trimTrackPoints(
                &self.recentTrackPoints,
                relativeTo: point.timestamp
            )

            if self.isTracking {
                self.trackingContinuation?.yield(point)
            }

            self.previousTrackingLocation = location
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
#if DEBUG
            // Keep the synthetic .authorizedAlways we set in init() for replay mode.
            guard self.gpxReplayName == nil else { return }
#endif
            self.authorizationStatus = status
            self.lastError = nil

            switch status {
            case .authorizedWhenInUse, .authorizedAlways:
                self.startPassiveCollectionIfAuthorized()
                manager.requestLocation()
            case .denied, .restricted:
                self.stopAllLocationUpdates()
                self.recentTrackPoints.removeAll(keepingCapacity: false)
            case .notDetermined:
                break
            @unknown default:
                break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let nsError = error as NSError
        if nsError.domain == kCLErrorDomain, nsError.code == CLError.locationUnknown.rawValue {
            return
        }

        Self.logger.error("Location error: \(error.localizedDescription, privacy: .public)")
        Task { @MainActor in
            self.lastError = error
        }
    }

    private func startPassiveCollectionIfAuthorized() {
        guard authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways else { return }
        configureLocationManager(forTracking: isTracking)
        startLocationUpdatesIfNeeded()
    }

    private func startLocationUpdatesIfNeeded() {
        guard authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways else { return }
        if !isCollectingLocationUpdates {
            locationManager.startUpdatingLocation()
            isCollectingLocationUpdates = true
        }
    }

    private func stopAllLocationUpdates() {
        locationManager.stopUpdatingLocation()
        isCollectingLocationUpdates = false
        locationManager.allowsBackgroundLocationUpdates = false
        locationManager.showsBackgroundLocationIndicator = false
    }

    private func configureLocationManager(forTracking: Bool) {
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = batteryAwareDistanceFilter
        locationManager.activityType = .fitness
        locationManager.pausesLocationUpdatesAutomatically = !forTracking

        let hasBackgroundMode = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String]
        let canUseBackgroundMode = hasBackgroundMode?.contains("location") == true
        locationManager.allowsBackgroundLocationUpdates = forTracking && canUseBackgroundMode
        locationManager.showsBackgroundLocationIndicator = forTracking && canUseBackgroundMode
    }

    private var batteryAwareDistanceFilter: CLLocationDistance {
        UIDevice.current.isBatteryMonitoringEnabled = true
        let level = UIDevice.current.batteryLevel
        guard level >= 0 else { return 5 }
        return level <= SharedConstants.lowBatteryThreshold ? 20 : 5
    }

    private func normalizedHorizontalAccuracy(for reportedAccuracy: Double) -> Double {
        if reportedAccuracy >= 0 { return reportedAccuracy }
#if targetEnvironment(simulator)
        return 8
#else
        return reportedAccuracy
#endif
    }

    private func normalizedVerticalAccuracy(for reportedAccuracy: Double) -> Double {
        if reportedAccuracy >= 0 { return reportedAccuracy }
#if targetEnvironment(simulator)
        return 12
#else
        return 100
#endif
    }

    private func derivedCourse(for location: CLLocation) -> Double {
        if location.course >= 0 { return location.course }
        guard let previous = previousTrackingLocation else { return 0 }
        let lat1 = previous.coordinate.latitude * .pi / 180
        let lat2 = location.coordinate.latitude * .pi / 180
        let dLon = (location.coordinate.longitude - previous.coordinate.longitude) * .pi / 180
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let angle = atan2(y, x) * 180 / .pi
        let normalized = angle.truncatingRemainder(dividingBy: 360)
        return normalized >= 0 ? normalized : normalized + 360
    }
}

#if DEBUG
extension LocationTrackingService {
    func startGPXReplay(name: String) -> AsyncStream<TrackPoint>? {
        guard let points = GPXParser.parse(named: name), !points.isEmpty else { return nil }
        isTracking = true

        let primeCount = min(45, points.count)
        recentTrackPoints = Array(points.prefix(primeCount))

        if let first = points.first {
            currentLocation = CLLocationCoordinate2D(latitude: first.latitude, longitude: first.longitude)
            currentAltitude = first.altitude
        }

        return AsyncStream { continuation in
            self.trackingContinuation?.finish()
            self.trackingContinuation = continuation

            let task = Task { @MainActor [weak self] in
                guard let self else { return }
                await self.runGPXLoop(points: points, continuation: continuation)
            }
            continuation.onTermination = { @Sendable [weak self] _ in
                task.cancel()
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.trackingContinuation = nil
                    self.isTracking = false
                }
            }
        }
    }

    private func runGPXLoop(
        points: [TrackPoint],
        continuation: AsyncStream<TrackPoint>.Continuation
    ) async {
        let anchorOffset = Date().timeIntervalSince(points[0].timestamp)
        let anchored = points.map {
            TrackPoint(
                timestamp: $0.timestamp.addingTimeInterval(anchorOffset),
                latitude: $0.latitude,
                longitude: $0.longitude,
                altitude: $0.altitude,
                speed: $0.speed,
                horizontalAccuracy: $0.horizontalAccuracy,
                verticalAccuracy: $0.verticalAccuracy,
                course: $0.course
            )
        }

        for i in anchored.indices {
            guard !Task.isCancelled else { break }

            let point = anchored[i]
            let delay: TimeInterval = i > 0
                ? max(0.05, point.timestamp.timeIntervalSince(anchored[i - 1].timestamp) / gpxSpeedMultiplier)
                : 0

            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }

            guard !Task.isCancelled else { break }

            currentLocation = CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude)
            currentAltitude = point.altitude
            currentSpeed = point.speed
            currentCourse = point.course
            currentHorizontalAccuracy = point.horizontalAccuracy
            currentVerticalAccuracy = point.verticalAccuracy

            recentTrackPoints.append(point)
            RecentTrackWindow.trimTrackPoints(&recentTrackPoints, relativeTo: point.timestamp)

            if isTracking {
                continuation.yield(point)
            }
        }
        continuation.finish()
    }
}
#endif
