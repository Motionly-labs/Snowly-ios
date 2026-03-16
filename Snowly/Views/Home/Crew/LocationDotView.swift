//
//  LocationDotView.swift
//  Snowly
//
//  Reusable location dot for map annotations.
//  Used for crew member positions. Accepts any color so the caller
//  controls identity (e.g. CrewMarkerColor for members).
//

import SwiftUI

struct LocationDotView: View {
    let color: Color
    let initial: String
    var size: CGFloat = 32
    var isStale: Bool = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .overlay {
                Text(initial)
                    .font(Typography.smallBold)
                    .foregroundStyle(ColorTokens.locationDotLabel)
            }
            .overlay(Circle().stroke(ColorTokens.mapAnnotationBorder, lineWidth: 2))
            .shadowStyle(.subtle)
            .opacity(isStale ? Opacity.strong : 1.0)
    }
}

#Preview {
    HStack(spacing: 16) {
        LocationDotView(color: .blue, initial: "R")
        LocationDotView(color: .red, initial: "A")
        LocationDotView(color: .green, initial: "M", size: 40)
        LocationDotView(color: .orange, initial: "S", isStale: true)
    }
    .padding()
    .background(Color.black)
}
