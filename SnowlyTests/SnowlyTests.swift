//
//  SnowlyTests.swift
//  SnowlyTests
//
//  Main test entry — individual test files are in separate files.
//

import Testing
import Foundation
import UIKit
import XCTest
@testable import Snowly

struct SnowlyTests {
    @Test func appBuilds() async throws {
        // Smoke test: the app module compiles and can be imported
        #expect(true)
    }
}

final class ShareCardGeneratorTest: XCTestCase {
    @MainActor
    func testGenerateShareCardLocally() async throws {
        // 1. Create a mock SkiSession
        let session = SkiSession()
        session.startDate = Date().addingTimeInterval(-3600 * 4.2)
        session.endDate = session.startDate.addingTimeInterval(15120) // 4:12 h:m
        session.maxSpeed = 23.38 // m/s = ~84.2 km/h
        session.totalDistance = 42500 // 42.5 km
        session.totalVertical = 3240 // 3240 m
        session.runCount = 14
        session.noteTitle = "Powder Day"
        
        // 2. Add realistic track geometry so the MKMapSnapshotter draws a route
        let startLat = 46.0217
        let startLon = 7.7823
        var filteredPoints: [FilteredTrackPoint] = []
        for i in 0..<100 {
            let progress = Double(i) / 100.0
            let lat = startLat - progress * 0.05 + sin(progress * .pi * 4) * 0.005
            let lon = startLon - progress * 0.03 + cos(progress * .pi * 3) * 0.005
            
            let tp = FilteredTrackPoint(
                rawTimestamp: session.startDate.addingTimeInterval(Double(i) * 10),
                timestamp: session.startDate.addingTimeInterval(Double(i) * 10),
                latitude: lat,
                longitude: lon,
                altitude: 2000 - progress * 500,
                estimatedSpeed: 15.0,
                horizontalAccuracy: 5.0,
                verticalAccuracy: 5.0,
                course: 180.0
            )
            filteredPoints.append(tp)
        }
        
        // Add a primary SkiRun to the session with trackData
        let run = SkiRun(
            startDate: session.startDate,
            endDate: session.endDate,
            distance: 12500,
            verticalDrop: 500,
            maxSpeed: 23.38,
            averageSpeed: 15.0,
            activityType: .skiing,
            trackData: try? JSONEncoder().encode(filteredPoints)
        )
        session.runs = [run]
        
        // 3. Render the image
        let image = await ShareCardRenderer.render(
            session: session,
            resortName: "Matterhorn, Zermatt",
            unitSystem: .metric,
            avatarData: nil,
            displayName: "Alex Rider"
        )
        
        // 4. Save to /tmp
        guard let data = image?.pngData() else {
            XCTFail("Failed to render image")
            return
        }
        
        let path = "/tmp/Snowly/snowly_share_card.png"
        let url = URL(fileURLWithPath: path)
        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try data.write(to: url)
        print("✅ Successfully generated share card at \(url.path)")
    }
}
