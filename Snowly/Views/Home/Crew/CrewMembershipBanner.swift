//
//  CrewMembershipBanner.swift
//  Snowly
//
//  Top-sliding in-app banner when a crew member joins or leaves.
//

import SwiftUI

struct CrewMembershipBanner: View {
    let event: CrewMembershipEvent
    let onDismiss: () -> Void

    private var subtitle: String {
        switch event.kind {
        case .joined:
            return "joined the crew."
        case .left:
            return "left the crew."
        }
    }

    private var iconName: String {
        switch event.kind {
        case .joined:
            return "person.crop.circle.badge.plus"
        case .left:
            return "person.crop.circle.badge.minus"
        }
    }

    private var iconColor: Color {
        switch event.kind {
        case .joined:
            return .green
        case .left:
            return .orange
        }
    }

    var body: some View {
        Button(action: onDismiss) {
            HStack(spacing: 10) {
                Image(systemName: iconName)
                    .font(.title2)
                    .foregroundStyle(iconColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text(event.displayName)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                Image(systemName: "xmark.circle.fill")
                    .font(.body)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: CornerRadius.large, style: .continuous))
            .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, Spacing.lg)
        .transition(.move(edge: .top).combined(with: .opacity))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(event.displayName) \(subtitle)")
        .accessibilityAddTraits(.isButton)
    }
}
