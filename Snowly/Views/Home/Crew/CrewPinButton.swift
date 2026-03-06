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
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 44, height: 44)
                .background(.regularMaterial, in: Circle())
        }
        .shadow(color: .black.opacity(0.18), radius: 8, x: 0, y: 4)
        .accessibilityLabel(String(localized: "crew_pin_drop_button"))
    }
}
