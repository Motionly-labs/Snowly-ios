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

    @Environment(LaunchRestorationCoordinator.self) private var coordinator
    @State private var step: Step = .welcome

    var body: some View {
        Group {
            switch step {
            case .welcome:
                OnboardingWelcomeStep(
                    coordinatorState: coordinator.state,
                    onRestore: { step = .restore },
                    onStartFresh: {
                        coordinator.completeFreshSetup()
                        step = .permissions
                    }
                )
            case .restore:
                OnboardingRestoreStep(
                    onStartFresh: {
                        coordinator.completeFreshSetup()
                        step = .permissions
                    }
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
        .environment(LaunchRestorationCoordinator(fingerprint: nil))
        .modelContainer(for: [UserProfile.self, DeviceSettings.self], inMemory: true)
}
