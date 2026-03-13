//
//  MusicPillButton.swift
//  Snowly
//
//  Material-style Music button for MusicKit Now Playing control.
//  Tapping shows an in-app Now Playing sheet with playback controls.
//

import SwiftUI
import MusicKit

struct MusicPillButton: View {
    @Environment(MusicPlayerService.self) private var musicService
    @State private var showingNowPlaying = false

    var body: some View {
        Button {
            showingNowPlaying = true
        } label: {
            Group {
                if musicService.isPlaying {
                    Image(systemName: "waveform")
                        .symbolEffect(.variableColor.iterative)
                } else {
                    Image(systemName: "music.note")
                }
            }
            .font(.body.weight(.semibold))
            .foregroundStyle(.primary)
            .frame(width: 44, height: 44)
            .snowlyGlass(in: Circle())
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showingNowPlaying) {
            NowPlayingSheet()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.hidden)
        }
    }
}
