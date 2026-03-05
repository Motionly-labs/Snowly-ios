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
    private let thumbSize: CGFloat = 52
    private var maxOffset: CGFloat { trackWidth - thumbSize - 8 }

    var body: some View {
        ZStack(alignment: .leading) {
            // Track
            RoundedRectangle(cornerRadius: thumbSize / 2)
                .fill(Color.red.opacity(0.15))
                .frame(width: trackWidth, height: thumbSize + 8)

            // Label
            Text(String(localized: "tracking_slide_to_end_day"))
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(Color.red.opacity(0.6))
                .frame(width: trackWidth, height: thumbSize + 8)

            // Thumb
            Circle()
                .fill(.red)
                .frame(width: thumbSize, height: thumbSize)
                .overlay {
                    Image(systemName: "stop.fill")
                        .foregroundStyle(.white)
                        .font(.system(size: 16, weight: .bold))
                }
                .offset(x: offset + 4)
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
                            withAnimation(.spring(response: 0.3)) {
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
