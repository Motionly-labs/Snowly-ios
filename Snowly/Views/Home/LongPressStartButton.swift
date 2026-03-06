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
    @State private var isRingPulsing = false
    @State private var progress: CGFloat = 0
    @State private var hapticTask: Task<Void, Never>?

    private let duration: TimeInterval = ProcessInfo.processInfo.arguments.contains("-ui_testing_fast_start")
        ? 0.2
        : 2.0
    private let buttonSize: CGFloat = 188
    private let ringInset: CGFloat = 6
    private var ringDiameter: CGFloat { buttonSize - ringInset * 2 }

    var body: some View {
        let buttonTitle = String(localized: "home_start_button_title")
        let progressAngle = Angle(degrees: -90 + Double(progress) * 360)

        Circle()
            .fill(.clear)
            .overlay {
                Circle()
                    .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
            }
            .frame(width: buttonSize, height: buttonSize)
            // Keep liquid-glass look but reduce distortion by disabling interactive warping.
            .glassEffect(.clear.tint(.clear), in: .circle)
            .overlay {
                ZStack {
                    Circle()
                        .stroke(
                            ColorTokens.brandWarmOrange.opacity(0.22),
                            style: StrokeStyle(lineWidth: 6, lineCap: .round)
                        )
                        .frame(width: ringDiameter, height: ringDiameter)

                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(
                            ColorTokens.progressArcGradient,
                            style: StrokeStyle(lineWidth: 7, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .frame(width: ringDiameter, height: ringDiameter)
                        .shadow(
                            color: ColorTokens.brandWarmOrange.opacity(isPressing ? 0.7 : 0.4),
                            radius: isPressing ? 10 : 6,
                            x: 0,
                            y: 0
                        )

                    Circle()
                        .stroke(ColorTokens.brandWarmOrange.opacity(isPressing ? 0.28 : 0), lineWidth: 2)
                        .frame(width: ringDiameter + 10, height: ringDiameter + 10)
                        .scaleEffect(isRingPulsing ? 1.04 : 0.96)
                        .opacity(isRingPulsing ? 0.95 : 0.2)

                    if progress > 0.001 {
                        Circle()
                            .fill(ColorTokens.brandGold)
                            .frame(width: 10, height: 10)
                            .overlay {
                                Circle().strokeBorder(.white.opacity(0.7), lineWidth: 1)
                            }
                            .shadow(color: ColorTokens.brandWarmAmber.opacity(0.8), radius: 6, x: 0, y: 0)
                            .offset(y: -ringDiameter / 2)
                            .rotationEffect(progressAngle)
                    }

                    VStack(spacing: 6) {
                        Text(buttonTitle)
                            .font(.system(size: 28, weight: .black, design: .rounded))
                            .foregroundStyle(ColorTokens.buttonTextGradient)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.75)
                            .shadow(color: .black.opacity(0.25), radius: 2, x: 0, y: 1)
                    }
                }
            }
        .scaleEffect(isPressing ? 0.95 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isPressing)
        .contentShape(Circle())
        .onLongPressGesture(
            minimumDuration: duration,
            maximumDistance: 24,
            perform: completePress,
            onPressingChanged: handlePressingChange
        )
        .onDisappear {
            resetState()
        }
        .accessibilityIdentifier("start_tracking_button")
        .accessibilityLabel(String(localized: "home_start_button_title"))
        .accessibilityHint(String(localized: "accessibility_long_press_to_start_hint"))
        .accessibilityAddTraits(.isButton)
    }

    private func handlePressingChange(_ isPressingNow: Bool) {
        if isPressingNow {
            startPress()
        } else if isPressing {
            cancelPress()
        }
    }

    private func startPress() {
        guard !isPressing else { return }
        isPressing = true
        progress = 0
        withAnimation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true)) {
            isRingPulsing = true
        }
        withAnimation(.linear(duration: duration)) {
            progress = 1.0
        }
        scheduleCheckpointHaptics()

        let feedbackGenerator = UIImpactFeedbackGenerator(style: .medium)
        feedbackGenerator.impactOccurred()
    }

    private func completePress() {
        let successFeedback = UINotificationFeedbackGenerator()
        successFeedback.notificationOccurred(.success)

        onStart()
        resetState()
    }

    private func cancelPress() {
        guard isPressing else { return }

        hapticTask?.cancel()
        hapticTask = nil

        isPressing = false
        isRingPulsing = false
        withAnimation(.easeOut(duration: 0.18)) {
            progress = 0
        }
    }

    private func resetState() {
        hapticTask?.cancel()
        hapticTask = nil
        isPressing = false
        isRingPulsing = false
        progress = 0
    }

    private func scheduleCheckpointHaptics() {
        hapticTask?.cancel()
        let interval = UInt64((duration / 3) * 1_000_000_000)
        hapticTask = Task { @MainActor in
            for _ in 1..<3 {
                do {
                    try await Task.sleep(nanoseconds: interval)
                } catch {
                    return
                }

                guard isPressing else { return }
                let checkpointFeedback = UIImpactFeedbackGenerator(style: .light)
                checkpointFeedback.impactOccurred(intensity: 0.8)
            }
        }
    }
}
