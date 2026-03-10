//
//  SplashView.swift
//  Snowly
//
//  Launch splash screen shown on every app open.
//  Displays the Snowly logo and slogan with fade-in animation.
//  Auto-transitions to the main content after a brief delay.
//

import SwiftUI

struct SplashView: View {
    @State private var showSlogan = false
    @State private var isFinished = false
    @State private var transitionTask: Task<Void, Never>?

    let onFinished: () -> Void

    var body: some View {
        VStack(spacing: Spacing.xxxl) {
            Spacer()

            // Brand logo
            Image("SnowlyLogo")
                .resizable()
                .renderingMode(.original)
                .scaledToFit()
                .frame(height: 112)

            // App name
            Text("SNOWLY")
                .font(Typography.splashTitle.italic())
                .tracking(4)

            // Slogan — fades in
            VStack(spacing: Spacing.xs) {
                Text(String(localized: "splash_tagline_primary"))
                    .font(Typography.splashSubtitle)
                    .foregroundStyle(.secondary)
            }
            .opacity(showSlogan ? 1 : 0)

            Spacer()
            Spacer()
        }
        .onAppear {
            withAnimation(.easeIn(duration: 0.8).delay(0.3)) {
                showSlogan = true
            }
            // Auto-transition after 2.2 seconds
            transitionTask = Task {
                try? await Task.sleep(for: .seconds(2.2))
                guard !Task.isCancelled, !isFinished else { return }
                isFinished = true
                onFinished()
            }
        }
        .onDisappear {
            transitionTask?.cancel()
        }
    }
}

#Preview {
    SplashView(onFinished: {})
}
