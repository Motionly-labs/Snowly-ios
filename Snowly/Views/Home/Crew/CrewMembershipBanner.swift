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
            return ColorTokens.success
        case .left:
            return ColorTokens.warning
        }
    }

    var body: some View {
        Button(action: onDismiss) {
            HStack(spacing: Spacing.gutter) {
                Image(systemName: iconName)
                    .font(.title2)
                    .foregroundStyle(iconColor)

                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(event.displayName)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: Spacing.xs)

                Image(systemName: "xmark.circle.fill")
                    .font(.body)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.gutter)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: CornerRadius.large, style: .continuous))
            .shadowStyle(.medium)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, Spacing.lg)
        .transition(.move(edge: .top).combined(with: .opacity))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(event.displayName) \(subtitle)")
        .accessibilityAddTraits(.isButton)
    }
}
