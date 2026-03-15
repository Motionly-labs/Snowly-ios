//
//  CurveRendering.swift
//  Snowly
//
//  Shared helpers for smooth chart paths and point inspection overlays.
//

import SwiftUI

enum CurveRendering {
    nonisolated static func smoothPath(points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }

        path.move(to: first)
        guard points.count > 1 else { return path }
        guard points.count > 2 else {
            path.addLine(to: points[1])
            return path
        }

        for index in 0..<(points.count - 1) {
            let previous = index > 0 ? points[index - 1] : points[index]
            let current = points[index]
            let next = points[index + 1]
            let following = index + 2 < points.count ? points[index + 2] : next

            let control1 = clampedControlPoint(
                CGPoint(
                    x: current.x + (next.x - previous.x) / 6,
                    y: current.y + (next.y - previous.y) / 6
                ),
                between: current,
                and: next
            )
            let control2 = clampedControlPoint(
                CGPoint(
                    x: next.x - (following.x - current.x) / 6,
                    y: next.y - (following.y - current.y) / 6
                ),
                between: current,
                and: next
            )

            path.addCurve(to: next, control1: control1, control2: control2)
        }

        return path
    }

    nonisolated static func smoothFillPath(points: [CGPoint], baseline: CGFloat) -> Path {
        guard let first = points.first, let last = points.last else { return Path() }

        var path = smoothPath(points: points)
        path.addLine(to: CGPoint(x: last.x, y: baseline))
        path.addLine(to: CGPoint(x: first.x, y: baseline))
        path.closeSubpath()
        return path
    }

    nonisolated static func nearestPointIndex(to x: CGFloat, in points: [CGPoint]) -> Int? {
        guard !points.isEmpty else { return nil }
        return points.enumerated().min { lhs, rhs in
            abs(lhs.element.x - x) < abs(rhs.element.x - x)
        }?.offset
    }

    private nonisolated static func clampedControlPoint(
        _ point: CGPoint,
        between start: CGPoint,
        and end: CGPoint
    ) -> CGPoint {
        CGPoint(
            x: min(max(point.x, min(start.x, end.x)), max(start.x, end.x)),
            y: min(max(point.y, min(start.y, end.y)), max(start.y, end.y))
        )
    }

    // MARK: - Shared design constants

    /// Stroke weight used by all active-tracking series card curves.
    nonisolated static let standardStrokeWidth: CGFloat = 2.0

    /// Top-of-fill opacity for the area gradient on all series card curves.
    nonisolated static let standardFillTopOpacity: Double = 0.12

    // MARK: - Coordinate normalisation

    /// Computes evenly-spaced `CGPoint` coordinates for an index-based value series.
    ///
    /// The value at `origin` maps to `size.height - bottomInset`, and the value
    /// at `origin + scale` maps to `topInset`, so data fills the usable interior of
    /// the frame with consistent visual proportions across all series cards.
    ///
    /// - Parameters:
    ///   - values: The series to render.
    ///   - size: The available draw area.
    ///   - origin: Value mapped to the bottom of the usable area. `nil` → `values.min()`.
    ///   - scale: Full range mapped to the usable height. `nil` → `max(values.max() - origin, minimumRange)`.
    ///   - minimumRange: Floor for `scale` to prevent flat-line artefacts on constant data.
    ///   - topInset: Pixels reserved above the peak.
    ///   - bottomInset: Pixels reserved below the minimum.
    nonisolated static func indexedPoints(
        values: [Double],
        in size: CGSize,
        origin: Double? = nil,
        scale: Double? = nil,
        minimumRange: Double = 1,
        topInset: CGFloat = 4,
        bottomInset: CGFloat = 4
    ) -> [CGPoint] {
        guard values.count >= 2 else { return [] }
        let resolvedOrigin = origin ?? (values.min() ?? 0)
        let resolvedScale: Double
        if let s = scale {
            resolvedScale = max(s, minimumRange)
        } else {
            resolvedScale = max((values.max() ?? 1) - resolvedOrigin, minimumRange)
        }
        let usableHeight = max(size.height - topInset - bottomInset, 1)
        let step = size.width / CGFloat(max(values.count - 1, 1))
        return values.enumerated().map { index, value in
            let x = CGFloat(index) * step
            let normalized = CGFloat(min(max(value - resolvedOrigin, 0) / resolvedScale, 1))
            let y = size.height - bottomInset - normalized * usableHeight
            return CGPoint(x: x, y: y)
        }
    }

    /// 90th-percentile cap for speed-history y-scale.
    ///
    /// Isolated speed spikes don't compress the visible range of the rest of the curve.
    nonisolated static func robustScaleMax(for values: [Double]) -> Double {
        let positives = values.filter { $0 > 0 }.sorted()
        guard let peak = positives.last else { return 1 }
        guard positives.count >= 6 else { return max(peak, 1) }
        let p90 = positives[Int(Double(positives.count - 1) * 0.9)]
        return max(min(peak, p90 * 1.12), 1)
    }

    // MARK: - Segment drawing

    /// Draws bezier segments batched by activity state — O(S) `Path` allocations
    /// where S equals the number of state transitions, not the number of data points.
    nonisolated static func drawStateSegments(
        into context: inout GraphicsContext,
        points: [CGPoint],
        states: [SpeedCurveState],
        stateColor: (SpeedCurveState) -> Color,
        style: StrokeStyle
    ) {
        guard points.count >= 2, states.count == points.count else { return }
        var segStart = 1
        while segStart < points.count {
            let seg = states[segStart]
            var j = segStart
            while j < points.count && states[j] == seg { j += 1 }
            let path = smoothPath(points: Array(points[(segStart - 1)..<j]))
            context.stroke(path, with: .color(stateColor(seg)), style: style)
            segStart = j
        }
    }
}

// MARK: - SpeedCurveState rendering colour

extension SpeedCurveState {
    /// Canonical tint for each activity phase, used across all series card curves.
    var trackingColor: Color {
        switch self {
        case .skiing: ColorTokens.skiingAccent
        case .lift:   ColorTokens.liftAccent
        case .others: ColorTokens.walkAccent
        }
    }
}

struct CurveSelectionOverlay: View {
    let point: CGPoint
    let baseline: CGFloat
    let label: String
    let tint: Color
    let chartSize: CGSize

    private var labelX: CGFloat {
        let horizontalInset: CGFloat = 56
        let maxX = max(chartSize.width - horizontalInset, horizontalInset)
        return min(max(point.x, horizontalInset), maxX)
    }

    private var labelY: CGFloat {
        if point.y < 24 {
            return min(point.y + 22, baseline - 12)
        }
        return max(point.y - 22, 12)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Path { path in
                path.move(to: CGPoint(x: point.x, y: baseline))
                path.addLine(to: point)
            }
            .stroke(
                tint.opacity(0.42),
                style: StrokeStyle(lineWidth: 1, lineCap: .round)
            )

            Circle()
                .fill(tint)
                .frame(width: 9, height: 9)
                .overlay {
                    Circle()
                        .stroke(Color.white.opacity(0.9), lineWidth: 1.5)
                }
                .position(point)

            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.xs)
                .snowlyGlass(in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(tint.opacity(0.2), lineWidth: 1)
                }
                .position(x: labelX, y: labelY)
        }
        .allowsHitTesting(false)
    }
}
