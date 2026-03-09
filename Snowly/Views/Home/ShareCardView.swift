//
//  ShareCardView.swift
//  Snowly
//
//  1920x1080 landscape share card mirroring the ski day recap composition.
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
    let noteTitle: String?
    let noteBody: String?
    let mapImage: UIImage?

    var body: some View {
        ZStack {
            background
            HStack(spacing: AppConstants.shareCardColumnSpacing) {
                mapPanel
                infoPanel
            }
            .padding(.horizontal, AppConstants.shareCardHorizontalPadding)
            .padding(.vertical, AppConstants.shareCardVerticalPadding)
        }
        .frame(width: AppConstants.shareCardWidth, height: AppConstants.shareCardHeight)
    }

    private var background: some View {
        LinearGradient(
            colors: [AppConstants.backgroundDark, AppConstants.backgroundCard, AppConstants.backgroundDark],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay {
            Circle()
                .fill(ColorTokens.brandWarmOrange.opacity(0.12))
                .frame(width: 360, height: 360)
                .blur(radius: 16)
                .offset(x: 640, y: -240)
        }
    }

    private var mapPanel: some View {
        Group {
            if let image = mapImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                LinearGradient(
                    colors: [AppConstants.surfaceElevated, AppConstants.backgroundCard],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .overlay {
                    Image(systemName: "mountain.2.fill")
                        .font(.system(size: 64, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.35))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay {
            RoundedRectangle(cornerRadius: 24)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        }
    }

    private var infoPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerBlock

            if noteTitle != nil || noteBody != nil {
                noteBlock(title: noteTitle, body: noteBody)
                    .padding(.top, 20)
            }

            Spacer()

            // Max speed — hero stat
            VStack(alignment: .leading, spacing: 8) {
                Text(String(localized: "stat_max_speed").uppercased())
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.45))
                    .tracking(2.5)
                Text("\(Formatters.speedValue(maxSpeed, unit: unitSystem)) \(Formatters.speedUnit(unitSystem))")
                    .font(.system(size: 96, weight: .black, design: .rounded).monospacedDigit())
                    .foregroundStyle(ColorTokens.brandGradient)
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
            }

            Spacer().frame(height: 40)

            // 4-stat band
            HStack(spacing: 0) {
                statBlock(value: "\(runCount)", label: String(localized: "common_runs"))
                statSeparator
                statBlock(
                    value: Formatters.distance(totalDistance, unit: unitSystem),
                    label: String(localized: "common_distance")
                )
                statSeparator
                statBlock(
                    value: Formatters.vertical(totalVertical, unit: unitSystem),
                    label: String(localized: "common_vertical")
                )
                statSeparator
                statBlock(
                    value: Formatters.duration(duration),
                    label: String(localized: "common_ski_time")
                )
            }
            .padding(.vertical, 24)
            .background(AppConstants.surfaceElevated.opacity(0.6), in: RoundedRectangle(cornerRadius: 16))

            Spacer()

            // Brand lockup — bottom right
            HStack {
                Spacer()
                HStack(spacing: 10) {
                    Image("SnowlyLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(height: 26)
                    Text("Snowly")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
        }
        .frame(width: AppConstants.shareCardInfoPanelWidth, alignment: .leading)
    }

    private var headerBlock: some View {
        HStack(spacing: 16) {
            AvatarView(avatarData: avatarData, displayName: displayName, size: 58)
            VStack(alignment: .leading, spacing: 5) {
                if !displayName.isEmpty {
                    Text(displayName)
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                HStack(spacing: 8) {
                    if let resortName {
                        Text(resortName)
                        Text("\u{00B7}")
                    }
                    Text(startDate.longDisplay)
                }
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.55))
            }
        }
    }

    private func noteBlock(title: String?, body: String?) -> some View {
        HStack(spacing: 12) {
            Rectangle()
                .fill(ColorTokens.brandWarmAmber.opacity(0.7))
                .frame(width: 3)
                .clipShape(Capsule())
            VStack(alignment: .leading, spacing: 4) {
                if let title, !title.isEmpty {
                    Text(title)
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(1)
                }
                if let body, !body.isEmpty {
                    Text(body)
                        .font(.system(size: 14, weight: .regular, design: .rounded))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(2)
                }
            }
        }
    }

    private var statSeparator: some View {
        Rectangle()
            .fill(.white.opacity(0.1))
            .frame(width: 1, height: 52)
    }

    private func statBlock(value: String, label: String) -> some View {
        VStack(alignment: .center, spacing: 8) {
            Text(value)
                .font(.system(size: 36, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            Text(label.uppercased())
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.45))
                .tracking(1.5)
        }
        .frame(maxWidth: .infinity)
    }
}
