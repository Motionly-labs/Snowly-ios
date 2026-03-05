//
//  AnimatedNumberText.swift
//  Snowly
//
//  Animated counter with numeric content transition.
//

import SwiftUI

struct AnimatedNumberText: View {
    let value: Double
    var decimals: Int = 0
    var duration: Double = 1.2
    var suffix: String = ""
    var delay: Double = 0

    @State private var display: Double = 0
    @State private var animationTask: Task<Void, Never>?

    private var formattedValue: String {
        String(format: "%.\(decimals)f", display)
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(formattedValue)
                .contentTransition(.numericText())
                .monospacedDigit()

            if !suffix.isEmpty {
                Text(suffix)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .baselineOffset(1)
            }
        }
        .onAppear {
            runAnimation(to: value)
        }
        .onChange(of: value) { _, newValue in
            runAnimation(to: newValue)
        }
        .onDisappear {
            animationTask?.cancel()
        }
    }

    private func runAnimation(to target: Double) {
        animationTask?.cancel()
        animationTask = Task {
            if delay > 0 {
                try? await Task.sleep(for: .seconds(delay))
            }
            guard !Task.isCancelled else { return }
            withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: duration)) {
                display = target
            }
        }
    }
}
