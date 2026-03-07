//
//  ActivityRingView.swift
//  Snowly
//
//  Circular progress ring for activity tracking.
//

import SwiftUI

struct ActivityRingView: View {
    let targetProgress: Double
    var size: CGFloat = 56
    var strokeWidth: CGFloat = 5
    var color: Color = .accentColor
    var delay: Double = 0

    @State private var progress: Double = 0
    @State private var animationTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            Circle()
                .stroke(.quaternary, lineWidth: strokeWidth)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    color,
                    style: StrokeStyle(
                        lineWidth: strokeWidth,
                        lineCap: .round
                    )
                )
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
        .accessibilityLabel(String(localized: "accessibility_activity_ring"))
        .accessibilityValue("\(Int(targetProgress * 100))%")
        .onAppear {
            animationTask?.cancel()
            animationTask = Task {
                if delay > 0 {
                    try? await Task.sleep(for: .seconds(delay))
                }
                guard !Task.isCancelled else { return }
                withAnimation(AnimationTokens.smoothEntrance) {
                    progress = targetProgress
                }
            }
        }
        .onChange(of: targetProgress) { _, newProgress in
            withAnimation(.easeOut(duration: 0.4)) {
                progress = newProgress
            }
        }
        .onDisappear {
            animationTask?.cancel()
        }
    }
}
