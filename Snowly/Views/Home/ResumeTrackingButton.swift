//
//  ResumeTrackingButton.swift
//  Snowly
//
//  Circular material button that returns to active tracking.
//

import SwiftUI

struct ResumeTrackingButton: View {
    let onTap: () -> Void

    private let buttonSize = Spacing.heroButton

    var body: some View {
        Button(action: onTap) {
            ZStack {
                // Subtle accent tint — signals active session without heavy gradients
                Circle()
                    .fill(ColorTokens.primaryAccent.opacity(Opacity.faint))
                // Thin accent ring: shows "live session" state clearly but quietly
                Circle()
                    .strokeBorder(ColorTokens.primaryAccent.opacity(Opacity.ring), lineWidth: 1.5)
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
        .shadowStyle(.brandGlow)
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
