//
//  CrewMemberAnnotation.swift
//  Snowly
//
//  Map annotation showing a crew member's position and activity.
//

import SwiftUI

struct CrewMemberAnnotation: View {
    let member: MemberLocation

    var body: some View {
        VStack(spacing: Spacing.xxs) {
            Circle()
                .fill(CrewMarkerColor.color(for: member.userId))
                .frame(width: 32, height: 32)
                .overlay {
                    Text(initial)
                        .font(Typography.smallBold)
                        .foregroundStyle(.white)
                }
                .overlay(Circle().stroke(.white, lineWidth: 2))
                .shadowStyle(.subtle)
                .opacity(member.isStale ? Opacity.strong : 1.0)

            Image(systemName: activityIcon)
                .font(.caption2)
                .foregroundStyle(.secondary)

            Text(member.displayName)
                .font(Typography.caption2Semibold)
                .foregroundStyle(.white)
                .padding(.horizontal, Spacing.gap)
                .padding(.vertical, Spacing.xxs)
                .snowlyGlass(in: Capsule())
        }
    }

    private var activityIcon: String {
        switch member.activityType {
        case .skiing:  "figure.skiing.downhill"
        case .onLift:  "cablecar"
        case .idle:    "pause.circle"
        case .unknown: "questionmark.circle"
        }
    }

    private var initial: String {
        String(member.displayName.prefix(1)).uppercased()
    }
}

#Preview {
    CrewMemberAnnotation(member: MemberLocation(
        userId: "preview-1",
        displayName: "Roy",
        hasAvatar: false,
        latitude: 0,
        longitude: 0,
        altitude: 2400,
        speed: 12.5,
        course: 180,
        horizontalAccuracy: 5,
        verticalAccuracy: 9,
        timestamp: .now,
        activityType: .skiing,
        isStale: false
    ))
}
