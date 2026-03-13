//
//  ResumeTrackingButton.swift
//  Snowly
//
//  Circular material button that returns to active tracking.
//

import SwiftUI

struct ResumeTrackingButton: View {
    let onTap: () -> Void

    @State private var pulseScale: CGFloat = 1.0

    private let buttonSize = Spacing.heroButton

    var body: some View {
        Button(action: onTap) {
            ZStack {
                // Warm amber tint — signals active session
                Circle()
                    .fill(ColorTokens.brandWarmAmber.opacity(Opacity.gentle))
                // Live-pulse ring: subtle breathing animation indicates recording is running
                Circle()
                    .strokeBorder(ColorTokens.brandWarmAmber.opacity(Opacity.ring), lineWidth: 1.5)
                    .scaleEffect(pulseScale)
                    .animation(
                        .easeInOut(duration: 1.8).repeatForever(autoreverses: true),
                        value: pulseScale
                    )
                    .onAppear { pulseScale = 1.04 }
                Circle()
                    .strokeBorder(ColorTokens.glassHighlightGradient, lineWidth: 1)
                Text(String(localized: "tracking_resume_button_label"))
                    .font(Typography.buttonResume)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Spacing.xl)
            }
            .frame(width: buttonSize, height: buttonSize)
            .snowlyGlass(in: Circle())
        }
        .buttonStyle(.plain)
        .shadowStyle(.brandAmberGlow)
        .shadowStyle(.glassBase)
        .accessibilityIdentifier("resume_tracking_dashboard_button")
        .accessibilityLabel(String(localized: "tracking_resume_button_label"))
    }
}

#Preview("Resume Tracking Button") {
    ZStack {
        LinearGradient(
            colors: [
                Color(red: 0.26, green: 0.31, blue: 0.35),
                Color(red: 0.15, green: 0.18, blue: 0.22),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()

        ResumeTrackingButton { }
    }
    .frame(width: 360, height: 640)
}
