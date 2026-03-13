//
//  MotionDetecting.swift
//  Snowly
//
//  Protocol for motion detection — enables mock injection for testing.
//

import Foundation

/// Detected motion activity type from CoreMotion.
enum DetectedMotion: Sendable {
    case stationary
    case walking
    case automotive
    case cycling
    case running
    case unknown
}

@MainActor
protocol MotionDetecting: AnyObject, Sendable {
    var isAvailable: Bool { get }
    var isAuthorized: Bool { get }
    var currentMotion: DetectedMotion { get }

    func requestAuthorization()
    func startMonitoring()
    func stopMonitoring()
}
