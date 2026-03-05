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
                Spacer().frame(height: 48)

                headerSection
                    .padding(.bottom, 32)

                mapSection
                    .padding(.horizontal, 48)
                    .padding(.bottom, 40)

                statsGrid
                    .padding(.horizontal, 48)
                    .padding(.bottom, 32)

                durationSection
                    .padding(.bottom, 40)

                Spacer()

                footerSection
                    .padding(.bottom, 48)
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
        VStack(spacing: 12) {
            AvatarView(avatarData: avatarData, displayName: displayName, size: 72)

            if !displayName.isEmpty {
                Text(displayName)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.white)
            }

            HStack(spacing: 8) {
                if let name = resortName {
                    Text(name)
                    Text("\u{00B7}")
                }
                Text(startDate.longDisplay)
            }
            .font(.system(size: 22))
            .foregroundStyle(.white.opacity(0.5))
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
                            .font(.system(size: 60))
                            .foregroundStyle(.white.opacity(0.15))
                    }
            }
        }
    }

    // MARK: - Stats

    private var statsGrid: some View {
        VStack(spacing: 24) {
            HStack(spacing: 24) {
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
            HStack(spacing: 24) {
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
        VStack(spacing: 6) {
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundStyle(ColorTokens.brandGradient)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            Text(label)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(AppConstants.surfaceElevated, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Duration

    private var durationSection: some View {
        VStack(spacing: 6) {
            Text(Formatters.duration(duration))
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .foregroundStyle(ColorTokens.brandGradient)
            Text(String(localized: "common_ski_time"))
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
        }
    }

    // MARK: - Footer

    private var footerSection: some View {
        HStack(spacing: 12) {
            Rectangle()
                .fill(.white.opacity(0.15))
                .frame(width: 80, height: 1)
            Text(String(localized: "share_card_logged_with"))
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.white.opacity(0.4))
            Rectangle()
                .fill(.white.opacity(0.15))
                .frame(width: 80, height: 1)
        }
    }
}
