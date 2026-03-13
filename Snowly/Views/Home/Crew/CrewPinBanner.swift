//
//  CrewPinBanner.swift
//  Snowly
//
//  Top-sliding in-app banner when a crew pin is received in the foreground.
//

import SwiftUI

struct CrewPinBanner: View {
    let pin: CrewPin
    let onDismiss: () -> Void

    var body: some View {
        Button(action: onDismiss) {
            HStack(spacing: Spacing.gutter) {
                Image(systemName: "mappin.circle.fill")
                    .font(.title2)
                    .foregroundStyle(ColorTokens.warning)

                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(pin.senderDisplayName)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.primary)
                    Text(pin.message)
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
            .snowlyGlass(in: RoundedRectangle(cornerRadius: CornerRadius.large, style: .continuous))
            .shadowStyle(.medium)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, Spacing.lg)
        .transition(.move(edge: .top).combined(with: .opacity))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(pin.senderDisplayName): \(pin.message)")
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(String(localized: "crew_pin_banner_dismiss_hint"))
    }
}
