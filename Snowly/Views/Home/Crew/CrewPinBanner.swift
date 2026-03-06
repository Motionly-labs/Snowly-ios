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
            HStack(spacing: 10) {
                Image(systemName: "mappin.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.orange)

                VStack(alignment: .leading, spacing: 2) {
                    Text(pin.senderDisplayName)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.primary)
                    Text(pin.message)
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
        .accessibilityLabel("\(pin.senderDisplayName): \(pin.message)")
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(String(localized: "crew_pin_banner_dismiss_hint"))
    }
}
