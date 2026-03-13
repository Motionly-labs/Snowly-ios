//
//  LongPressStartButton.swift
//  Snowly
//
//  Long-press start button with progress ring and haptic feedback.
//

import SwiftUI

struct LongPressStartButton: View {
    let onStart: () -> Void

    @State private var isPressing = false
    @State private var progress: CGFloat = 0
    @State private var pressTask: Task<Void, Never>?

    private let duration: TimeInterval = ProcessInfo.processInfo.arguments.contains("-ui_testing_fast_start")
        ? 0.2
        : 1.0
    private let buttonSize = Spacing.heroButton

    var body: some View {
        buttonCircle
            .frame(width: buttonSize, height: buttonSize)
            .scaleEffect(isPressing ? 0.95 : 1.0)
            .animation(AnimationTokens.quickEaseInOut, value: isPressing)
            .shadow(
                color: ColorTokens.primaryAccent.opacity(isPressing ? Opacity.soft : Opacity.gentle),
                radius: isPressing ? 16 : 20, x: 0, y: isPressing ? 6 : 8
            )
            .shadowStyle(.glassBase)
            .animation(AnimationTokens.quickEaseInOut, value: isPressing)
            .contentShape(Circle())
            .gesture(pressGesture)
            .onDisappear { resetState() }
            .accessibilityIdentifier("start_tracking_button")
            .accessibilityLabel(String(localized: "home_start_button_title"))
            .accessibilityHint(String(localized: "accessibility_long_press_to_start_hint"))
            .accessibilityAddTraits(.isButton)
    }

    private var buttonCircle: some View {
        ZStack {
            accentTintOverlay
            progressRingOverlay
            idleBorderOverlay
            glassHighlightOverlay
            labelOverlay
        }
        .snowlyGlass(in: Circle())
    }

    private var accentTintOverlay: some View {
        Circle()
            .fill(ColorTokens.primaryAccent.opacity(isPressing ? Opacity.pressingAccent : Opacity.faint))
            .animation(AnimationTokens.quickEaseInOut, value: isPressing)
    }

    private var progressRingOverlay: some View {
        Circle()
            .trim(from: 0, to: progress)
            .stroke(
                ColorTokens.primaryAccent,
                style: StrokeStyle(lineWidth: 3, lineCap: .round)
            )
            .rotationEffect(.degrees(-90))
            .padding(Spacing.gap)
    }

    private var idleBorderOverlay: some View {
        Circle()
            .strokeBorder(
                ColorTokens.primaryAccent.opacity(progress > 0 ? 0 : Opacity.mediumHigh),
                lineWidth: 1.5
            )
            .animation(AnimationTokens.quickEaseInOut, value: progress)
    }

    private var glassHighlightOverlay: some View {
        Circle()
            .strokeBorder(ColorTokens.glassHighlightGradient, lineWidth: 1)
    }

    private var labelOverlay: some View {
        Text(String(localized: "home_start_button_title"))
            .font(Typography.buttonHero)
            .foregroundStyle(.primary)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.75)
    }

    private var pressGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let dist = sqrt(
                    value.translation.width * value.translation.width
                    + value.translation.height * value.translation.height
                )
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
        successFeedback.notificationOccurred(.success)

        progress = 1.0
        onStart()
        resetState()
    }

    private func cancelPress() {
        guard isPressing else { return }
        pressTask?.cancel()
        pressTask = nil
        isPressing = false
        withAnimation(AnimationTokens.quickEaseOut) {
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
