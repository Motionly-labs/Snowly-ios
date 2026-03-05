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
        VStack(spacing: 40) {
            Spacer()

            // App icon / snowflake
            Image(systemName: "snowflake")
                .font(.system(size: 64, weight: .thin))
                .foregroundStyle(Color.accentColor)

            // App name
            Text("SNOWLY")
                .font(.system(size: 48, weight: .black).italic())
                .tracking(4)

            // Slogan — fades in
            VStack(spacing: 4) {
                Text(String(localized: "splash_tagline_primary"))
                    .font(.system(size: 18, weight: .light))
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
