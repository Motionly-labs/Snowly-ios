//
//  CrewPinComposeBar.swift
//  Snowly
//
//  Inline compose bar for dropping a pin at the map crosshair location.
//  Shown at bottom of screen when pin mode is active.
//

import SwiftUI
import CoreLocation

struct CrewPinComposeBar: View {
    let coordinate: CLLocationCoordinate2D?
    let onDismiss: () -> Void

    @Environment(CrewService.self) private var crewService
    @Environment(CrewPinNotificationService.self) private var pinNotificationService

    @State private var message = ""
    @State private var isSending = false
    @State private var errorMessage: String?

    private static let maxLength = 60
    private static let quickMessages = [
        String(localized: "crew_pin_quick_meet_here"),
        String(localized: "crew_pin_quick_caution"),
        String(localized: "crew_pin_quick_food"),
        String(localized: "crew_pin_quick_wait"),
    ]

    var body: some View {
        VStack(spacing: Spacing.gutter) {
            // Quick message chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.sm) {
                    ForEach(Self.quickMessages, id: \.self) { text in
                        Button {
                            message = text
                        } label: {
                            Text(text)
                                .font(Typography.subheadlineMedium)
                                .foregroundStyle(message == text ? Color.accentColor : .primary)
                                .padding(.horizontal, Spacing.md)
                                .padding(.vertical, 7)
                                .background(
                                    message == text
                                        ? Color.accentColor.opacity(Opacity.gentle)
                                        : ColorTokens.surfaceOverlay,
                                    in: Capsule()
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(ColorTokens.error)
            }

            // Message field + action buttons
            HStack(spacing: Spacing.sm) {
                // Cancel
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(Typography.smallSemibold)
                        .foregroundStyle(.secondary)
                        .frame(width: 36, height: 36)
                        .background(ColorTokens.surfaceOverlay, in: Circle())
                }

                // Text field
                TextField(
                    String(localized: "crew_pin_message_placeholder"),
                    text: $message
                )
                .font(.subheadline)
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
                .background(ColorTokens.surfaceOverlay, in: Capsule())
                .submitLabel(.done)
                .onChange(of: message) { _, newValue in
                    if newValue.count > Self.maxLength {
                        message = String(newValue.prefix(Self.maxLength))
                    }
                }

                // Send
                Button {
                    Task { await sendPin() }
                } label: {
                    Group {
                        if isSending {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "paperplane.fill")
                        }
                    }
                    .font(Typography.smallSemibold)
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(
                        canSend ? Color.accentColor : Color.secondary.opacity(Opacity.moderate),
                        in: Circle()
                    )
                }
                .disabled(!canSend || isSending)
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.md)
        .background(
            .ultraThinMaterial,
            in: RoundedRectangle(cornerRadius: CornerRadius.large, style: .continuous)
        )
        .shadowStyle(.topBar)
    }

    private var canSend: Bool {
        !message.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func sendPin() async {
        let trimmed = message.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        isSending = true
        errorMessage = nil

        do {
            pinNotificationService.requestPermissionIfNeeded()
            try await crewService.dropPin(message: trimmed, coordinate: coordinate)
            onDismiss()
        } catch {
            errorMessage = error.localizedDescription
            isSending = false
        }
    }
}
