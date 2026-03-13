//
//  AppLaunchView.swift
//  Snowly
//  Legacy launch wrapper. Kept as a thin passthrough so app startup
//  goes straight from the system launch screen into the real root view.
//

import SwiftUI

struct AppLaunchView: View {
    var body: some View {
        RootView()
    }
}

#Preview {
    AppLaunchView()
}
