//
//  OnboardingPermissionsStep.swift
//  Snowly
//
//  Step 2: Request permissions with explicit actions.
//

import CoreLocation
import SwiftUI
import UIKit

enum OnboardingPermissionAction: Equatable {
    case request
    case openSettings
    case done
    case unavailable
}

enum OnboardingPermissionResolver {
    static func trackingLocationAction(
        for status: CLAuthorizationStatus
    ) -> OnboardingPermissionAction {
        switch status {
        case .authorizedAlways:
            return .done
        case .authorizedWhenInUse, .notDetermined:
            return .request
        case .denied, .restricted:
            return .openSettings
        @unknown default:
            return .request
        }
    }

    static func weatherAction(
        for status: CLAuthorizationStatus
    ) -> OnboardingPermissionAction {
        switch status {
        case .authorizedAlways, .authorizedWhenInUse:
            return .done
        case .denied, .restricted:
            return .openSettings
        case .notDetermined:
            return .request
        @unknown default:
            return .request
        }
    }

    static func healthAction(
        for status: HealthKitAuthorizationState
    ) -> OnboardingPermissionAction {
        switch status {
        case .authorized:
            return .done
        case .denied:
            return .openSettings
        case .notDetermined:
            return .request
        case .unavailable:
            return .unavailable
        }
    }
}

struct OnboardingPermissionsStep: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(LocationTrackingService.self) private var locationService
    @Environment(HealthKitService.self) private var healthKitService
    let onNext: () -> Void

    private var locationAction: OnboardingPermissionAction {
        OnboardingPermissionResolver.trackingLocationAction(
            for: locationService.authorizationStatus
        )
    }

    private var weatherAction: OnboardingPermissionAction {
        OnboardingPermissionResolver.weatherAction(
            for: locationService.authorizationStatus
        )
    }

    private var healthAction: OnboardingPermissionAction {
        OnboardingPermissionResolver.healthAction(
            for: healthKitService.authorizationState
        )
    }

    var body: some View {
        VStack(spacing: Spacing.xxl) {
            Spacer()

            Image(systemName: "lock.shield.fill")
                .font(Typography.onboardingIcon)
                .foregroundStyle(Color.accentColor)

            Text(String(localized: "onboarding_permissions_title"))
                .font(Typography.onboardingTitle)

            Text(String(localized: "onboarding_permissions_subtitle"))
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.xxxl)

            // Permission actions
            VStack(spacing: Spacing.md) {
                permissionRow(
                    icon: "location.fill",
                    title: String(localized: "onboarding_permissions_location_title"),
                    subtitle: String(localized: "onboarding_permissions_location_subtitle"),
                    color: ColorTokens.info,
                    action: locationAction,
                    onRequest: { locationService.requestAuthorization() }
                )

                permissionRow(
                    icon: "cloud.sun.fill",
                    title: String(localized: "onboarding_permissions_weather_title"),
                    subtitle: String(localized: "onboarding_permissions_weather_subtitle"),
                    color: ColorTokens.info,
                    action: weatherAction,
                    onRequest: { locationService.requestAuthorization() }
                )

                permissionRow(
                    icon: "heart.fill",
                    title: String(localized: "onboarding_permissions_health_title"),
                    subtitle: String(localized: "onboarding_permissions_health_subtitle"),
                    color: .red,
                    action: healthAction,
                    onRequest: { Task { await healthKitService.requestAuthorization() } }
                )

            }
            .padding(.horizontal, Spacing.xxl)

            // iCloud sync note (Option C: document the limitation)
            HStack(spacing: Spacing.sm) {
                Image(systemName: "icloud")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(String(localized: "onboarding.icloud_sync_note"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
            }
            .padding(.horizontal, Spacing.xxl)

            Spacer()

            Button(action: onNext) {
                Text(String(localized: "common_continue"))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, Spacing.xxl)
            .padding(.bottom, Spacing.xxxl)
        }
        .onAppear {
            refreshPermissionStates()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            refreshPermissionStates()
        }
    }

    // MARK: - Permission Action Row

    private func permissionRow(
        icon: String,
        title: String,
        subtitle: String,
        color: Color,
        action: OnboardingPermissionAction,
        onRequest: @escaping () -> Void
    ) -> some View {
        HStack(spacing: Spacing.lg) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: Spacing.xxl)

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            if action == .done {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(ColorTokens.success)
                    .font(.title3)
            } else if action == .unavailable {
                Text(actionTitle(for: action))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.sm)
                    .background(.white.opacity(0.12), in: Capsule())
            } else {
                if action == .openSettings {
                    Button(actionTitle(for: action)) {
                        handleAction(action, onRequest: onRequest)
                    }
                    .buttonStyle(.bordered)
                    .tint(color)
                } else {
                    Button(actionTitle(for: action)) {
                        handleAction(action, onRequest: onRequest)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(color)
                }
            }
        }
        .padding(Spacing.lg)
        .background(.quinary, in: RoundedRectangle(cornerRadius: CornerRadius.medium))
    }

    private func actionTitle(for action: OnboardingPermissionAction) -> String {
        switch action {
        case .request:
            return String(localized: "common_continue")
        case .openSettings:
            return String(localized: "common_open_settings")
        case .done:
            return String(localized: "common_done")
        case .unavailable:
            return String(localized: "common_unavailable")
        }
    }

    private func handleAction(_ action: OnboardingPermissionAction, onRequest: () -> Void) {
        switch action {
        case .request:
            onRequest()
        case .openSettings:
            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
            UIApplication.shared.open(url)
        case .done, .unavailable:
            break
        }
    }

    private func refreshPermissionStates() {
        locationService.refreshAuthorizationStatus()
        healthKitService.refreshAuthorizationStatus()
    }
}
