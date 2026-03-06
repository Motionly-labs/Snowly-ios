//
//  OnboardingPermissionsStep.swift
//  Snowly
//
//  Step 2: Request permissions with explicit actions.
//

import CoreLocation
import SwiftUI
import UIKit

struct OnboardingPermissionsStep: View {
    @Environment(LocationTrackingService.self) private var locationService
    @Environment(HealthKitService.self) private var healthKitService
    let onNext: () -> Void

    private enum PermissionAction {
        case request
        case openSettings
        case done
    }

    private var locationAction: PermissionAction {
        switch locationService.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            return .done
        case .denied, .restricted:
            return .openSettings
        default:
            return .request
        }
    }

    private var healthAction: PermissionAction {
        healthKitService.isAuthorized ? .done : .request
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
                    color: .blue,
                    action: locationAction,
                    onRequest: { locationService.requestAuthorization() }
                )

                permissionRow(
                    icon: "cloud.sun.fill",
                    title: String(localized: "onboarding_permissions_weather_title"),
                    subtitle: String(localized: "onboarding_permissions_weather_subtitle"),
                    color: .cyan,
                    action: .done,
                    onRequest: {}
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
    }

    // MARK: - Permission Action Row

    private func permissionRow(
        icon: String,
        title: String,
        subtitle: String,
        color: Color,
        action: PermissionAction,
        onRequest: @escaping () -> Void
    ) -> some View {
        HStack(spacing: Spacing.lg) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: Spacing.xxl)

            VStack(alignment: .leading, spacing: 2) {
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
                    .foregroundStyle(.green)
                    .font(.title3)
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

    private func actionTitle(for action: PermissionAction) -> String {
        switch action {
        case .request:
            return String(localized: "common_continue")
        case .openSettings:
            return String(localized: "common_open_settings")
        case .done:
            return String(localized: "common_done")
        }
    }

    private func handleAction(_ action: PermissionAction, onRequest: () -> Void) {
        switch action {
        case .request:
            onRequest()
        case .openSettings:
            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
            UIApplication.shared.open(url)
        case .done:
            break
        }
    }
}
