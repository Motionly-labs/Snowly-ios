//
//  LocationTrackingServiceTests.swift
//  SnowlyTests
//

import Testing
import Foundation
import CoreLocation
@testable import Snowly

@MainActor
struct LocationTrackingServiceTests {

    @Test func initialState() {
        let service = LocationTrackingService()
        #expect(service.isTracking == false)
        #expect(service.currentLocation == nil)
        #expect(service.lastError == nil)
    }

    @Test func authorizationStatus_initialValue() {
        let service = LocationTrackingService()
        // Authorization status depends on host permission, but should be a valid value
        let validStatuses: [CLAuthorizationStatus] = [
            .notDetermined, .restricted, .denied, .authorizedWhenInUse, .authorizedAlways
        ]
        #expect(validStatuses.contains(service.authorizationStatus))
    }

    @Test func stopTracking_whenNotTracking() {
        let service = LocationTrackingService()
        // Should not crash when called on a service that hasn't started
        service.stopTracking()
        #expect(service.isTracking == false)
    }
}
