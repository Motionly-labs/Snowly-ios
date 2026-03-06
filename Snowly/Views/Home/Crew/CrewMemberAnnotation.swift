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
        VStack(spacing: 2) {
            Circle()
                .fill(CrewMarkerColor.color(for: member.userId))
                .frame(width: 32, height: 32)
                .overlay {
                    Text(initial)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                }
                .overlay(Circle().stroke(.white, lineWidth: 2))
                .shadow(color: .black.opacity(0.3), radius: 4)
                .opacity(member.isStale ? 0.6 : 1.0)

            Image(systemName: activityIcon)
                .font(.caption2)
                .foregroundStyle(.secondary)

            Text(member.displayName)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.ultraThinMaterial, in: Capsule())
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
        accuracy: 5,
        timestamp: .now,
        activityType: .skiing,
        isStale: false
    ))
}
