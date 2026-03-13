//
//  HoldProgressCircleButton.swift
//  SnowlyWatch
//
//  Circular button that requires a sustained hold before triggering.
//

import SwiftUI

struct HoldProgressCircleButton: View {
    let systemImage: String
    let title: String?
    let subtitle: String?
    let tint: Color
    let holdDuration: TimeInterval
    let diameter: CGFloat
    let iconSize: CGFloat
    let action: () -> Void

    @State private var holdProgress: CGFloat = 0
    @State private var didCompleteHold = false

    var body: some View {
        let ringWidth = max(4, diameter * 0.065)
        let innerDiameter = diameter * 0.78
        VStack(spacing: WatchSpacing.sm) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: diameter, height: diameter)

                Circle()
                    .stroke(Color.white.opacity(0.18), lineWidth: ringWidth)
                    .frame(width: diameter, height: diameter)

                Circle()
                    .trim(from: 0, to: holdProgress)
                    .stroke(
                        tint,
                        style: StrokeStyle(lineWidth: ringWidth, lineCap: .round, lineJoin: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .frame(width: diameter, height: diameter)

                Circle()
                    .fill(tint.opacity(0.18))
                    .frame(width: innerDiameter, height: innerDiameter)

                Image(systemName: systemImage)
                    .font(.system(size: iconSize, weight: .bold))
                    .foregroundStyle(tint)
            }
            .contentShape(Circle())
            .onLongPressGesture(minimumDuration: holdDuration, maximumDistance: 28) {
                didCompleteHold = true
                action()
                holdProgress = 0
            } onPressingChanged: { pressing in
                if pressing {
                    didCompleteHold = false
                    withAnimation(.linear(duration: holdDuration)) {
                        holdProgress = 1
                    }
                    return
                }

                if didCompleteHold {
                    holdProgress = 0
                    didCompleteHold = false
                } else {
                    withAnimation(.easeOut(duration: 0.18)) {
                        holdProgress = 0
                    }
                }
            }

            if let title, !title.isEmpty {
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }

            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity)
    }
}
