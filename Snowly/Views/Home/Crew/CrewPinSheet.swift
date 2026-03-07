//
//  CrewPinSheet.swift
//  Snowly
//
//  Compact sheet for composing a pin message with quick-tap chips.
//

import SwiftUI

struct CrewPinSheet: View {
    @Environment(CrewService.self) private var crewService
    @Environment(CrewPinNotificationService.self) private var pinNotificationService
    @Environment(\.dismiss) private var dismiss

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
        VStack(spacing: Spacing.lg) {
            TextField(
                String(localized: "crew_pin_message_placeholder"),
                text: $message
            )
            .textFieldStyle(.roundedBorder)
            .submitLabel(.done)
            .onChange(of: message) { _, newValue in
                if newValue.count > Self.maxLength {
                    message = String(newValue.prefix(Self.maxLength))
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.sm) {
                    ForEach(Self.quickMessages, id: \.self) { text in
                        Button {
                            message = text
                        } label: {
                            Text(text)
                                .font(Typography.subheadlineMedium)
                                .padding(.horizontal, Spacing.md)
                                .padding(.vertical, Spacing.gap)
                                .background(
                                    message == text ? Color.accentColor.opacity(Opacity.muted) : Color.secondary.opacity(Opacity.light),
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

            Button {
                Task { await sendPin() }
            } label: {
                HStack {
                    if isSending {
                        ProgressView()
                            .tint(.white)
                    }
                    Text(String(localized: "crew_pin_confirm"))
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.md)
                .background(
                    message.trimmingCharacters(in: .whitespaces).isEmpty ? Color.gray : Color.accentColor,
                    in: RoundedRectangle(cornerRadius: CornerRadius.medium, style: .continuous)
                )
                .foregroundStyle(.white)
            }
            .disabled(message.trimmingCharacters(in: .whitespaces).isEmpty || isSending)
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.top, Spacing.md)
    }

    private func sendPin() async {
        let trimmed = message.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        isSending = true
        errorMessage = nil

        do {
            pinNotificationService.requestPermissionIfNeeded()
            try await crewService.dropPin(message: trimmed)
            dismiss()
            return
        } catch {
            errorMessage = error.localizedDescription
            isSending = false
        }
    }
}
