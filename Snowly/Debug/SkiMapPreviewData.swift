//
//  SkiMapPreviewData.swift
//  Snowly
//
//  Static preview data for ski map overlay testing.
//  Uses a subset of real Whistler Blackcomb data.
//

#if DEBUG
import Foundation

enum SkiMapPreviewData {

    /// Sample Whistler Blackcomb ski area data for previews and debug.
    static let whistler = SkiAreaData(
        trails: [
            SkiTrail(
                id: "1",
                name: "Village Run",
                difficulty: .easy,
                type: .downhill,
                coordinates: [
                    Coordinate(latitude: 50.1141, longitude: -122.9537),
                    Coordinate(latitude: 50.1148, longitude: -122.9541),
                    Coordinate(latitude: 50.1155, longitude: -122.9548),
                    Coordinate(latitude: 50.1162, longitude: -122.9558),
                    Coordinate(latitude: 50.1168, longitude: -122.9565),
                ]
            ),
            SkiTrail(
                id: "2",
                name: "Cruiser - Lower",
                difficulty: .intermediate,
                type: .downhill,
                coordinates: [
                    Coordinate(latitude: 50.1185, longitude: -122.9505),
                    Coordinate(latitude: 50.1178, longitude: -122.9512),
                    Coordinate(latitude: 50.1170, longitude: -122.9520),
                    Coordinate(latitude: 50.1160, longitude: -122.9530),
                ]
            ),
            SkiTrail(
                id: "3",
                name: "Olympic Run",
                difficulty: .novice,
                type: .downhill,
                coordinates: [
                    Coordinate(latitude: 50.1130, longitude: -122.9550),
                    Coordinate(latitude: 50.1125, longitude: -122.9555),
                    Coordinate(latitude: 50.1118, longitude: -122.9560),
                    Coordinate(latitude: 50.1110, longitude: -122.9568),
                ]
            ),
            SkiTrail(
                id: "4",
                name: "Dave Murray Downhill",
                difficulty: .advanced,
                type: .downhill,
                coordinates: [
                    Coordinate(latitude: 50.1200, longitude: -122.9480),
                    Coordinate(latitude: 50.1190, longitude: -122.9495),
                    Coordinate(latitude: 50.1175, longitude: -122.9510),
                    Coordinate(latitude: 50.1160, longitude: -122.9525),
                    Coordinate(latitude: 50.1145, longitude: -122.9540),
                ]
            ),
        ],
        lifts: [
            SkiLift(
                id: "10",
                name: "Whistler Village Gondola",
                liftType: .gondola,
                capacity: 2400,
                coordinates: [
                    Coordinate(latitude: 50.1140, longitude: -122.9570),
                    Coordinate(latitude: 50.1160, longitude: -122.9555),
                    Coordinate(latitude: 50.1185, longitude: -122.9535),
                    Coordinate(latitude: 50.1205, longitude: -122.9510),
                ]
            ),
            SkiLift(
                id: "11",
                name: "Fitzsimmons Express",
                liftType: .chairLift,
                capacity: 1800,
                coordinates: [
                    Coordinate(latitude: 50.1130, longitude: -122.9530),
                    Coordinate(latitude: 50.1145, longitude: -122.9515),
                    Coordinate(latitude: 50.1165, longitude: -122.9495),
                ]
            ),
        ],
        fetchedAt: Date(),
        boundingBox: BoundingBox(south: 50.10, west: -122.97, north: 50.13, east: -122.94),
        name: "Whistler Blackcomb"
    )
}
#endif
