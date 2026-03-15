//
//  OnboardingFlow.swift
//  Snowly
//
//  Onboarding flow with two paths:
//  - Restore: wait for iCloud sync → main app (returning users)
//  - Fresh: Permissions → Preferences → main app (new users)
//

import SwiftUI
import SwiftData

struct OnboardingFlow: View {
    private enum Step {
        case welcome
        case restore
        case permissions
        case preferences
    }

    @State private var step: Step = .welcome

    var body: some View {
        Group {
            switch step {
            case .welcome:
                OnboardingWelcomeStep(
                    onRestore: { step = .restore },
                    onStartFresh: { step = .permissions }
                )
            case .restore:
                OnboardingRestoreStep(
                    onStartFresh: { step = .permissions }
                )
            case .permissions:
                OnboardingPermissionsStep(onNext: { step = .preferences })
            case .preferences:
                OnboardingPreferencesStep()
            }
        }
        .animation(.easeInOut(duration: 0.3), value: step)
    }
}

#Preview {
    OnboardingFlow()
        .environment(LocationTrackingService())
        .environment(HealthKitService())
        .environment(SyncMonitorService())
        .modelContainer(for: [UserProfile.self, DeviceSettings.self], inMemory: true)
}
