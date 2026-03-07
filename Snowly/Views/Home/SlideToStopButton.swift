//
//  SlideToStopButton.swift
//  Snowly
//
//  Slide-to-stop control (like iPhone power off slider).
//  Prevents accidental session termination.
//

import SwiftUI

struct SlideToStopButton: View {
    let onStop: () -> Void

    @State private var offset: CGFloat = 0
    @State private var isDragging = false

    private let trackWidth: CGFloat = 280
    private let thumbSize: CGFloat = 56
    private let trackPadding: CGFloat = 4
    private var maxOffset: CGFloat { trackWidth - thumbSize - trackPadding * 2 }

    private var dragProgress: Double {
        guard maxOffset > 0 else { return 0 }
        return Double(offset / maxOffset)
    }

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay {
                    Capsule()
                        .fill(ColorTokens.error.opacity(Opacity.light))
                }
                .frame(width: trackWidth, height: thumbSize + trackPadding * 2)

            Text(String(localized: "tracking_slide_to_end_day"))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(ColorTokens.error.opacity(max(Opacity.strong - dragProgress, 0)))
                .frame(width: trackWidth, height: thumbSize + trackPadding * 2)

            Circle()
                .fill(ColorTokens.error)
                .shadowStyle(.danger)
                .frame(width: thumbSize, height: thumbSize)
                .overlay {
                    Image(systemName: "stop.fill")
                        .foregroundStyle(.white)
                        .font(Typography.buttonStrong)
                }
                .offset(x: offset + trackPadding)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            isDragging = true
                            offset = min(max(0, value.translation.width), maxOffset)
                        }
                        .onEnded { _ in
                            isDragging = false
                            if offset >= maxOffset * 0.9 {
                                let feedback = UINotificationFeedbackGenerator()
                                feedback.notificationOccurred(.warning)
                                onStop()
                            }
                            withAnimation(AnimationTokens.gentleSpring) {
                                offset = 0
                            }
                        }
                )
                .accessibilityIdentifier("slide_stop_thumb")
        }
        .accessibilityIdentifier("slide_stop_track")
        .accessibilityLabel(String(localized: "tracking_slide_to_end_day"))
        .accessibilityHint(String(localized: "accessibility_slide_to_stop_hint"))
        .accessibilityAddTraits(.isButton)
    }
}
