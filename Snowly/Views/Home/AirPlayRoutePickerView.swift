//
//  AirPlayRoutePickerView.swift
//  Snowly
//
//  UIKit bridge for AVRoutePickerView to show AirPlay device selection.
//

import SwiftUI
import AVKit

struct AirPlayRoutePickerView: UIViewRepresentable {

    func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.tintColor = UIColor(ColorTokens.secondaryAccent)
        picker.activeTintColor = UIColor(ColorTokens.secondaryAccent)
        return picker
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
