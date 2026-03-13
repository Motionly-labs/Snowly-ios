//
//  CrewPinButton.swift
//  Snowly
//
//  Map control button to enter pin-drop mode.
//  Styled to match system MapUserLocationButton / MapPitchToggle.
//

import SwiftUI

struct CrewPinButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "mappin.and.ellipse")
                .font(Typography.bodyMedium)
                .foregroundStyle(Color.accentColor)
                .frame(width: 44, height: 44)
                .snowlyGlass(in: Circle())
        }
        .shadowStyle(.medium)
        .accessibilityLabel(String(localized: "crew_pin_drop_button"))
    }
}
