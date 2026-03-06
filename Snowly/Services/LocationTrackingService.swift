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
            self.currentSpeed = max(0, location.speed)
            self.currentCourse = location.course
            self.currentAccuracy = location.horizontalAccuracy
            self.lastError = nil

            guard self.isTracking else { return }
            guard location.horizontalAccuracy >= 0,
                  location.horizontalAccuracy <= 50 else { return }

            let point = TrackPoint(
                timestamp: location.timestamp,
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                altitude: location.altitude,
                speed: max(0, location.speed),
                accuracy: location.horizontalAccuracy,
                course: location.course
            )

            self.adjustAccuracy(forSpeed: point.speed)
            self.trackingContinuation?.yield(point)
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
    private func adjustAccuracy(forSpeed speed: Double) {
        if speed > SharedConstants.highSpeedThreshold {
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
}
