//
//  LongPressStopButton.swift
//  Snowly
//
//  Compact long-press stop button with circular progress ring.
//  Requires a full ring revolution to trigger, preventing accidental stops.
//

import SwiftUI

struct LongPressStopButton: View {
    let onStop: () -> Void

    @State private var isPressing = false
    @State private var progress: CGFloat = 0
    @State private var pressTask: Task<Void, Never>?

    private let duration: TimeInterval = ProcessInfo.processInfo.arguments.contains("-ui_testing_fast_start")
        ? 0.2
        : 1.0
    private let buttonSize: CGFloat = 36
    private let ringLineWidth: CGFloat = 3

    var body: some View {
        Circle()
            .fill(.clear)
            .frame(width: buttonSize, height: buttonSize)
            .glassEffect(.regular, in: .circle)
            .overlay {
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        ColorTokens.error,
                        style: StrokeStyle(lineWidth: ringLineWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .padding(Spacing.xxs)
            }
            .overlay {
                Image(systemName: "stop.fill")
                    .font(Typography.smallBold)
                    .foregroundStyle(ColorTokens.error)
            }
        .scaleEffect(isPressing ? 0.9 : 1.0)
        .animation(AnimationTokens.quickEaseInOut, value: isPressing)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let dist = sqrt(value.translation.width * value.translation.width
                                  + value.translation.height * value.translation.height)
                    if dist > 24 {
                        cancelPress()
                        return
                    }
                    if !isPressing {
                        startPress()
                    }
                }
                .onEnded { _ in
                    cancelPress()
                }
        )
        .onDisappear {
            resetState()
        }
        .accessibilityLabel(String(localized: "tracking_stop_confirm_action"))
        .accessibilityHint(String(localized: "accessibility_long_press_to_stop_hint"))
        .accessibilityAddTraits(.isButton)
    }

    private func startPress() {
        guard !isPressing else { return }
        isPressing = true
        progress = 0

        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        withAnimation(.linear(duration: duration)) {
            progress = 1.0
        }

        let hapticDelay = duration / 3
        pressTask = Task { @MainActor in
            for _ in 0..<2 {
                try? await Task.sleep(for: .seconds(hapticDelay))
                guard isPressing else { return }
                UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.8)
            }
            try? await Task.sleep(for: .seconds(hapticDelay))
            guard isPressing else { return }
            completePress()
        }
    }

    private func completePress() {
        let successFeedback = UINotificationFeedbackGenerator()
        successFeedback.notificationOccurred(.warning)

        progress = 1.0
        onStop()
        resetState()
    }

    private func cancelPress() {
        guard isPressing else { return }
        pressTask?.cancel()
        pressTask = nil
        isPressing = false
        withAnimation(.easeOut(duration: 0.18)) {
            progress = 0
        }
    }

    private func resetState() {
        pressTask?.cancel()
        pressTask = nil
        isPressing = false
        progress = 0
    }
}
