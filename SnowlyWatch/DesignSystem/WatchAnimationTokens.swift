//
//  WatchAnimationTokens.swift
//  SnowlyWatch
//
//  Standardized animation timings for watchOS interactions.
//

import SwiftUI

enum WatchAnimationTokens {
    /// Snap-back when a hold gesture is released early.
    static let holdRelease: Animation = .easeOut(duration: 0.18)
}
