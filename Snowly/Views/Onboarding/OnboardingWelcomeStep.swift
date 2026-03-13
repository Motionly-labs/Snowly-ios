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

            Image("SnowlyLogo")
                .resizable()
                .renderingMode(.original)
                .scaledToFit()
                .frame(width: 92, height: 92)

            VStack(spacing: Spacing.sm) {
                Text("SNOWLY")
                    .font(Typography.splashTitle.italic())
                    .tracking(2)

                Text(String(localized: "onboarding_welcome_title"))
                    .font(Typography.onboardingTitle)

                Text(String(localized: "onboarding_welcome_subtitle"))
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Spacing.xxxl)
            }

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
