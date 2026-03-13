//
//  OnboardingFlow.swift
//  Snowly
//
//  3-step onboarding: Welcome -> Permissions -> Preferences.
//

import SwiftUI
import SwiftData

struct OnboardingFlow: View {
    private enum OnboardingStep: Int {
        case welcome = 0
        case permissions = 1
        case preferences = 2
    }

    @State private var currentStep = OnboardingStep.welcome

    var body: some View {
        TabView(selection: $currentStep) {
            OnboardingWelcomeStep(onNext: { currentStep = .permissions })
                .tag(OnboardingStep.welcome)

            OnboardingPermissionsStep(onNext: { currentStep = .preferences })
                .tag(OnboardingStep.permissions)

            OnboardingPreferencesStep()
                .tag(OnboardingStep.preferences)
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
        .indexViewStyle(.page(backgroundDisplayMode: .always))
    }
}

#Preview {
    OnboardingFlow()
        .environment(LocationTrackingService())
        .environment(HealthKitService())
        .modelContainer(for: UserProfile.self, inMemory: true)
}
