//
//  DwellTimeTests.swift
//  SnowlyTests
//
//  Tests for the dwell time hysteresis filter in SessionTrackingService.
//  Verifies that state transitions require sustained signal before switching.
//

import Testing
import Foundation
@testable import Snowly

@MainActor
struct DwellTimeTests {

    // MARK: - Dwell Time Lookup

    @Test func dwellTimeForTransition_returnsCorrectValues() {
        #expect(SessionTrackingService.dwellTimeForTransition(from: .skiing, to: .chairlift) == 15)
        #expect(SessionTrackingService.dwellTimeForTransition(from: .chairlift, to: .skiing) == 8)
        #expect(SessionTrackingService.dwellTimeForTransition(from: .idle, to: .skiing) == 3)
        #expect(SessionTrackingService.dwellTimeForTransition(from: .idle, to: .chairlift) == 10)
        // Same-state transitions return 0
        #expect(SessionTrackingService.dwellTimeForTransition(from: .skiing, to: .skiing) == 0)
        #expect(SessionTrackingService.dwellTimeForTransition(from: .idle, to: .idle) == 0)
    }

    // MARK: - Dwell Time State Machine

    @Test func briefAnomalyDoesNotTriggerSwitch() {
        // Start skiing, get 5 seconds of chairlift readings (< 15s threshold)
        var activity: DetectedActivity = .skiing
        var candidate: DetectedActivity?
        var candidateStart: Date?
        let baseTime = Date()

        for i in 0..<5 {
            let result = SessionTrackingService.applyDwellTime(
                rawActivity: .chairlift,
                currentActivity: activity,
                candidateActivity: candidate,
                candidateStartTime: candidateStart,
                timestamp: baseTime.addingTimeInterval(Double(i))
            )
            activity = result.activity
            candidate = result.candidate
            candidateStart = result.candidateStart
        }

        #expect(activity == .skiing) // Must NOT switch — anomaly too brief
    }

    @Test func sustainedChangeTriggersSwitch() {
        // Start skiing, get 16 seconds of chairlift readings (> 15s threshold)
        var activity: DetectedActivity = .skiing
        var candidate: DetectedActivity?
        var candidateStart: Date?
        let baseTime = Date()

        for i in 0..<16 {
            let result = SessionTrackingService.applyDwellTime(
                rawActivity: .chairlift,
                currentActivity: activity,
                candidateActivity: candidate,
                candidateStartTime: candidateStart,
                timestamp: baseTime.addingTimeInterval(Double(i))
            )
            activity = result.activity
            candidate = result.candidate
            candidateStart = result.candidateStart
        }

        #expect(activity == .chairlift) // Must switch after 15s sustained signal
    }

    @Test func interruptedCandidateResetsTimer() {
        // Start skiing, get 10s of chairlift, then 1 skiing, then 10s of chairlift
        var activity: DetectedActivity = .skiing
        var candidate: DetectedActivity?
        var candidateStart: Date?
        let baseTime = Date()

        // 10 seconds of chairlift
        for i in 0..<10 {
            let result = SessionTrackingService.applyDwellTime(
                rawActivity: .chairlift,
                currentActivity: activity,
                candidateActivity: candidate,
                candidateStartTime: candidateStart,
                timestamp: baseTime.addingTimeInterval(Double(i))
            )
            activity = result.activity
            candidate = result.candidate
            candidateStart = result.candidateStart
        }

        #expect(activity == .skiing) // Not yet (10 < 15)

        // 1 skiing reading — resets the candidate because raw matches current
        let resetResult = SessionTrackingService.applyDwellTime(
            rawActivity: .skiing,
            currentActivity: activity,
            candidateActivity: candidate,
            candidateStartTime: candidateStart,
            timestamp: baseTime.addingTimeInterval(10)
        )
        activity = resetResult.activity
        candidate = resetResult.candidate
        candidateStart = resetResult.candidateStart

        #expect(candidate == nil) // Candidate reset

        // 10 more seconds of chairlift — timer restarts from scratch
        for i in 11..<21 {
            let result = SessionTrackingService.applyDwellTime(
                rawActivity: .chairlift,
                currentActivity: activity,
                candidateActivity: candidate,
                candidateStartTime: candidateStart,
                timestamp: baseTime.addingTimeInterval(Double(i))
            )
            activity = result.activity
            candidate = result.candidate
            candidateStart = result.candidateStart
        }

        // 10 seconds from scratch (11..20) < 15s, so still skiing
        #expect(activity == .skiing)
    }

    @Test func idleToSkiing_fasterTransition() {
        // idle → skiing only needs 3 seconds
        var activity: DetectedActivity = .idle
        var candidate: DetectedActivity?
        var candidateStart: Date?
        let baseTime = Date()

        for i in 0..<4 {
            let result = SessionTrackingService.applyDwellTime(
                rawActivity: .skiing,
                currentActivity: activity,
                candidateActivity: candidate,
                candidateStartTime: candidateStart,
                timestamp: baseTime.addingTimeInterval(Double(i))
            )
            activity = result.activity
            candidate = result.candidate
            candidateStart = result.candidateStart
        }

        #expect(activity == .skiing) // Switches after 3s
    }
}
