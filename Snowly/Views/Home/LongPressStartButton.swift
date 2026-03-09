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
    private let buttonSize: CGFloat = 188

    var body: some View {
        let buttonTitle = String(localized: "home_start_button_title")

        Circle()
            .fill(.ultraThinMaterial)
            .frame(width: buttonSize, height: buttonSize)
            .overlay {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.white.opacity(isPressing ? 0.44 : 0.38),
                                ColorTokens.brandGold.opacity(isPressing ? 0.34 : 0.28),
                                ColorTokens.brandWarmAmber.opacity(isPressing ? 0.24 : 0.18)
                            ],
                            center: .center,
                            startRadius: 10,
                            endRadius: buttonSize * 0.56
                        )
                    )
            }
            .overlay {
                Circle()
                    .stroke(.white.opacity(Opacity.medium), lineWidth: 1.4)
            }
            .overlay {
                // Progress ring drawn inside the glass edge
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        ColorTokens.progressArcGradient,
                        style: StrokeStyle(lineWidth: 5, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .padding(5)
            }
            .overlay {
                Text(buttonTitle)
                    .font(Typography.buttonHero)
                    .foregroundStyle(ColorTokens.textOnBrand)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
                    .shadowStyle(.innerGlow)
            }
        .scaleEffect(isPressing ? 0.95 : 1.0)
        .animation(AnimationTokens.quickEaseInOut, value: isPressing)
        .shadow(
            color: ColorTokens.brandWarmAmber.opacity(isPressing ? Opacity.soft : Opacity.gentle),
            radius: isPressing ? 16 : 22,
            x: 0,
            y: isPressing ? 8 : 12
        )
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    // Cancel if finger drifts too far
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
        .accessibilityIdentifier("start_tracking_button")
        .accessibilityLabel(String(localized: "home_start_button_title"))
        .accessibilityHint(String(localized: "accessibility_long_press_to_start_hint"))
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
