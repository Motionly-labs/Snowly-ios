//
//  OnboardingRestoreStep.swift
//  Snowly
//
//  Waits for CloudKit to sync down the user's existing data.
//  - Profiles arriving via @Query → success → complete onboarding
//  - Import event completes with empty profiles → not found
//  - 15-second timeout → not found
//

import CoreData
import SwiftData
import SwiftUI

struct OnboardingRestoreStep: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(SyncMonitorService.self) private var syncMonitor
    @Query(sort: \UserProfile.createdAt) private var profiles: [UserProfile]

    let onStartFresh: () -> Void

    private enum Phase { case syncing, restored, notFound }
    @State private var phase: Phase = .syncing

    var body: some View {
        VStack(spacing: Spacing.xxl) {
            Spacer()

            switch phase {
            case .syncing:
                syncingView
            case .restored:
                restoredView
            case .notFound:
                notFoundView
            }

            Spacer()

            if phase == .syncing {
                Button(action: onStartFresh) {
                    Text(String(localized: "onboarding_restore_cta_start_fresh"))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .padding(.bottom, Spacing.xxxl)
            }
        }
        .animation(.easeInOut(duration: 0.4), value: phase)
        .task { await runTimeout() }
        .onChange(of: profiles.count) { _, count in
            guard count > 0, phase == .syncing else { return }
            phase = .restored
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(800))
                completeRestoration()
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: NSPersistentCloudKitContainer.eventChangedNotification
            )
        ) { handleCloudKitEvent($0) }
    }

    // MARK: - Sub-views

    private var syncingView: some View {
        VStack(spacing: Spacing.lg) {
            ProgressView()
                .scaleEffect(1.5)

            Text(String(localized: "onboarding_restore_title"))
                .font(Typography.onboardingTitle)

            Text(String(localized: "onboarding_restore_subtitle"))
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.xxxl)
        }
    }

    private var restoredView: some View {
        VStack(spacing: Spacing.lg) {
            Image(systemName: "checkmark.circle.fill")
                .font(Typography.onboardingIcon)
                .foregroundStyle(ColorTokens.success)

            Text(String(localized: "onboarding_restore_success_title"))
                .font(Typography.onboardingTitle)

            Text(String(localized: "onboarding_restore_success_subtitle"))
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.xxxl)
        }
    }

    private var notFoundView: some View {
        VStack(spacing: Spacing.lg) {
            Image(systemName: "icloud.slash")
                .font(Typography.onboardingIcon)
                .foregroundStyle(.secondary)

            Text(String(localized: "onboarding_restore_not_found_title"))
                .font(Typography.onboardingTitle)

            Text(String(localized: "onboarding_restore_not_found_subtitle"))
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.xxxl)

            Button(action: onStartFresh) {
                Text(String(localized: "onboarding_restore_cta_start_fresh"))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, Spacing.xxl)
            .padding(.top, Spacing.md)
        }
    }

    // MARK: - Logic

    private func runTimeout() async {
        do {
            try await Task.sleep(for: .seconds(15))
            guard phase == .syncing else { return }
            phase = .notFound
        } catch {}
    }

    private func handleCloudKitEvent(_ notification: Notification) {
        guard
            phase == .syncing,
            let event = notification.userInfo?[
                NSPersistentCloudKitContainer.eventNotificationUserInfoKey
            ] as? NSPersistentCloudKitContainer.Event,
            event.type == .import,
            event.endDate != nil
        else { return }

        // Give @Query a moment to reflect newly imported records before concluding no data exists.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            guard phase == .syncing, profiles.isEmpty else { return }
            phase = .notFound
        }
    }

    private func completeRestoration() {
        let descriptor = FetchDescriptor<DeviceSettings>()
        let all = (try? modelContext.fetch(descriptor)) ?? []
        if let settings = all.first {
            settings.hasCompletedOnboarding = true
        } else {
            modelContext.insert(DeviceSettings(hasCompletedOnboarding: true))
        }
        try? modelContext.save()
    }
}
