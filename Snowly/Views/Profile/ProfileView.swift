//
//  ProfileView.swift
//  Snowly
//
//  User profile. Accessed from Activity screen's top-right button.
//

import SwiftUI
import SwiftData

struct ProfileView: View {
    @Query(sort: \UserProfile.createdAt) private var profiles: [UserProfile]

    private var profile: UserProfile? { profiles.first }

    private var unitSystem: UnitSystem {
        profile?.preferredUnits ?? .metric
    }

    var body: some View {
        List {
            // Avatar + name
            Section {
                VStack(spacing: 12) {
                    AvatarView(
                        avatarData: profile?.avatarData,
                        displayName: displayName,
                        size: 72
                    )

                    Text(displayName)
                        .font(.title2.bold())

                    Text(memberSinceText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }

            // Season bests
            if let profile {
                Section(String(localized: "profile_section_season_bests")) {
                    bestRow(String(localized: "profile_best_top_speed"),
                            value: Formatters.speed(profile.seasonBestMaxSpeed, unit: unitSystem),
                            icon: "gauge.with.dots.needle.67percent")
                    bestRow(String(localized: "profile_best_most_vertical"),
                            value: Formatters.vertical(profile.seasonBestVertical, unit: unitSystem),
                            icon: "arrow.down")
                    bestRow(String(localized: "profile_best_longest_distance"),
                            value: Formatters.distance(profile.seasonBestDistance, unit: unitSystem),
                            icon: "point.topleft.down.to.point.bottomright.curvepath")
                    bestRow(String(localized: "profile_best_most_runs"),
                            value: "\(profile.seasonBestRunCount)",
                            icon: "number")
                }
            }

            // Navigation
            Section {
                NavigationLink(destination: SettingsView()) {
                    Label(String(localized: "profile_nav_settings"), systemImage: "gearshape")
                }
                .accessibilityIdentifier("profile_settings_link")
                NavigationLink(destination: PrivacyView()) {
                    Label(String(localized: "profile_nav_privacy"), systemImage: "lock.shield")
                }
            }

            // Version
            Section {
                HStack {
                    Text(String(localized: "profile_version_label"))
                    Spacer()
                    Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(String(localized: "profile_nav_title"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func bestRow(_ label: String, value: String, icon: String) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(Color.accentColor)
                .frame(width: 24)
            Text(label)
            Spacer()
            Text(value)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
        }
    }

    private var displayName: String {
        guard let profile else { return String(localized: "profile_default_display_name") }
        let trimmed = profile.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? String(localized: "profile_default_display_name") : trimmed
    }

    private var memberSinceText: String {
        let format = String(localized: "profile_member_since_format")
        let value = profile?.createdAt.longDisplay ?? ""
        return String(format: format, locale: Locale.current, value)
    }
}

#Preview {
    NavigationStack {
        ProfileView()
    }
    .environment(HealthKitService())
    .modelContainer(for: UserProfile.self, inMemory: true)
}
