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
        #expect(SessionTrackingService.dwellTimeForTransition(from: .skiing, to: .lift) == 25)
        #expect(SessionTrackingService.dwellTimeForTransition(from: .lift, to: .skiing) == 5)
        #expect(SessionTrackingService.dwellTimeForTransition(from: .idle, to: .skiing) == 3)
        #expect(SessionTrackingService.dwellTimeForTransition(from: .idle, to: .lift) == 10)
        // Same-state transitions return 0
        #expect(SessionTrackingService.dwellTimeForTransition(from: .skiing, to: .skiing) == 0)
        #expect(SessionTrackingService.dwellTimeForTransition(from: .idle, to: .idle) == 0)
    }

    // MARK: - Dwell Time State Machine

    @Test func briefAnomalyDoesNotTriggerSwitch() {
        // Start skiing, get 5 seconds of lift readings (< 25s threshold)
        var activity: DetectedActivity = .skiing
        var candidate: DetectedActivity?
        var candidateStart: Date?
        let baseTime = Date()

        for i in 0..<5 {
            let result = SessionTrackingService.applyDwellTime(
                rawActivity: .lift,
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
        // Start skiing, get 26 seconds of lift readings (> 25s threshold)
        var activity: DetectedActivity = .skiing
        var candidate: DetectedActivity?
        var candidateStart: Date?
        let baseTime = Date()

        for i in 0..<26 {
            let result = SessionTrackingService.applyDwellTime(
                rawActivity: .lift,
                currentActivity: activity,
                candidateActivity: candidate,
                candidateStartTime: candidateStart,
                timestamp: baseTime.addingTimeInterval(Double(i))
            )
            activity = result.activity
            candidate = result.candidate
            candidateStart = result.candidateStart
        }

        #expect(activity == .lift) // Must switch after 25s sustained signal
    }

    @Test func interruptedCandidateResetsTimer() {
        // Start skiing, get 20s of lift, then 1 skiing, then 20s of lift
        var activity: DetectedActivity = .skiing
        var candidate: DetectedActivity?
        var candidateStart: Date?
        let baseTime = Date()

        // 20 seconds of lift
        for i in 0..<20 {
            let result = SessionTrackingService.applyDwellTime(
                rawActivity: .lift,
                currentActivity: activity,
                candidateActivity: candidate,
                candidateStartTime: candidateStart,
                timestamp: baseTime.addingTimeInterval(Double(i))
            )
            activity = result.activity
            candidate = result.candidate
            candidateStart = result.candidateStart
        }

        #expect(activity == .skiing) // Not yet (20 < 25)

        // 1 skiing reading — resets the candidate because raw matches current
        let resetResult = SessionTrackingService.applyDwellTime(
            rawActivity: .skiing,
            currentActivity: activity,
            candidateActivity: candidate,
            candidateStartTime: candidateStart,
            timestamp: baseTime.addingTimeInterval(20)
        )
        activity = resetResult.activity
        candidate = resetResult.candidate
        candidateStart = resetResult.candidateStart

        #expect(candidate == nil) // Candidate reset

        // 20 more seconds of lift — timer restarts from scratch
        for i in 21..<41 {
            let result = SessionTrackingService.applyDwellTime(
                rawActivity: .lift,
                currentActivity: activity,
                candidateActivity: candidate,
                candidateStartTime: candidateStart,
                timestamp: baseTime.addingTimeInterval(Double(i))
            )
            activity = result.activity
            candidate = result.candidate
            candidateStart = result.candidateStart
        }

        // 20 seconds from scratch (21..40) < 25s, so still skiing
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
