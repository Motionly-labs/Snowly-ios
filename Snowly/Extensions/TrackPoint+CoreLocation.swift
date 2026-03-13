//
//  TrackPoint+CoreLocation.swift
//  Snowly
//
//  Converts track points to CLLocation for HealthKit route building.
//

import CoreLocation

extension TrackPoint {
    var clLocation: CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(
                latitude: latitude,
                longitude: longitude
            ),
            altitude: altitude,
            horizontalAccuracy: horizontalAccuracy,
            verticalAccuracy: verticalAccuracy,
            course: course >= 0 ? course : -1,
            speed: max(speed, 0),
            timestamp: timestamp
        )
    }
}

extension FilteredTrackPoint {
    var clLocation: CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(
                latitude: latitude,
                longitude: longitude
            ),
            altitude: altitude,
            horizontalAccuracy: horizontalAccuracy,
            verticalAccuracy: verticalAccuracy,
            course: course >= 0 ? course : -1,
            speed: max(estimatedSpeed, 0),
            timestamp: timestamp
        )
    }
}
