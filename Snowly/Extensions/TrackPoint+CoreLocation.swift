//
//  TrackPoint+CoreLocation.swift
//  Snowly
//
//  Converts TrackPoint to CLLocation for HealthKit route building.
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
            horizontalAccuracy: accuracy,
            verticalAccuracy: 10.0,
            course: course >= 0 ? course : -1,
            speed: max(speed, 0),
            timestamp: timestamp
        )
    }
}
