//
//  ChartTokens.swift
//  Snowly
//
//  Shared visual tokens for product charts.
//

import CoreGraphics

enum ChartTokens {
    enum HalfViolin {
        static let gridLineOpacity: Double = 0.08
        static let baselineOpacity: Double = 0.14

        // Selection behavior: selected 0% transparency, others 70% transparency.
        static let selectedAlpha: Double = 1.0
        static let dimmedAlpha: Double = 0.3

        static let axisLineWidthSelected: CGFloat = 1.6
        static let axisLineWidthDimmed: CGFloat = 1.05

        static let violinFillTopOpacity: Double = 0.66
        static let violinFillBottomOpacity: Double = 0.28
        static let violinStrokeOpacity: Double = 0.96
        static let violinStrokeWidth: CGFloat = 1.0

        static let meanRadiusSelected: CGFloat = 4.7
        static let meanRadiusDimmed: CGFloat = 3.9
        static let meanStrokeWidth: CGFloat = 1.7
    }
}
