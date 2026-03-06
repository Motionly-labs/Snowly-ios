//
//  CrewPinAnnotation.swift
//  Snowly
//
//  Map annotation for a crew pin — flag-style to distinguish
//  from circular member annotations.
//

import SwiftUI

struct CrewPinAnnotation: View {
    let pin: CrewPin
    var onResend: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: "flag.fill")
                .font(.title3)
                .foregroundStyle(CrewMarkerColor.color(for: pin.senderId))
                .shadow(color: .black.opacity(0.3), radius: 4)

            VStack(spacing: 1) {
                Text(pin.senderDisplayName)
                    .font(.caption2.weight(.bold))

                Text(pin.message)
                    .font(.caption2)
                    .lineLimit(2)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: CornerRadius.small, style: .continuous))
        }
        .contextMenu {
            if let onResend {
                Button {
                    onResend()
                } label: {
                    Label("Resend", systemImage: "arrow.clockwise")
                }
            }

            if let onDelete {
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }
}
