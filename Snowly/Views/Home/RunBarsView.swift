//
//  RunBarsView.swift
//  Snowly
//
//  Animated bar chart showing speed per run.
//

import SwiftUI

struct RunBarsView: View {
    let values: [Double]
    @State private var progress: CGFloat = 0

    var body: some View {
        let maxValue = max(values.max() ?? 1, 1)
        let maxIndex = values.firstIndex(of: values.max() ?? 0) ?? 0

        HStack(alignment: .bottom, spacing: Spacing.gap) {
            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                let rawHeight = CGFloat(value / maxValue) * 48
                let animatedHeight = max(2, rawHeight * progress)
                let isMax = index == maxIndex && value > 0
                let runGradient = RunColorPalette.chartGradientColors(
                    forRunIndex: index,
                    totalRuns: max(values.count, 1)
                )

                VStack {
                    Spacer(minLength: 0)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            LinearGradient(
                                colors: [
                                    runGradient.top.opacity(isMax ? 0.95 : 0.68),
                                    runGradient.bottom.opacity(isMax ? 0.92 : 0.55),
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .overlay {
                            if isMax {
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(Color.white.opacity(0.45), lineWidth: 0.9)
                            }
                        }
                        .frame(maxWidth: 32)
                        .frame(height: animatedHeight)
                }
                .frame(maxWidth: .infinity, maxHeight: 52)
            }
        }
        .onAppear {
            withAnimation(AnimationTokens.smoothEntranceMedium) {
                progress = 1
            }
        }
    }
}
