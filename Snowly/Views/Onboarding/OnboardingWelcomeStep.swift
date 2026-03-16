//
//  OnboardingWelcomeStep.swift
//  Snowly
//
//  Step 1: Welcome — choose to restore from iCloud or start fresh.
//

import SwiftUI

struct OnboardingWelcomeStep: View {
    let onRestore: () -> Void
    let onStartFresh: () -> Void

    var body: some View {
        VStack(spacing: Spacing.xxl) {
            Spacer()

            Image("SnowlyLogo")
                .resizable()
                .renderingMode(.original)
                .scaledToFit()
                .frame(width: 92, height: 92)

            VStack(spacing: Spacing.sm) {
                Text(String(localized: "onboarding_welcome_title"))
                    .font(Typography.onboardingTitle)

                Text(String(localized: "onboarding_welcome_subtitle"))
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Spacing.xxxl)
            }

            Spacer()

            VStack(spacing: Spacing.md) {
                Button(action: onRestore) {
                    Text(String(localized: "onboarding_welcome_cta_restore"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button(action: onStartFresh) {
                    Text(String(localized: "onboarding_welcome_cta_start_fresh"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            .padding(.horizontal, Spacing.xxl)
            .padding(.bottom, Spacing.xxxl)
        }
    }
}
