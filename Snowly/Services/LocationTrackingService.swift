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

@Observable
@MainActor
final class LocationTrackingService: NSObject, LocationProviding, CLLocationManagerDelegate {
    private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
    private(set) var isTracking = false

    private(set) var currentLocation: CLLocationCoordinate2D?
    private(set) var currentAltitude: Double = 0
    private(set) var currentSpeed: Double = 0
    private(set) var currentCourse: Double = 0
    private(set) var currentAccuracy: Double = 0
    private(set) var lastError: Error?

    private let locationManager = CLLocationManager()
    private var trackingContinuation: AsyncStream<TrackPoint>.Continuation?
    private var previousTrackingLocation: CLLocation?
    private var isCollectingLocationUpdates = false
    private var recentTrackPoints: [TrackPoint] = []

    nonisolated private static let logger = Logger(subsystem: "com.Snowly", category: "LocationTracking")

    override init() {
        super.init()
        locationManager.delegate = self
        authorizationStatus = locationManager.authorizationStatus
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

    func recentTrackPointsSnapshot() -> [TrackPoint] {
        recentTrackPoints
    }

    func startTracking() -> AsyncStream<TrackPoint> {
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
            self.currentLocation = location.coordinate
            self.currentAltitude = location.altitude
            let derivedCourse = self.derivedCourse(for: location)
            let normalizedAccuracy = self.normalizedAccuracy(for: location.horizontalAccuracy)
            self.currentSpeed = max(0, location.speed)
            self.currentCourse = derivedCourse
            self.currentAccuracy = normalizedAccuracy
            self.lastError = nil

            let isSimulator: Bool = {
#if targetEnvironment(simulator)
                true
#else
                false
#endif
            }()

            if !isSimulator {
                guard normalizedAccuracy >= 0,
                      normalizedAccuracy <= 50 else {
                    self.previousTrackingLocation = location
                    return
                }
            } else if normalizedAccuracy > 120 {
                self.previousTrackingLocation = location
                return
            }

            let point = TrackPoint(
                timestamp: location.timestamp,
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                altitude: location.altitude,
                speed: max(0, location.speed),
                accuracy: normalizedAccuracy,
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
            self.authorizationStatus = status
            self.lastError = nil

            switch status {
            case .authorizedWhenInUse, .authorizedAlways:
                self.startPassiveCollectionIfAuthorized()
                manager.requestLocation()
                if status == .authorizedWhenInUse {
                    manager.requestAlwaysAuthorization()
                }
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
        locationManager.distanceFilter = 5
        locationManager.activityType = .fitness
        locationManager.pausesLocationUpdatesAutomatically = !forTracking

        let hasBackgroundMode = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String]
        let canUseBackgroundMode = hasBackgroundMode?.contains("location") == true
        locationManager.allowsBackgroundLocationUpdates = forTracking && canUseBackgroundMode
        locationManager.showsBackgroundLocationIndicator = forTracking && canUseBackgroundMode
    }

    private func normalizedAccuracy(for reportedAccuracy: Double) -> Double {
        if reportedAccuracy >= 0 { return reportedAccuracy }
#if targetEnvironment(simulator)
        return 8
#else
        return reportedAccuracy
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
