//
//  OnboardingWelcomeStep.swift
//  Snowly
//
//  Step 1: Welcome — choose to restore from iCloud or start fresh.
//  Shows contextual hints when a returning user or offline-returning user is detected.
//

import SwiftUI

struct OnboardingWelcomeStep: View {
    let coordinatorState: LaunchRestorationCoordinator.State
    let onRestore: () -> Void
    let onStartFresh: () -> Void

    private var isReturningUser: Bool {
        coordinatorState == .returningUser
    }

    private var isOfflineReturning: Bool {
        coordinatorState == .offlineReturning
    }

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

            if isReturningUser {
                Label(
                    String(localized: "onboarding_welcome_returning_hint"),
                    systemImage: "icloud.and.arrow.down"
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.horizontal, Spacing.xxl)
            }

            if isOfflineReturning {
                Label(
                    String(localized: "onboarding_welcome_offline_hint"),
                    systemImage: "icloud.slash"
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.horizontal, Spacing.xxl)
            }

            Spacer()

            VStack(spacing: Spacing.md) {
                if !isOfflineReturning {
                    restoreButton
                }

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

    @ViewBuilder
    private var restoreButton: some View {
        if isReturningUser {
            Button(action: onRestore) {
                Text(String(localized: "onboarding_welcome_cta_restore"))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        } else {
            Button(action: onRestore) {
                Text(String(localized: "onboarding_welcome_cta_restore"))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
    }
}
