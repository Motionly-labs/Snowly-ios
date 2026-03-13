//
//  VolumeSliderView.swift
//  Snowly
//
//  UIKit bridge for MPVolumeView to show the system volume slider.
//

import SwiftUI
import MediaPlayer

struct VolumeSliderView: UIViewRepresentable {

    func makeUIView(context: Context) -> MPVolumeView {
        let view = MPVolumeView(frame: .zero)
        view.showsVolumeSlider = true
        view.tintColor = UIColor(ColorTokens.secondaryAccent)
        return view
    }

    func updateUIView(_ uiView: MPVolumeView, context: Context) {}
}
