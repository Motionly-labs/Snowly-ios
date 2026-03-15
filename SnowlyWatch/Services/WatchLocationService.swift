//
//  WatchLocationService.swift
//  SnowlyWatch
//
//  Lightweight CLLocationManager wrapper for independent watch tracking.
//

import CoreLocation
import Foundation

@Observable
@MainActor
final class WatchLocationService: NSObject {

    var isAuthorized = false

    private var locationManager: CLLocationManager?
    private var onPoint: ((TrackPoint) -> Void)?

    private static let accuracyThreshold: Double = 50.0

    // MARK: - Public

    func requestAuthorization() {
        let manager = makeManagerIfNeeded()
        manager.requestWhenInUseAuthorization()
    }

    func startTracking(onPoint: @escaping (TrackPoint) -> Void) {
        self.onPoint = onPoint
        let manager = makeManagerIfNeeded()
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.activityType = .otherNavigation
        manager.pausesLocationUpdatesAutomatically = false
        // watchOS independent workouts should not force stay-up location mode.
        manager.allowsBackgroundLocationUpdates = false
        manager.startUpdatingLocation()
    }

    func stopTracking() {
        locationManager?.stopUpdatingLocation()
        onPoint = nil
    }

    // MARK: - Private

    private func makeManagerIfNeeded() -> CLLocationManager {
        if let existing = locationManager { return existing }
        let manager = CLLocationManager()
        manager.delegate = self
        locationManager = manager
        return manager
    }

    private func processLocation(_ location: CLLocation) {
        guard location.horizontalAccuracy >= 0,
              location.horizontalAccuracy <= Self.accuracyThreshold else {
            return
        }

        let point = TrackPoint(
            timestamp: location.timestamp,
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            altitude: location.altitude,
            speed: max(0, location.speed),
            horizontalAccuracy: location.horizontalAccuracy,
            verticalAccuracy: location.verticalAccuracy >= 0 ? location.verticalAccuracy : 100,
            course: location.course
        )
        onPoint?(point)
    }
}

// MARK: - CLLocationManagerDelegate

extension WatchLocationService: CLLocationManagerDelegate {

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        Task { @MainActor in
            for location in locations {
                processLocation(location)
            }
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            isAuthorized = status == .authorizedWhenInUse || status == .authorizedAlways
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: Error
    ) {
        print("WatchLocationService error: \(error.localizedDescription)")
    }
}
