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
    @State private var cachedScaleMax: Double = 1

    private var hasData: Bool {
        samples.contains(where: { $0.value > 0 })
    }

    init(samples: [Sample], maxSpeedLabel: Double) {
        self.samples = samples
        self.maxSpeedLabel = maxSpeedLabel
    }

    init(data: [Double], maxSpeedLabel: Double) {
        self.samples = data.map { Sample(value: $0) }
        self.maxSpeedLabel = maxSpeedLabel
    }

    var body: some View {
        GeometryReader { geo in
            // Reserve 18 pt at the bottom for the max-speed label so it never clips.
            let graphHeight = max(44, geo.size.height - 18)
            let size = CGSize(width: geo.size.width, height: graphHeight)

            if hasData {
                let values = samples.map(\.value)
                let allPoints = CurveRendering.indexedPoints(
                    values: values,
                    in: size,
                    origin: 0,
                    scale: cachedScaleMax
                )
                let visibleCount = max(2, Int(CGFloat(allPoints.count) * progress))
                let visiblePoints = Array(allPoints.prefix(visibleCount))
                let visibleSamples = Array(samples.prefix(visibleCount))
                let maxIdx = visibleSamples.indices
                    .max(by: { visibleSamples[$0].value < visibleSamples[$1].value }) ?? 0

                ZStack(alignment: .topLeading) {
                    TrackingSeriesCurveView(
                        points: visiblePoints,
                        coloring: .byState(visibleSamples.map(\.state)) { $0.trackingColor },
                        fillColors: [
                            .white.opacity(CurveRendering.standardFillTopOpacity),
                            .white.opacity(0),
                        ]
                        // selectionLabel intentionally nil — session history shows
                        // the max marker instead of a tap overlay.
                    )
                    .frame(width: size.width, height: graphHeight)

                    if progress > 0, maxIdx < visiblePoints.count {
                        let pt = visiblePoints[maxIdx]
                        VStack(spacing: Spacing.xs) {
                            Text(String(format: "%.1f", maxSpeedLabel))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Circle()
                                .fill(visibleSamples[maxIdx].state.trackingColor)
                                .frame(width: 6, height: 6)
                        }
                        .position(x: pt.x, y: pt.y - 12)
                        .opacity(progress > 0.5 ? Double((progress - 0.5) * 2.0) : 0)
                    }
                }
            } else {
                Path { path in
                    path.move(to: CGPoint(x: 0, y: graphHeight))
                    path.addLine(to: CGPoint(x: geo.size.width, y: graphHeight))
                }
                .stroke(Color.secondary.opacity(Opacity.muted), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
        }
        .onChange(of: hasData) { _, newValue in
            if newValue && progress == 0 {
                withAnimation(AnimationTokens.smoothEntrance) { progress = 1 }
            }
        }
        .onChange(of: samples) { _, _ in
            cachedScaleMax = CurveRendering.robustScaleMax(for: samples.map(\.value))
        }
        .onAppear {
            cachedScaleMax = CurveRendering.robustScaleMax(for: samples.map(\.value))
            if hasData {
                withAnimation(AnimationTokens.smoothEntrance) { progress = 1 }
            }
        }
    }
}
