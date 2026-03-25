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
    @Environment(\.modelContext) private var modelContext

    @State private var showingResetConfirmation = false

    private var profile: UserProfile? { profiles.first }

    private var unitSystem: UnitSystem {
        profile?.preferredUnits ?? .metric
    }

    var body: some View {
        List {
            // Avatar + name
            Section {
                VStack(spacing: Spacing.md) {
                    AvatarView(
                        avatarData: profile?.avatarData,
                        displayName: baseDisplayName,
                        size: 72
                    )

                    Text(baseDisplayName)
                        .font(Typography.primaryTitle)

                    Text(memberSinceText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.sm)
            }

            // Season bests
            if let profile {
                Section {
                    bestRow(String(localized: "profile_best_peak_speed"),
                            value: Formatters.speed(profile.seasonBestMaxSpeed, unit: unitSystem),
                            icon: "gauge.with.dots.needle.67percent")
                    bestRow(String(localized: "profile_best_most_vertical"),
                            value: Formatters.vertical(profile.seasonBestVertical, unit: unitSystem),
                            icon: "arrow.down")
                    bestRow(String(localized: "profile_best_longest_distance"),
                            value: Formatters.distance(profile.seasonBestDistance, unit: unitSystem),
                            icon: "point.topleft.down.to.point.bottomright.curvepath")
                } header: {
                    Text(String(localized: "profile_section_season_bests"))
                } footer: {
                    Text(profile.lastSeasonYear)
                }
            }

            // All-time personal bests
            if let profile {
                Section {
                    bestRow(String(localized: "profile_best_peak_speed"),
                            value: Formatters.speed(profile.personalBestMaxSpeed, unit: unitSystem),
                            icon: "gauge.with.dots.needle.67percent")
                    bestRow(String(localized: "profile_best_most_vertical"),
                            value: Formatters.vertical(profile.personalBestVertical, unit: unitSystem),
                            icon: "arrow.down")
                    bestRow(String(localized: "profile_best_longest_distance"),
                            value: Formatters.distance(profile.personalBestDistance, unit: unitSystem),
                            icon: "point.topleft.down.to.point.bottomright.curvepath")
                    Button(role: .destructive) {
                        showingResetConfirmation = true
                    } label: {
                        HStack {
                            Image(systemName: "arrow.counterclockwise")
                                .frame(width: Spacing.xl)
                            Text(String(localized: "profile_reset_personal_bests"))
                        }
                        .foregroundStyle(ColorTokens.brandRed)
                    }
                } header: {
                    Text(String(localized: "profile_section_personal_bests"))
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
        .alert(String(localized: "profile_reset_personal_bests_confirm_title"), isPresented: $showingResetConfirmation) {
            Button(String(localized: "common_cancel"), role: .cancel) {}
            Button(String(localized: "common_reset"), role: .destructive) {
                if let profile {
                    StatsService.resetPersonalBests(for: profile)
                    StatsService.resetSeasonBests(for: profile)
                    try? modelContext.save()
                }
            }
        } message: {
            Text(String(localized: "profile_reset_personal_bests_confirm_message"))
        }
    }

    private func bestRow(_ label: String, value: String, icon: String) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(ColorTokens.secondaryAccent)
                .frame(width: Spacing.xl)
            Text(label)
            Spacer()
            Text(value)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
        }
    }

    private var baseDisplayName: String {
        profile?.resolvedDisplayName ?? String(localized: "profile_default_display_name")
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
