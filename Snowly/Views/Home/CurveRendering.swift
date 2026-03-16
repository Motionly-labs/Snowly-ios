//
//  CurveRendering.swift
//  Snowly
//
//  Shared helpers for smooth chart paths and point inspection overlays.
//

import SwiftUI

enum CurveRendering {
    struct StateSegment: Sendable {
        let range: Range<Int>
        let state: SpeedCurveState
    }

    nonisolated static func smoothPath(points: [CGPoint]) -> Path {
        smoothPath(points: points, range: points.startIndex..<points.endIndex)
    }

    /// Builds a smooth bezier path from a subrange of `points` without copying to a new Array.
    nonisolated static func smoothPath(points: [CGPoint], range: Range<Int>) -> Path {
        var path = Path()
        guard !range.isEmpty else { return path }

        path.move(to: points[range.lowerBound])
        guard range.count > 1 else { return path }
        guard range.count > 2 else {
            path.addLine(to: points[range.lowerBound + 1])
            return path
        }

        let lo = range.lowerBound
        let hi = range.upperBound
        for index in lo..<(hi - 1) {
            let previous = index > lo ? points[index - 1] : points[index]
            let current = points[index]
            let next = points[index + 1]
            let following = index + 2 < hi ? points[index + 2] : next

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

    /// Finds the nearest point for a tap hit-test.
    /// `points` must be x-sorted in ascending order.
    nonisolated static func nearestPointIndex(to x: CGFloat, in points: [CGPoint]) -> Int? {
        guard !points.isEmpty else { return nil }
        // Points are x-sorted — binary search for O(log n) instead of O(n).
        var lo = 0
        var hi = points.count
        while lo < hi {
            let mid = lo + (hi - lo) / 2
            if points[mid].x < x {
                lo = mid + 1
            } else {
                hi = mid
            }
        }
        // lo is the first point with x >= target; compare with lo-1 to find closest.
        if lo == 0 { return 0 }
        if lo >= points.count { return points.count - 1 }
        return abs(points[lo - 1].x - x) <= abs(points[lo].x - x) ? lo - 1 : lo
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
        drawStateSegments(
            into: &context,
            points: points,
            segments: stateSegments(points: points, states: states),
            stateColor: stateColor,
            style: style
        )
    }

    /// Closure-based overload that avoids allocating a `[SpeedCurveState]` array.
    nonisolated static func drawStateSegments(
        into context: inout GraphicsContext,
        points: [CGPoint],
        stateProvider: (Int) -> SpeedCurveState,
        stateColor: (SpeedCurveState) -> Color,
        style: StrokeStyle
    ) {
        drawStateSegments(
            into: &context,
            points: points,
            segments: stateSegments(pointCount: points.count, stateProvider: stateProvider),
            stateColor: stateColor,
            style: style
        )
    }

    nonisolated static func stateSegments(
        points: [CGPoint],
        states: [SpeedCurveState]
    ) -> [StateSegment] {
        guard states.count == points.count else { return [] }
        return stateSegments(
            pointCount: points.count,
            stateProvider: { states[$0] }
        )
    }

    nonisolated static func stateSegments(
        pointCount: Int,
        stateProvider: (Int) -> SpeedCurveState
    ) -> [StateSegment] {
        guard pointCount >= 2 else { return [] }

        var segments: [StateSegment] = []
        segments.reserveCapacity(pointCount / 2)

        var segStart = 1
        while segStart < pointCount {
            let seg = stateProvider(segStart)
            var end = segStart
            while end < pointCount && stateProvider(end) == seg {
                end += 1
            }
            segments.append(StateSegment(range: (segStart - 1)..<end, state: seg))
            segStart = end
        }

        return segments
    }

    nonisolated private static func drawStateSegments(
        into context: inout GraphicsContext,
        points: [CGPoint],
        segments: [StateSegment],
        stateColor: (SpeedCurveState) -> Color,
        style: StrokeStyle
    ) {
        for segment in segments {
            let path = smoothPath(points: points, range: segment.range)
            context.stroke(path, with: .color(stateColor(segment.state)), style: style)
        }
    }
}

extension CurveRendering.StateSegment: Equatable {
    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.range == rhs.range && lhs.state == rhs.state
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
