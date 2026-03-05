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

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let graphHeight = max(44, geo.size.height - 18)
            let points = normalizedPoints(width: width, height: graphHeight)
            let visibleCount = max(2, Int(CGFloat(points.count) * progress))
            let visible = Array(points.prefix(visibleCount))
            let maxIndex = indexOfMax(in: data)
            let showMax = visibleCount > maxIndex

            ZStack(alignment: .topLeading) {
                if visible.count >= 2 {
                    curveFillPath(points: visible, baseline: graphHeight)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.accentColor.opacity(0.15),
                                    Color.accentColor.opacity(0.0),
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                    curveLinePath(points: visible)
                        .stroke(
                            Color.accentColor,
                            style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                        )
                }

                if showMax, maxIndex < points.count {
                    let point = points[maxIndex]
                    VStack(spacing: 4) {
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
        }
        .onAppear {
            withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 1.5)) {
                progress = 1
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

        let maxValue = max(data.max() ?? 1, 1)
        return data.enumerated().map { index, value in
            let x = CGFloat(index) / CGFloat(data.count - 1) * width
            let y = height - CGFloat(value / maxValue) * height * 0.9 - 4
            return CGPoint(x: x, y: y)
        }
    }

    private func curveLinePath(points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)

        for index in 1..<points.count {
            let prev = points[index - 1]
            let curr = points[index]
            let cp1 = CGPoint(x: prev.x + (curr.x - prev.x) * 0.4, y: prev.y)
            let cp2 = CGPoint(x: prev.x + (curr.x - prev.x) * 0.6, y: curr.y)
            path.addCurve(to: curr, control1: cp1, control2: cp2)
        }
        return path
    }

    private func curveFillPath(points: [CGPoint], baseline: CGFloat) -> Path {
        var path = curveLinePath(points: points)
        guard let first = points.first, let last = points.last else { return path }
        path.addLine(to: CGPoint(x: last.x, y: baseline))
        path.addLine(to: CGPoint(x: first.x, y: baseline))
        path.closeSubpath()
        return path
    }
}
