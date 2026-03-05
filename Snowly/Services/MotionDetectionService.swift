//
//  MotionDetectionService.swift
//  Snowly
//
//  CoreMotion activity recognition to assist run/chairlift detection.
//

import Foundation
import CoreMotion
import Observation

@Observable
@MainActor
final class MotionDetectionService: MotionDetecting {
    private let activityManager = CMMotionActivityManager()

    private(set) var isAvailable = CMMotionActivityManager.isActivityAvailable()
    private(set) var isAuthorized = CMMotionActivityManager.authorizationStatus() == .authorized
    private(set) var currentMotion: DetectedMotion = .unknown

    func requestAuthorization() {
        guard isAvailable else { return }
        // CoreMotion has no explicit requestAuthorization API.
        // Querying a short activity range triggers the system permission dialog.
        let now = Date()
        activityManager.queryActivityStarting(
            from: now.addingTimeInterval(-1),
            to: now,
            to: .main
        ) { [weak self] _, _ in
            Task { @MainActor in
                self?.isAuthorized = CMMotionActivityManager.authorizationStatus() == .authorized
            }
        }
    }

    func startMonitoring() {
        guard isAvailable else { return }
        stopMonitoring()

        activityManager.startActivityUpdates(to: .main) { [weak self] activity in
            guard let activity else { return }

            Task { @MainActor in
                if activity.stationary {
                    self?.currentMotion = .stationary
                } else if activity.walking {
                    self?.currentMotion = .walking
                } else if activity.automotive {
                    self?.currentMotion = .automotive
                } else if activity.cycling {
                    self?.currentMotion = .cycling
                } else if activity.running {
                    self?.currentMotion = .running
                } else {
                    self?.currentMotion = .unknown
                }
            }
        }
    }

    func stopMonitoring() {
        activityManager.stopActivityUpdates()
        currentMotion = .unknown
    }
}
