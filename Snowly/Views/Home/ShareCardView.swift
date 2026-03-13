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
            HStack(spacing: 0) {
                mapPanel
                infoPanel
            }
        }
        .frame(width: AppConstants.shareCardWidth, height: AppConstants.shareCardHeight)
        .clipShape(RoundedRectangle(cornerRadius: 64, style: .continuous))
    }

    private var background: some View {
        Color.white.ignoresSafeArea()
    }

    private var mapPanel: some View {
        ZStack {
            Color(hex: "F1F5F9") // slate-100 equivalent
            
            // Map Grid Background (subtle dots)
            GeometryReader { proxy in
                Path { path in
                    let step: CGFloat = 80
                    for y in stride(from: 0, to: proxy.size.height, by: step) {
                        for x in stride(from: 0, to: proxy.size.width, by: step) {
                            path.addEllipse(in: CGRect(x: x, y: y, width: 4, height: 4))
                        }
                    }
                }
                .fill(Color(hex: "A8A2BC").opacity(0.3))
            }
            
            // Subtle Gradient Multiply
            LinearGradient(
                colors: [ColorTokens.primaryAccent.opacity(0.1), Color.clear, ColorTokens.primaryAccent.opacity(0.05)],
                startPoint: .topTrailing,
                endPoint: .bottomLeading
            )
            .blendMode(.multiply)
            
            // Route Map Image
            if let image = mapImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .blendMode(.multiply) // Combine the grey tracks naturally over light background
                    .opacity(0.9)
            }
            
            // Replicate the "Matterhorn, Zermatt" resort pill
            if let resortName = resortName {
                VStack {
                    HStack {
                        Text(resortName)
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundStyle(Color(hex: "1E293B")) // slate-800
                            .padding(.horizontal, 40)
                            .padding(.vertical, 20)
                            .background(
                                Capsule()
                                    .fill(.white.opacity(0.95))
                                    .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
                            )
                        Spacer()
                    }
                    .padding(.top, 64)
                    .padding(.leading, 64)
                    Spacer()
                }
            }
        }
        .frame(width: AppConstants.shareCardWidth - AppConstants.shareCardInfoPanelWidth, height: AppConstants.shareCardHeight)
    }

    private var infoPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerBlock
                .padding(.bottom, 60)

            Spacer()

            // 2x2 Stats Grid (Matches React ShareCard exactly)
            VStack(spacing: 96) {
                HStack(spacing: 48) {
                    statBlock(
                        value: Formatters.speedValue(maxSpeed, unit: unitSystem),
                        unit: Formatters.speedUnit(unitSystem),
                        label: String(localized: "stat_max_speed"),
                        icon: "bolt.fill"
                    )
                    statBlock(
                        value: Formatters.distance(totalDistance, unit: unitSystem).dropLast(3).trimmingCharacters(in: .whitespaces),
                        unit: Formatters.distance(totalDistance, unit: unitSystem).suffix(2).trimmingCharacters(in: .whitespaces),
                        label: String(localized: "common_distance"),
                        icon: "waveform.path.ecg"
                    )
                }
                
                HStack(spacing: 48) {
                    statBlock(
                        value: Formatters.vertical(totalVertical, unit: unitSystem).dropLast(2).trimmingCharacters(in: .whitespaces),
                        unit: Formatters.vertical(totalVertical, unit: unitSystem).suffix(1).trimmingCharacters(in: .whitespaces),
                        label: String(localized: "common_vertical"),
                        icon: "arrow.down.right"
                    )
                    let durationParts = Formatters.duration(duration).components(separatedBy: " ")
                    statBlock(
                        value: durationParts.first ?? "0:00",
                        unit: "h:m",
                        label: String(localized: "common_duration"),
                        icon: "clock.fill"
                    )
                }
            }

            Spacer()
        }
        .padding(.top, 96)
        .padding(.bottom, 96)
        .padding(.horizontal, 96)
        .frame(width: AppConstants.shareCardInfoPanelWidth, height: AppConstants.shareCardHeight, alignment: .leading)
        .background(Color.white)
        // Add subtle divider line on left matching React sharecard
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Color(hex: "F1F5F9"))
                .frame(width: 2)
        }
    }

    private var headerBlock: some View {
        HStack(alignment: .top) {
            HStack(spacing: 32) {
                // Avatar with white border
                AvatarView(avatarData: avatarData, displayName: displayName, size: 128)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.white, lineWidth: 8))
                    .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
                
                VStack(alignment: .leading, spacing: 8) {
                    if !displayName.isEmpty {
                        Text(displayName)
                            .font(.system(size: 48, weight: .heavy, design: .rounded))
                            .foregroundStyle(Color(hex: "0F172A")) // slate-900
                            .lineLimit(1)
                    }
                    Text(startDate.longDisplay)
                        .font(.system(size: 24, weight: .medium, design: .rounded))
                        .foregroundStyle(Color(hex: "64748B")) // slate-500
                        .tracking(1)
                }
            }
            
            Spacer()
            
            // App Logo
            VStack(alignment: .trailing, spacing: 16) {
                Image("SnowlyLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 64, height: 64)
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(Color.white)
                            .shadow(color: .black.opacity(0.05), radius: 2)
                            .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color(hex: "E2E8F0"), lineWidth: 1))
                    )
                
                Text("SNOWLY")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(hex: "94A3B8")) // slate-400
                    .tracking(2.5)
            }
        }
    }

    private func statBlock(value: String, unit: String, label: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(ColorTokens.primaryAccent)
                
                Text(label.uppercased())
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(hex: "94A3B8")) // slate-400
                    .tracking(2.5)
            }
            
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(value)
                    .font(.system(size: 100, weight: .black, design: .rounded).monospacedDigit())
                    .foregroundStyle(Color(hex: "0F172A")) // slate-900
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                
                Text(unit)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(hex: "94A3B8")) // slate-400
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
