//
//  OnboardingWelcomeStep.swift
//  Snowly
//
//  Step 1: Welcome screen with app introduction.
//

import SwiftUI

struct OnboardingWelcomeStep: View {
    let onNext: () -> Void

    var body: some View {
        VStack(spacing: Spacing.xxl) {
            Spacer()

            Image(systemName: "mountain.2.fill")
                .font(Typography.onboardingHeroIcon)
                .foregroundStyle(Color.accentColor)

            Text(String(localized: "onboarding_welcome_title"))
                .font(Typography.onboardingTitle)

            Text(String(localized: "onboarding_welcome_subtitle"))
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.xxxl)

            Spacer()

            Button(action: onNext) {
                Text(String(localized: "onboarding_welcome_cta_plan_first_run"))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, Spacing.xxl)
            .padding(.bottom, Spacing.xxxl)
        }
    }
}
