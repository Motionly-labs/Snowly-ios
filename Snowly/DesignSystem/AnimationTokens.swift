//
//  AnimationTokens.swift
//  Snowly
//
//  Standardized animation timings for consistent motion.
//

import SwiftUI

enum AnimationTokens {
    // MARK: - Durations
    static let quick: Double = 0.15
    static let fast: Double = 0.2
    static let standard: Double = 0.25
    static let moderate: Double = 0.3
    static let slow: Double = 0.45

    // MARK: - Preset Animations
    static let quickEaseOut = Animation.easeOut(duration: quick)
    static let quickEaseInOut = Animation.easeInOut(duration: quick)
    static let standardEaseInOut = Animation.easeInOut(duration: standard)
    static let moderateEaseInOut = Animation.easeInOut(duration: moderate)
    static let slowEaseInOut = Animation.easeInOut(duration: slow)
    static let standardEaseIn = Animation.easeIn(duration: standard)
    static let fastEaseInOut = Animation.easeInOut(duration: fast)

    // MARK: - Spring
    static let gentleSpring = Animation.spring(response: 0.35, dampingFraction: 0.7)

    // MARK: - Smooth Entrance (deceleration curve)
    static let smoothEntrance = Animation.timingCurve(0.22, 1, 0.36, 1, duration: 1.5)
    static let smoothEntranceFast = Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.8)
    static let smoothEntranceMedium = Animation.timingCurve(0.22, 1, 0.36, 1, duration: 1.2)
}
