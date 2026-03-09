//
//  LocationTrackingService.swift
//  Snowly
//
//  Wraps CLLocationUpdate.liveUpdates (iOS 17+) AsyncSequence.
//  Dynamically adjusts GPS accuracy based on speed.
//  Also exposes current location for the map background.
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

    /// Current user location for map display (updated via delegate).
    private(set) var currentLocation: CLLocationCoordinate2D?

    /// Extended location data for crew sharing (updated alongside currentLocation).
    private(set) var currentAltitude: Double = 0
    private(set) var currentSpeed: Double = 0
    private(set) var currentCourse: Double = 0
    private(set) var currentAccuracy: Double = 0

    /// Last GPS error encountered (nil when healthy).
    private(set) var lastError: Error?

    private let locationManager = CLLocationManager()
    private var trackingContinuation: AsyncStream<TrackPoint>.Continuation?
    private var previousTrackingLocation: CLLocation?
    nonisolated private static let logger = Logger(subsystem: "com.Snowly", category: "LocationTracking")

    override init() {
        super.init()
        locationManager.delegate = self
        authorizationStatus = locationManager.authorizationStatus

        // Request a single location for the map background
        if authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways {
            locationManager.requestLocation()
        }
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

    func startTracking() -> AsyncStream<TrackPoint> {
        isTracking = true
        previousTrackingLocation = nil

        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 5
        locationManager.activityType = .fitness

        // Only enable background updates if the capability is configured.
        // Setting this without UIBackgroundModes "location" in Info.plist causes a crash.
        let hasBackgroundMode = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String]
        if hasBackgroundMode?.contains("location") == true {
            locationManager.allowsBackgroundLocationUpdates = true
            locationManager.showsBackgroundLocationIndicator = true
        }

        locationManager.pausesLocationUpdatesAutomatically = false
        locationManager.startUpdatingLocation()

        return AsyncStream { continuation in
            self.trackingContinuation = continuation

            continuation.onTermination = { @Sendable [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.isTracking = false
                }
            }
        }
    }

    func stopTracking() {
        locationManager.stopUpdatingLocation()
        trackingContinuation?.finish()
        trackingContinuation = nil
        previousTrackingLocation = nil
        isTracking = false
        locationManager.allowsBackgroundLocationUpdates = false
        locationManager.showsBackgroundLocationIndicator = false
    }

    // MARK: - CLLocationManagerDelegate

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            self.currentLocation = location.coordinate
            self.currentAltitude = location.altitude
            let derivedSpeed = self.derivedSpeed(for: location)
            let derivedCourse = self.derivedCourse(for: location)
            let normalizedAccuracy = self.normalizedAccuracy(for: location.horizontalAccuracy)
            self.currentSpeed = derivedSpeed
            self.currentCourse = derivedCourse
            self.currentAccuracy = normalizedAccuracy
            self.lastError = nil

            guard self.isTracking else { return }
            let isSimulator: Bool = {
#if targetEnvironment(simulator)
                true
#else
                false
#endif
            }()

            if !isSimulator {
                guard normalizedAccuracy >= 0,
                      normalizedAccuracy <= 50 else { return }
            } else if normalizedAccuracy > 120 {
                // Simulator can report unstable values; avoid clearly invalid jumps.
                return
            }

            let point = TrackPoint(
                timestamp: location.timestamp,
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                altitude: location.altitude,
                speed: derivedSpeed,
                accuracy: normalizedAccuracy,
                course: derivedCourse
            )

            self.adjustAccuracy(forSpeed: point.speed)
            self.trackingContinuation?.yield(point)
            self.previousTrackingLocation = location
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorizationStatus = status
            // Get initial location when authorized
            if status == .authorizedWhenInUse || status == .authorizedAlways {
                manager.requestLocation()
            }
            // Escalate to Always once when-in-use permission is granted.
            if status == .authorizedWhenInUse {
                manager.requestAlwaysAuthorization()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let nsError = error as NSError
        // Ignore temporary errors that resolve on their own
        if nsError.domain == kCLErrorDomain, nsError.code == CLError.locationUnknown.rawValue {
            return
        }

        Self.logger.error("Location error: \(error.localizedDescription, privacy: .public)")
        Task { @MainActor in
            self.lastError = error
        }
    }

    // MARK: - Private

    /// Dynamically adjust GPS precision to save battery.
    private static let veryHighSpeedThreshold: Double = 15.0 // m/s (~54 km/h)

    private func adjustAccuracy(forSpeed speed: Double) {
        if speed > Self.veryHighSpeedThreshold {
            // Very high speed: widen filter to cap update rate at ~2/s
            locationManager.desiredAccuracy = kCLLocationAccuracyBest
            locationManager.distanceFilter = 10
        } else if speed > SharedConstants.highSpeedThreshold {
            locationManager.desiredAccuracy = kCLLocationAccuracyBest
            locationManager.distanceFilter = 5
        } else if speed > SharedConstants.mediumSpeedThreshold {
            locationManager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
            locationManager.distanceFilter = 10
        } else {
            locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
            locationManager.distanceFilter = 20
        }
    }

    private func normalizedAccuracy(for reportedAccuracy: Double) -> Double {
        if reportedAccuracy >= 0 { return reportedAccuracy }
#if targetEnvironment(simulator)
        // GPX playback commonly reports -1 (unknown); use a realistic default.
        return 8
#else
        return reportedAccuracy
#endif
    }

    private func derivedSpeed(for location: CLLocation) -> Double {
        // GPX playback (and some simulated feeds) can report 0 as "unknown speed".
        // Fall back to coordinate delta when reported speed is effectively zero.
        if location.speed > 0.1 {
            return max(0, location.speed)
        }
        guard let previous = previousTrackingLocation else { return 0 }
        let delta = location.timestamp.timeIntervalSince(previous.timestamp)
        guard delta > 0.25 else { return 0 }
        return max(0, location.distance(from: previous) / delta)
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
