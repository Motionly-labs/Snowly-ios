//
//  CurveSampleSanitizer.swift
//  Snowly
//
//  Drops leading placeholder zero-values from live curve sample streams.
//  Keeps later zero readings intact so real pauses and idle segments still render.
//

import Foundation

protocol CurveZeroTrimValueProviding {
    var curveValueForZeroTrim: Double { get }
}

extension SpeedSample: CurveZeroTrimValueProviding {
    var curveValueForZeroTrim: Double { speed }
}

extension AltitudeSample: CurveZeroTrimValueProviding {
    var curveValueForZeroTrim: Double { altitude }
}

extension HeartRateSample: CurveZeroTrimValueProviding {
    var curveValueForZeroTrim: Double { bpm }
}

extension Array where Element: CurveZeroTrimValueProviding {
    func droppingLeadingZeroLikeSamples(threshold: Double = 0.0001) -> [Element] {
        guard let firstValidIndex = firstIndex(where: { abs($0.curveValueForZeroTrim) > threshold }) else {
            return []
        }
        return Array(self[firstValidIndex...])
    }
}
