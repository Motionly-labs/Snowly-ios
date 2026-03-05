//
//  ResumeTrackingButton.swift
//  Snowly
//
//  Circular material button that returns to active tracking.
//

import SwiftUI

struct ResumeTrackingButton: View {
    let onTap: () -> Void

    private let buttonSize: CGFloat = 188

    var body: some View {
        Button(action: onTap) {
            Circle()
                .fill(.regularMaterial)
                .overlay {
                    Circle()
                        .fill(ColorTokens.brandVerticalGradient.opacity(0.16))
                }
                .overlay {
                    Circle()
                        .strokeBorder(ColorTokens.brandWarmOrange.opacity(0.25), lineWidth: 1)
                }
                .overlay {
                    Circle()
                        .stroke(
                            ColorTokens.progressArcGradient,
                            style: StrokeStyle(lineWidth: 6, lineCap: .round)
                        )
                        .padding(Spacing.sm)
                        .opacity(0.8)
                }
                .frame(width: buttonSize, height: buttonSize)
                .overlay {
                    Text(String(localized: "tracking_resume_button_label"))
                        .font(.system(size: 24, weight: .black, design: .rounded))
                        .foregroundStyle(ColorTokens.buttonTextGradient)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Spacing.xl)
                        .shadow(color: .black.opacity(0.25), radius: 2, x: 0, y: 1)
                }
        }
        .buttonStyle(.plain)
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
