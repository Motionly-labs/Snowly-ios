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
    var suffix: String = ""
    var delay: Double = 0
    var usesNumericTransition: Bool = true
    var animation: Animation? = .easeOut(duration: AnimationTokens.moderate)

    @State private var display: Double = 0
    @State private var hasAppeared = false

    private var formattedValue: String {
        String(format: "%.\(decimals)f", display)
    }

    @ViewBuilder
    private var valueText: some View {
        let text = Text(formattedValue).monospacedDigit()
        if usesNumericTransition {
            text.contentTransition(.numericText())
        } else {
            text
        }
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.xxs) {
            valueText

            if !suffix.isEmpty {
                Text(suffix)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .baselineOffset(1)
            }
        }
        .animation(animation, value: display)
        .onAppear {
            if delay > 0 && !hasAppeared {
                hasAppeared = true
                Task {
                    try? await Task.sleep(for: .seconds(delay))
                    guard !Task.isCancelled else { return }
                    display = value
                }
            } else {
                display = value
            }
        }
        .onChange(of: value) { _, newValue in
            display = newValue
        }
    }
}
