//
//  PlaylistPickerView.swift
//  Snowly
//
//  Browseable list of the user's Apple Music playlists.
//  Pushed inside NowPlayingSheet's NavigationStack.
//

import SwiftUI
import MusicKit

struct PlaylistPickerView: View {
    @Environment(MusicPlayerService.self) private var musicService
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private var filteredPlaylists: [Playlist] {
        if searchText.isEmpty {
            return musicService.playlists
        }
        let query = searchText.lowercased()
        return musicService.playlists.filter { playlist in
            playlist.name.lowercased().contains(query)
        }
    }

    var body: some View {
        Group {
            if musicService.isLoadingPlaylists {
                loadingView
            } else if musicService.playlists.isEmpty {
                emptyView
            } else {
                playlistList
            }
        }
        .navigationTitle(String(localized: "music_playlists_nav_title"))
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: String(localized: "music_playlists_search_prompt"))
        .task {
            if musicService.playlists.isEmpty {
                await musicService.loadPlaylists()
            }
        }
    }

    // MARK: - Subviews

    private var loadingView: some View {
        VStack(spacing: Spacing.lg) {
            Spacer()
            ProgressView()
                .controlSize(.large)
            Text(String(localized: "music_playlists_loading"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private var emptyView: some View {
        VStack(spacing: Spacing.md) {
            Spacer()
            Image(systemName: "music.note.list")
                .font(Typography.musicIcon)
                .foregroundStyle(.tertiary)
            Text(String(localized: "music_playlists_empty_title"))
                .font(.title3.weight(.semibold))
            Text(String(localized: "music_playlists_empty_description"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(.horizontal, Spacing.xl)
    }

    private var playlistList: some View {
        List(filteredPlaylists) { playlist in
            Button {
                Task {
                    await musicService.playPlaylist(playlist)
                    dismiss()
                }
            } label: {
                playlistRow(playlist)
            }
            .buttonStyle(.plain)
        }
        .listStyle(.plain)
    }

    private func playlistRow(_ playlist: Playlist) -> some View {
        HStack(spacing: Spacing.md) {
            if let artwork = playlist.artwork {
                ArtworkImage(artwork, width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.small))
            } else {
                RoundedRectangle(cornerRadius: CornerRadius.small)
                    .fill(.quinary)
                    .frame(width: 56, height: 56)
                    .overlay {
                        Image(systemName: "music.note.list")
                            .foregroundStyle(.tertiary)
                    }
            }

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(playlist.name)
                    .font(.body)
                    .lineLimit(1)

                if let description = playlist.standardDescription {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Image(systemName: "play.circle")
                .font(.title2)
                .foregroundStyle(ColorTokens.secondaryAccent)
        }
        .contentShape(Rectangle())
    }
}
