//
//  SpeedCurveView.swift
//  Snowly
//
//  Bezier curve visualization for speed history.
//

import SwiftUI

struct SpeedCurveView: View {
    let data: [Double]
    let maxSpeedLabel: Double

    @State private var progress: CGFloat = 0

    private var hasData: Bool {
        data.contains(where: { $0 > 0 })
    }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let graphHeight = max(44, geo.size.height - 18)

            if hasData {
                let points = normalizedPoints(width: width, height: graphHeight)
                let visibleCount = max(2, Int(CGFloat(points.count) * progress))
                let visible = Array(points.prefix(visibleCount))
                let maxIndex = indexOfMax(in: data)
                let showMax = visibleCount > maxIndex

                ZStack(alignment: .topLeading) {
                    curveFillPath(points: visible, baseline: graphHeight)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.accentColor.opacity(Opacity.light),
                                    Color.accentColor.opacity(0.0),
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                    catmullRomPath(points: visible)
                        .stroke(
                            Color.accentColor,
                            style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
                        )

                    if showMax, maxIndex < points.count {
                        let point = points[maxIndex]
                        VStack(spacing: Spacing.xs) {
                            Text(String(format: "%.1f", maxSpeedLabel))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Circle()
                                .fill(Color.accentColor)
                                .frame(width: 6, height: 6)
                        }
                        .position(x: point.x, y: point.y - 12)
                        .opacity(
                            progress > 0.5
                                ? Double((progress - CGFloat(0.5)) * CGFloat(2.0))
                                : 0
                        )
                    }
                }
            } else {
                // Empty state: flat baseline
                Path { path in
                    path.move(to: CGPoint(x: 0, y: graphHeight))
                    path.addLine(to: CGPoint(x: width, y: graphHeight))
                }
                .stroke(Color.accentColor.opacity(Opacity.muted), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
        }
        .onChange(of: hasData) { _, newValue in
            if newValue && progress == 0 {
                withAnimation(AnimationTokens.smoothEntrance) {
                    progress = 1
                }
            }
        }
        .onAppear {
            if hasData {
                withAnimation(AnimationTokens.smoothEntrance) {
                    progress = 1
                }
            }
        }
    }

    private func indexOfMax(in values: [Double]) -> Int {
        guard let max = values.max(), let index = values.firstIndex(of: max) else { return 0 }
        return index
    }

    private func normalizedPoints(width: CGFloat, height: CGFloat) -> [CGPoint] {
        guard data.count > 1 else {
            return [CGPoint(x: 0, y: height), CGPoint(x: width, y: height)]
        }

        let maxValue = robustScaleMax(for: data)
        return data.enumerated().map { index, value in
            let x = CGFloat(index) / CGFloat(data.count - 1) * width
            let clamped = min(max(value, 0), maxValue)
            let y = height - CGFloat(clamped / maxValue) * height * 0.85 - 4
            return CGPoint(x: x, y: y)
        }
    }

    /// Uses a high percentile so isolated spikes don't flatten the whole curve.
    private func robustScaleMax(for values: [Double]) -> Double {
        let positives = values.filter { $0 > 0 }.sorted()
        guard let peak = positives.last else { return 1 }
        guard positives.count >= 6 else { return max(peak, 1) }

        let percentile90 = positives[Int(Double(positives.count - 1) * 0.9)]
        let padded = percentile90 * 1.12
        return max(min(peak, padded), 1)
    }

    /// Catmull-Rom spline for smooth, natural-looking curves through all data points.
    private func catmullRomPath(points: [CGPoint], alpha: CGFloat = 0.5) -> Path {
        var path = Path()
        guard points.count >= 2 else { return path }

        path.move(to: points[0])

        if points.count == 2 {
            path.addLine(to: points[1])
            return path
        }

        for i in 0..<points.count - 1 {
            let p0 = i > 0 ? points[i - 1] : points[i]
            let p1 = points[i]
            let p2 = points[i + 1]
            let p3 = i + 2 < points.count ? points[i + 2] : points[i + 1]

            let d1 = distance(p0, p1)
            let d2 = distance(p1, p2)
            let d3 = distance(p2, p3)

            let d1a = pow(d1, alpha)
            let d2a = pow(d2, alpha)
            let d3a = pow(d3, alpha)

            let b1x = (d1a * d1a * p2.x - d2a * d2a * p0.x + (2 * d1a * d1a + 3 * d1a * d2a + d2a * d2a) * p1.x) / (3 * d1a * (d1a + d2a))
            let b1y = (d1a * d1a * p2.y - d2a * d2a * p0.y + (2 * d1a * d1a + 3 * d1a * d2a + d2a * d2a) * p1.y) / (3 * d1a * (d1a + d2a))

            let b2x = (d3a * d3a * p1.x - d2a * d2a * p3.x + (2 * d3a * d3a + 3 * d3a * d2a + d2a * d2a) * p2.x) / (3 * d3a * (d3a + d2a))
            let b2y = (d3a * d3a * p1.y - d2a * d2a * p3.y + (2 * d3a * d3a + 3 * d3a * d2a + d2a * d2a) * p2.y) / (3 * d3a * (d3a + d2a))

            let cp1 = CGPoint(x: b1x.isNaN ? p1.x : b1x, y: b1y.isNaN ? p1.y : b1y)
            let cp2 = CGPoint(x: b2x.isNaN ? p2.x : b2x, y: b2y.isNaN ? p2.y : b2y)

            path.addCurve(to: p2, control1: cp1, control2: cp2)
        }
        return path
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = a.x - b.x
        let dy = a.y - b.y
        return sqrt(dx * dx + dy * dy)
    }

    private func curveFillPath(points: [CGPoint], baseline: CGFloat) -> Path {
        var path = catmullRomPath(points: points)
        guard let first = points.first, let last = points.last else { return path }
        path.addLine(to: CGPoint(x: last.x, y: baseline))
        path.addLine(to: CGPoint(x: first.x, y: baseline))
        path.closeSubpath()
        return path
    }
}
