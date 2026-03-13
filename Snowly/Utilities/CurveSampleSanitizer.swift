//
//  CurveSampleSanitizer.swift
//  Snowly
//
//  Drops leading placeholder zero-values from live curve sample streams.
//  Keeps later zero readings intact so real pauses and idle segments still render.
//

import Foundation

nonisolated protocol CurveZeroTrimValueProviding {
    var curveValueForZeroTrim: Double { get }
}

extension SpeedSample: CurveZeroTrimValueProviding {
    nonisolated var curveValueForZeroTrim: Double { speed }
}

extension AltitudeSample: CurveZeroTrimValueProviding {
    nonisolated var curveValueForZeroTrim: Double { altitude }
}

extension HeartRateSample: CurveZeroTrimValueProviding {
    nonisolated var curveValueForZeroTrim: Double { bpm }
}

extension Array where Element: CurveZeroTrimValueProviding {
    nonisolated func droppingLeadingZeroLikeSamples(threshold: Double = 0.0001) -> [Element] {
        guard let firstValidIndex = firstIndex(where: { abs($0.curveValueForZeroTrim) > threshold }) else {
            return []
        }
        return Array(self[firstValidIndex...])
    }
}
