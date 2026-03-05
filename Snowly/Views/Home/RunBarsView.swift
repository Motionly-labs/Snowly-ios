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

        HStack(alignment: .bottom, spacing: 6) {
            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                let rawHeight = CGFloat(value / maxValue) * 48
                let animatedHeight = max(2, rawHeight * progress)
                let isMax = index == maxIndex && value > 0

                VStack {
                    Spacer(minLength: 0)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isMax ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(maxWidth: 32)
                        .frame(height: animatedHeight)
                }
                .frame(maxWidth: .infinity, maxHeight: 52)
            }
        }
        .onAppear {
            withAnimation(.timingCurve(0.2, 0.9, 0.25, 1, duration: 1.2)) {
                progress = 1
            }
        }
    }
}
