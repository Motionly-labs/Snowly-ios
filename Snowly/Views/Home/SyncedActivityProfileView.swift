//
//  SyncedActivityProfileView.swift
//  Snowly
//
//  Compact dual-curve profile for live altitude and speed updates.
//

import SwiftUI

struct SyncedActivityProfileView: View {
    static var preferredWindowCount: Int { SharedConstants.profileViewWindowCount }

    private struct DisplaySample: Equatable {
        let altitude: Double
        let speed: Double
        let state: SpeedCurveState
    }

    let altitudeSamples: [AltitudeSample]
    let speedSamples: [SpeedSample]
    let unitSystem: UnitSystem

    private var displaySamples: [DisplaySample] {
        let altitudeWindow = Array(
            altitudeSamples
                .droppingLeadingZeroLikeSamples()
                .suffix(Self.preferredWindowCount)
        )
        let speedWindow = Array(
            speedSamples
                .droppingLeadingZeroLikeSamples()
                .suffix(Self.preferredWindowCount)
        )
        let count = min(altitudeWindow.count, speedWindow.count)
        guard count > 1 else { return [] }

        let alignedAltitudes = altitudeWindow.suffix(count)
        let alignedSpeeds = speedWindow.suffix(count)
        return zip(alignedAltitudes, alignedSpeeds).map { altitudeSample, speedSample in
            DisplaySample(
                altitude: altitudeSample.altitude,
                speed: displaySpeed(for: speedSample.speed),
                state: speedSample.state
            )
        }
    }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size

            if displaySamples.count < 2 {
                Path { path in
                    let baseline = size.height - 10
                    path.move(to: CGPoint(x: 0, y: baseline))
                    path.addLine(to: CGPoint(x: size.width, y: baseline))
                }
                .stroke(
                    Color.secondary.opacity(Opacity.muted),
                    style: StrokeStyle(lineWidth: 1, dash: [4, 4])
                )
            } else {
                let rect = CGRect(origin: .zero, size: size)
                let altitudePoints = points(
                    for: displaySamples.map(\.altitude),
                    in: rect,
                    minimumRange: unitSystem == .metric ? 20 : 65,
                    topInset: 8,
                    bottomInset: 12
                )
                let speedPoints = points(
                    for: displaySamples.map(\.speed),
                    in: rect,
                    minimumRange: unitSystem == .metric ? 12 : 8,
                    topInset: 12,
                    bottomInset: 16
                )

                Canvas { context, _ in
                    drawGrid(into: &context, in: rect)

                    context.fill(
                        CurveRendering.smoothFillPath(points: altitudePoints, baseline: rect.maxY - 6),
                        with: .linearGradient(
                            Gradient(colors: [
                                Color.primary.opacity(0.08),
                                Color.primary.opacity(0.0),
                            ]),
                            startPoint: CGPoint(x: rect.midX, y: rect.minY),
                            endPoint: CGPoint(x: rect.midX, y: rect.maxY)
                        )
                    )

                    let altitudePath = CurveRendering.smoothPath(points: altitudePoints)
                    context.stroke(
                        altitudePath,
                        with: .color(Color.primary.opacity(0.28)),
                        style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round, dash: [4, 4])
                    )

                    drawSpeedSegments(into: &context, points: speedPoints)

                    if let lastAltitude = altitudePoints.last {
                        let altitudeMarker = Path(
                            ellipseIn: CGRect(x: lastAltitude.x - 2.5, y: lastAltitude.y - 2.5, width: 5, height: 5)
                        )
                        context.stroke(
                            altitudeMarker,
                            with: .color(Color.primary.opacity(0.38)),
                            lineWidth: 1.25
                        )
                    }

                    if let lastSpeed = speedPoints.last, let lastState = displaySamples.last?.state {
                        let speedMarker = Path(
                            ellipseIn: CGRect(x: lastSpeed.x - 3, y: lastSpeed.y - 3, width: 6, height: 6)
                        )
                        context.fill(speedMarker, with: .color(speedColor(for: lastState)))
                    }
                }
            }
        }
    }

    private func displaySpeed(for metersPerSecond: Double) -> Double {
        switch unitSystem {
        case .metric:
            return UnitConversion.metersPerSecondToKmh(metersPerSecond)
        case .imperial:
            return UnitConversion.metersPerSecondToMph(metersPerSecond)
        }
    }

    private func speedColor(for state: SpeedCurveState) -> Color {
        switch state {
        case .skiing: return ColorTokens.skiingAccent
        case .lift:   return ColorTokens.liftAccent
        case .others: return ColorTokens.walkAccent
        }
    }

    private func drawGrid(into context: inout GraphicsContext, in rect: CGRect) {
        for index in 1...2 {
            let y = rect.minY + (rect.height * CGFloat(index) / 3)
            var path = Path()
            path.move(to: CGPoint(x: rect.minX, y: y))
            path.addLine(to: CGPoint(x: rect.maxX, y: y))
            context.stroke(
                path,
                with: .color(Color.primary.opacity(0.08)),
                style: StrokeStyle(lineWidth: 0.8, dash: [2, 6])
            )
        }
    }

    private func drawSpeedSegments(into context: inout GraphicsContext, points: [CGPoint]) {
        guard points.count >= 2 else { return }

        let strokeStyle = StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round)
        // Batch contiguous same-state segments into one Path each.
        // O(S) where S = number of activity-state transitions, not O(N) points.
        var segStart = 1
        while segStart < points.count {
            let segState = displaySamples[segStart].state
            var j = segStart
            while j < points.count && displaySamples[j].state == segState {
                j += 1
            }
            let segPath = CurveRendering.smoothPath(points: points, range: (segStart - 1)..<j)
            context.stroke(segPath, with: .color(speedColor(for: segState)), style: strokeStyle)
            segStart = j
        }
    }

    private func points(
        for values: [Double],
        in rect: CGRect,
        minimumRange: Double,
        topInset: CGFloat,
        bottomInset: CGFloat
    ) -> [CGPoint] {
        guard !values.isEmpty else { return [] }
        let minValue = values.min() ?? 0
        let maxValue = values.max() ?? 1
        let range = max(maxValue - minValue, minimumRange)
        let usableHeight = max(rect.height - topInset - bottomInset, 1)
        let denominator = CGFloat(max(values.count - 1, 1))

        return values.enumerated().map { index, value in
            let x = rect.minX + rect.width * CGFloat(index) / denominator
            let normalized = (value - minValue) / range
            let y = rect.maxY - bottomInset - CGFloat(normalized) * usableHeight
            return CGPoint(x: x, y: y)
        }
    }
}
