//
//  ShareCardView.swift
//  Snowly
//
//  1080x1920 share card layout with avatar, route map,
//  and stats on a dark gradient background.
//
//  Accepts plain values (not SwiftData models) to avoid
//  EXC_BAD_ACCESS when rendered via ImageRenderer.
//

import SwiftUI

struct ShareCardView: View {
    let maxSpeed: Double
    let runCount: Int
    let totalDistance: Double
    let totalVertical: Double
    let duration: TimeInterval
    let startDate: Date
    let resortName: String?
    let unitSystem: UnitSystem
    let avatarData: Data?
    let displayName: String
    let mapImage: UIImage?

    var body: some View {
        ZStack {
            background

            VStack(spacing: 0) {
                Spacer().frame(height: Spacing.section)

                headerSection
                    .padding(.bottom, Spacing.xxl)

                mapSection
                    .padding(.horizontal, Spacing.section)
                    .padding(.bottom, Spacing.xxxl)

                statsGrid
                    .padding(.horizontal, Spacing.section)
                    .padding(.bottom, Spacing.xxl)

                durationSection
                    .padding(.bottom, Spacing.xxxl)

                Spacer()

                footerSection
                    .padding(.bottom, Spacing.section)
            }
        }
        .frame(width: AppConstants.shareCardWidth, height: AppConstants.shareCardHeight)
    }

    // MARK: - Background

    private var background: some View {
        LinearGradient(
            colors: [
                AppConstants.backgroundDark,
                AppConstants.backgroundCard,
                AppConstants.backgroundDark,
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: Spacing.md) {
            AvatarView(avatarData: avatarData, displayName: displayName, size: 72)

            if !displayName.isEmpty {
                Text(displayName)
                    .font(Typography.headingLarge)
                    .foregroundStyle(.white)
            }

            HStack(spacing: Spacing.sm) {
                if let name = resortName {
                    Text(name)
                    Text("\u{00B7}")
                }
                Text(startDate.longDisplay)
            }
            .font(Typography.headingMedium)
            .foregroundStyle(.white.opacity(Opacity.half))
        }
    }

    // MARK: - Map

    private var mapSection: some View {
        Group {
            if let image = mapImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 500)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
            } else {
                RoundedRectangle(cornerRadius: 20)
                    .fill(
                        LinearGradient(
                            colors: [
                                AppConstants.surfaceElevated,
                                AppConstants.backgroundCard,
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(height: 500)
                    .overlay {
                        Image(systemName: "mountain.2.fill")
                            .font(Typography.onboardingIcon)
                            .foregroundStyle(.white.opacity(Opacity.gentle))
                    }
            }
        }
    }

    // MARK: - Stats

    private var statsGrid: some View {
        VStack(spacing: Spacing.xl) {
            HStack(spacing: Spacing.xl) {
                statCard(
                    value: Formatters.speedValue(maxSpeed, unit: unitSystem),
                    unit: Formatters.speedUnit(unitSystem),
                    label: String(localized: "stat_max_speed")
                )
                statCard(
                    value: "\(runCount)",
                    unit: "",
                    label: String(localized: "common_runs")
                )
            }
            HStack(spacing: Spacing.xl) {
                statCard(
                    value: Formatters.distance(totalDistance, unit: unitSystem),
                    unit: "",
                    label: String(localized: "common_distance")
                )
                statCard(
                    value: Formatters.vertical(totalVertical, unit: unitSystem),
                    unit: "",
                    label: String(localized: "common_vertical")
                )
            }
        }
    }

    private func statCard(value: String, unit: String, label: String) -> some View {
        VStack(spacing: Spacing.gap) {
            HStack(alignment: .lastTextBaseline, spacing: Spacing.xs) {
                Text(value)
                    .font(Typography.metricMedium)
                    .foregroundStyle(ColorTokens.brandGradient)
                if !unit.isEmpty {
                    Text(unit)
                        .font(Typography.bodyLabel)
                        .foregroundStyle(.white.opacity(Opacity.half))
                }
            }
            Text(label)
                .font(Typography.captionMedium)
                .foregroundStyle(.white.opacity(Opacity.half))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.content)
        .background(AppConstants.surfaceElevated, in: RoundedRectangle(cornerRadius: CornerRadius.large))
    }

    // MARK: - Duration

    private var durationSection: some View {
        VStack(spacing: Spacing.gap) {
            Text(Formatters.duration(duration))
                .font(Typography.metricLarge)
                .foregroundStyle(ColorTokens.brandGradient)
            Text(String(localized: "common_ski_time"))
                .font(Typography.captionMedium)
                .foregroundStyle(.white.opacity(Opacity.half))
        }
    }

    // MARK: - Footer

    private var footerSection: some View {
        HStack(spacing: Spacing.md) {
            Rectangle()
                .fill(ColorTokens.surfaceDivider)
                .frame(width: 80, height: 1)
            Text(String(localized: "share_card_logged_with"))
                .font(Typography.bodyLabel)
                .foregroundStyle(.white.opacity(Opacity.prominent))
            Rectangle()
                .fill(ColorTokens.surfaceDivider)
                .frame(width: 80, height: 1)
        }
    }
}
