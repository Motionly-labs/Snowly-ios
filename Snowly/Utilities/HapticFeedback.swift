//
//  HapticFeedback.swift
//  Snowly
//
//  Thin wrapper over UIImpactFeedbackGenerator so views stay free
//  of direct UIKit imports. Call sites: TrackingStatGrid drag start,
//  ActiveTrackingView long-press to enter edit mode.
//

import UIKit

enum HapticFeedback {
    nonisolated static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
}
