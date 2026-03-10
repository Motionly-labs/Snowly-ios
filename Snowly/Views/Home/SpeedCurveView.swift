//
//  SpeedCurveView.swift
//  Snowly
//
//  Bezier curve visualization for speed history.
//

import SwiftUI

struct SpeedCurveView: View {
    struct Sample: Equatable {
        let value: Double
        let state: SpeedCurveState

        init(value: Double, state: SpeedCurveState = .skiing) {
            self.value = value
            self.state = state
        }
    }

    let samples: [Sample]
    let maxSpeedLabel: Double

    @State private var progress: CGFloat = 0

    private var hasData: Bool {
        samples.contains(where: { $0.value > 0 })
    }

    init(samples: [Sample], maxSpeedLabel: Double) {
        self.samples = samples
        self.maxSpeedLabel = maxSpeedLabel
    }

    init(data: [Double], maxSpeedLabel: Double) {
        self.samples = data.map { Sample(value: $0, state: .skiing) }
        self.maxSpeedLabel = maxSpeedLabel
    }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let graphHeight = max(44, geo.size.height - 18)

            if hasData {
                let points = normalizedPoints(width: width, height: graphHeight)
                let visibleCount = max(2, Int(CGFloat(points.count) * progress))
                let visiblePoints = Array(points.prefix(visibleCount))
                let visibleSamples = Array(samples.prefix(visibleCount))
                let maxIndex = indexOfMax(in: samples.map(\.value))
                let showMax = visibleCount > maxIndex

                ZStack(alignment: .topLeading) {
                    curveFillPath(points: visiblePoints, baseline: graphHeight)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.12),
                                    Color.white.opacity(0.0),
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                    Canvas { context, _ in
                        let strokeCount = min(visiblePoints.count, visibleSamples.count)
                        guard strokeCount > 1 else { return }
                        for index in 1..<strokeCount {
                            var path = Path()
                            path.move(to: visiblePoints[index - 1])
                            path.addLine(to: visiblePoints[index])
                            let strokeColor = stateColor(for: visibleSamples[index].state)
                            context.stroke(
                                path,
                                with: .color(strokeColor),
                                style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
                            )
                        }
                    }

                    if showMax, maxIndex < points.count, maxIndex < samples.count {
                        let point = points[maxIndex]
                        let markerColor = stateColor(for: samples[maxIndex].state)
                        VStack(spacing: Spacing.xs) {
                            Text(String(format: "%.1f", maxSpeedLabel))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Circle()
                                .fill(markerColor)
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
                .stroke(Color.secondary.opacity(Opacity.muted), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
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

    private func stateColor(for state: SpeedCurveState) -> Color {
        switch state {
        case .skiing:
            return ColorTokens.brandIceBlue
        case .lift:
            return ColorTokens.brandWarmAmber
        case .others:
            return Color.secondary.opacity(0.85)
        }
    }

    private func normalizedPoints(width: CGFloat, height: CGFloat) -> [CGPoint] {
        guard samples.count > 1 else {
            return [CGPoint(x: 0, y: height), CGPoint(x: width, y: height)]
        }

        let values = samples.map(\.value)
        let maxValue = robustScaleMax(for: values)
        return values.enumerated().map { index, value in
            let x = CGFloat(index) / CGFloat(values.count - 1) * width
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

    private func curveFillPath(points: [CGPoint], baseline: CGFloat) -> Path {
        var path = Path()
        guard let first = points.first, let last = points.last else { return path }
        path.move(to: first)
        for point in points.dropFirst() {
            path.addLine(to: point)
        }
        path.addLine(to: CGPoint(x: last.x, y: baseline))
        path.addLine(to: CGPoint(x: first.x, y: baseline))
        path.closeSubpath()
        return path
    }
}
