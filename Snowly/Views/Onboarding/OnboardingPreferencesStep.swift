//
//  OnboardingPreferencesStep.swift
//  Snowly
//
//  Step 3: Set name and unit preferences.
//

import SwiftUI
import SwiftData
import PhotosUI

struct OnboardingPreferencesStep: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \UserProfile.createdAt) private var profiles: [UserProfile]

    @State private var displayName = ""
    @State private var unitSystem: UnitSystem = .metric
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var avatarData: Data?

    var body: some View {
        VStack(spacing: Spacing.xxl) {
            Spacer()

            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                AvatarView(
                    avatarData: avatarData,
                    displayName: displayName,
                    size: 80
                )
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.white, Color.accentColor)
                }
            }
            .buttonStyle(.plain)
            .onChange(of: selectedPhoto) { _, newItem in
                Task { await loadAvatar(from: newItem) }
            }

            Text(String(localized: "onboarding_preferences_title"))
                .font(Typography.onboardingTitle)

            Form {
                TextField(String(localized: "onboarding_preferences_name_placeholder"), text: $displayName)

                Picker(String(localized: "onboarding_preferences_units_title"), selection: $unitSystem) {
                    Text(String(localized: "units_metric_short")).tag(UnitSystem.metric)
                    Text(String(localized: "units_imperial_short")).tag(UnitSystem.imperial)
                }
            }
            .frame(maxHeight: 150)

            Spacer()

            Button(action: completeOnboarding) {
                Text(String(localized: "onboarding_preferences_cta_start_day"))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .padding(.horizontal, Spacing.xxl)
            .padding(.bottom, Spacing.xxxl)
        }
    }

    private func loadAvatar(from item: PhotosPickerItem?) async {
        guard let item,
              let data = try? await item.loadTransferable(type: Data.self),
              let original = UIImage(data: data) else {
            return
        }
        avatarData = compressAvatar(original)
    }

    private func compressAvatar(_ image: UIImage) -> Data? {
        let maxDimension: CGFloat = 512
        let size = image.size
        let scale: CGFloat
        if max(size.width, size.height) > maxDimension {
            scale = maxDimension / max(size.width, size.height)
        } else {
            scale = 1.0
        }

        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
        return resized.jpegData(compressionQuality: 0.7)
    }

    private func completeOnboarding() {
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)

        if let profile = profiles.first {
            profile.updateDisplayName(trimmedName)
            profile.preferredUnits = unitSystem
            profile.avatarData = avatarData

            for duplicate in profiles.dropFirst() {
                modelContext.delete(duplicate)
            }
        } else {
            let profile = UserProfile(
                displayName: trimmedName,
                preferredUnits: unitSystem,
                avatarData: avatarData
            )
            modelContext.insert(profile)
        }

        // Mark onboarding complete in local DeviceSettings
        let settingsDescriptor = FetchDescriptor<DeviceSettings>()
        let existingSettings = (try? modelContext.fetch(settingsDescriptor)) ?? []

        if let settings = existingSettings.first {
            settings.hasCompletedOnboarding = true
        } else {
            modelContext.insert(DeviceSettings(hasCompletedOnboarding: true))
        }

        // Persist onboarding completion immediately to avoid a relaunch race.
        try? modelContext.save()

        // Write Keychain fingerprint so the app can detect returning users after reinstall.
        if let profileId = profiles.first?.id ?? (try? modelContext.fetch(FetchDescriptor<UserProfile>()))?.first?.id {
            try? UserIdentityKeychainService.save(
                UserIdentityFingerprint(profileId: profileId, createdAt: Date())
            )
        }
    }
}
