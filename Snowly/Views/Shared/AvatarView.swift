//
//  AvatarView.swift
//  Snowly
//
//  Reusable avatar component. Shows photo if available,
//  otherwise displays initials on a brand gradient background.
//

import SwiftUI

struct AvatarView: View {
    let avatarData: Data?
    let displayName: String
    var size: CGFloat = 48

    var body: some View {
        if let data = avatarData, let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(Circle())
        } else {
            Circle()
                .fill(ColorTokens.brandGradient)
                .frame(width: size, height: size)
                .overlay {
                    Text(initials)
                        .font(.system(size: size * 0.4, weight: .bold))
                        .foregroundStyle(.white)
                }
        }
    }

    private var initials: String {
        let words = displayName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ")
        let letters = words.prefix(2).compactMap(\.first)
        guard !letters.isEmpty else { return "?" }
        return String(letters).uppercased()
    }
}
