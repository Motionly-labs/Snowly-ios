//
//  CurveRendering.swift
//  Snowly
//
//  Shared helpers for smooth chart paths and point inspection overlays.
//

import SwiftUI

enum CurveRendering {
    static func smoothPath(points: [CGPoint]) -> Path {
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

    static func smoothFillPath(points: [CGPoint], baseline: CGFloat) -> Path {
        guard let first = points.first, let last = points.last else { return Path() }

        var path = smoothPath(points: points)
        path.addLine(to: CGPoint(x: last.x, y: baseline))
        path.addLine(to: CGPoint(x: first.x, y: baseline))
        path.closeSubpath()
        return path
    }

    static func nearestPointIndex(to x: CGFloat, in points: [CGPoint]) -> Int? {
        guard !points.isEmpty else { return nil }
        return points.enumerated().min { lhs, rhs in
            abs(lhs.element.x - x) < abs(rhs.element.x - x)
        }?.offset
    }

    private static func clampedControlPoint(
        _ point: CGPoint,
        between start: CGPoint,
        and end: CGPoint
    ) -> CGPoint {
        CGPoint(
            x: min(max(point.x, min(start.x, end.x)), max(start.x, end.x)),
            y: min(max(point.y, min(start.y, end.y)), max(start.y, end.y))
        )
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
