//
//  CurveRenderingTests.swift
//  SnowlyTests
//

import Testing
import CoreGraphics
import Foundation
@testable import Snowly

@Suite("CurveRendering")
struct CurveRenderingTests {

    @Test("stateSegments returns empty when point and state counts differ")
    func stateSegmentsCountMismatch() {
        let points = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 10, y: 10),
            CGPoint(x: 20, y: 5),
        ]
        let states: [SpeedCurveState] = [.skiing, .lift]

        let segments = CurveRendering.stateSegments(points: points, states: states)

        #expect(segments.isEmpty)
    }

    @Test("stateSegments groups contiguous states with shared boundary points")
    func stateSegmentsContiguousRuns() {
        let points = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 10, y: 10),
            CGPoint(x: 20, y: 12),
            CGPoint(x: 30, y: 7),
            CGPoint(x: 40, y: 4),
        ]
        let states: [SpeedCurveState] = [.skiing, .skiing, .lift, .lift, .others]

        let segments = CurveRendering.stateSegments(points: points, states: states)

        #expect(segments.count == 3)
        #expect(segments[0] == CurveRendering.StateSegment(range: 0..<2, state: .skiing))
        #expect(segments[1] == CurveRendering.StateSegment(range: 1..<4, state: .lift))
        #expect(segments[2] == CurveRendering.StateSegment(range: 3..<5, state: .others))
    }

    @Test("nearestPointIndex uses closest x coordinate at the bounds and midpoint")
    func nearestPointIndexBinarySearch() {
        let points = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 10, y: 0),
            CGPoint(x: 20, y: 0),
        ]

        #expect(CurveRendering.nearestPointIndex(to: -5, in: points) == 0)
        #expect(CurveRendering.nearestPointIndex(to: 9, in: points) == 1)
        #expect(CurveRendering.nearestPointIndex(to: 15, in: points) == 1)
        #expect(CurveRendering.nearestPointIndex(to: 99, in: points) == 2)
    }
}

@Suite("CurveSampleSanitizer")
struct CurveSampleSanitizerTests {

    private func makeSpeedSample(_ speed: Double, at second: TimeInterval) -> SpeedSample {
        SpeedSample(
            time: Date(timeIntervalSinceReferenceDate: second),
            speed: speed,
            state: .skiing
        )
    }

    @Test("Array zero-trim removes only leading placeholder values")
    func arrayTrimKeepsInteriorZeros() {
        let samples = [
            makeSpeedSample(0, at: 0),
            makeSpeedSample(0, at: 1),
            makeSpeedSample(12, at: 2),
            makeSpeedSample(0, at: 3),
        ]

        let trimmed = samples.droppingLeadingZeroLikeSamples()

        #expect(trimmed.map { $0.speed } == [12, 0])
    }

    @Test("ArraySlice zero-trim is relative to the slice start")
    func arraySliceTrimUsesSliceStart() {
        let samples = [
            makeSpeedSample(9, at: 0),
            makeSpeedSample(0, at: 1),
            makeSpeedSample(0, at: 2),
            makeSpeedSample(14, at: 3),
            makeSpeedSample(18, at: 4),
        ]

        let trimmed = samples[1...].droppingLeadingZeroLikeSamples()

        #expect(trimmed.map { $0.speed } == [14, 18])
    }

    @Test("ArraySlice returns the full slice when it already starts with a real sample")
    func arraySliceTrimKeepsCleanSlice() {
        let samples = [
            makeSpeedSample(0, at: 0),
            makeSpeedSample(11, at: 1),
            makeSpeedSample(13, at: 2),
        ]

        let trimmed = samples[1...].droppingLeadingZeroLikeSamples()

        #expect(trimmed.map { $0.speed } == [11, 13])
    }
}
