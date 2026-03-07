//
//  NowPlayingSheet.swift
//  Snowly
//
//  Apple Music-style Now Playing sheet with artwork, track info,
//  seekable progress bar, playback controls, volume, AirPlay,
//  and playlist browsing.
//

import SwiftUI
import MusicKit

struct NowPlayingSheet: View {
    @Environment(MusicPlayerService.self) private var musicService
    @Environment(\.dismiss) private var dismiss

    @State private var isSeeking = false
    @State private var seekTime: TimeInterval = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                dragIndicator
                    .padding(.top, Spacing.sm)

                if musicService.authorizationStatus == .authorized {
                    authorizedContent
                } else {
                    unauthorizedContent
                }
            }
            .padding(.horizontal, Spacing.xl)
            .task {
                if musicService.authorizationStatus == .notDetermined {
                    await musicService.requestAuthorization()
                }
            }
        }
    }

    // MARK: - Authorized Content

    private var authorizedContent: some View {
        VStack(spacing: 0) {
            Spacer()

            artworkView
                .padding(.horizontal, Spacing.xxxl)

            Spacer()
                .frame(height: 28)

            trackInfoView

            Spacer()
                .frame(height: Spacing.xl)

            progressBar

            Spacer()
                .frame(height: 28)

            playbackControls

            Spacer()
                .frame(height: Spacing.xl)

            VolumeSliderView()
                .frame(height: 32)

            Spacer()
                .frame(height: Spacing.content)

            bottomActions

            Spacer()
                .frame(height: Spacing.lg)
        }
    }

    // MARK: - Unauthorized Content

    private var unauthorizedContent: some View {
        VStack(spacing: Spacing.lg) {
            Spacer()

            Image(systemName: "music.note.house")
                .font(Typography.musicIcon)
                .foregroundStyle(.tertiary)

            Text(String(localized: "music_access_required_title"))
                .font(.title3.weight(.semibold))

            Text(String(localized: "music_access_required_description"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if musicService.authorizationStatus == .denied
                || musicService.authorizationStatus == .restricted
            {
                Button(String(localized: "common_open_settings")) {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(.bordered)
                .padding(.top, Spacing.sm)
            }

            Spacer()
        }
    }

    // MARK: - Subviews

    private var dragIndicator: some View {
        Capsule()
            .fill(.quaternary)
            .frame(width: 36, height: 5)
    }

    @ViewBuilder
    private var artworkView: some View {
        if let artwork = musicService.currentArtwork {
            ArtworkImage(artwork, width: 280, height: 280)
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.large))
                .shadowStyle(.large)
        } else {
            RoundedRectangle(cornerRadius: CornerRadius.large)
                .fill(.quinary)
                .frame(width: 280, height: 280)
                .overlay {
                    Image(systemName: "music.note")
                        .font(Typography.onboardingIcon)
                        .foregroundStyle(.tertiary)
                }
        }
    }

    private var trackInfoView: some View {
        VStack(spacing: Spacing.gap) {
            Text(musicService.currentTitle ?? String(localized: "music_now_playing_not_playing"))
                .font(.title3.weight(.semibold))
                .lineLimit(1)

            Text(musicService.currentArtist ?? "\u{2014}")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    // MARK: - Progress Bar

    private var progressBar: some View {
        let current = isSeeking ? seekTime : musicService.playbackTime
        let total = max(musicService.duration, 1)
        let progress = min(max(current / total, 0), 1)

        return VStack(spacing: Spacing.gap) {
            GeometryReader { geo in
                let width = geo.size.width

                ZStack(alignment: .leading) {
                    // Track background
                    Capsule()
                        .fill(.quaternary)
                        .frame(height: 4)

                    // Filled portion
                    Capsule()
                        .fill(ColorTokens.brandWarmOrange)
                        .frame(width: width * progress, height: 4)

                    // Thumb
                    Circle()
                        .fill(ColorTokens.brandWarmOrange)
                        .frame(width: 12, height: 12)
                        .offset(x: width * progress - 6)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            isSeeking = true
                            let fraction = min(max(value.location.x / width, 0), 1)
                            seekTime = fraction * total
                        }
                        .onEnded { _ in
                            musicService.seekTo(seekTime)
                            isSeeking = false
                        }
                )
            }
            .frame(height: 12)

            // Time labels
            HStack {
                Text(formatTime(current))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()

                Spacer()

                Text("-\(formatTime(max(total - current, 0)))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }

    // MARK: - Playback Controls

    private var playbackControls: some View {
        HStack(spacing: 36) {
            Button {
                Task { await musicService.skipToPrevious() }
            } label: {
                Image(systemName: "backward.fill")
                    .font(.title2)
                    .frame(width: 44, height: 44)
            }
            .disabled(musicService.currentTitle == nil)
            .accessibilityLabel(String(localized: "music_skip_previous"))

            Button {
                Task { await musicService.togglePlayback() }
            } label: {
                Image(systemName: musicService.isPlaying ? "pause.fill" : "play.fill")
                    .font(.largeTitle)
                    .frame(width: 64, height: 64)
                    .background(.quinary, in: Circle())
            }
            .accessibilityLabel(musicService.isPlaying
                ? String(localized: "music_pause")
                : String(localized: "music_play"))

            Button {
                Task { await musicService.skipToNext() }
            } label: {
                Image(systemName: "forward.fill")
                    .font(.title2)
                    .frame(width: 44, height: 44)
            }
            .disabled(musicService.currentTitle == nil)
            .accessibilityLabel(String(localized: "music_skip_next"))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
    }

    // MARK: - Bottom Actions

    private var bottomActions: some View {
        HStack {
            AirPlayRoutePickerView()
                .frame(width: 44, height: 44)

            Spacer()

            NavigationLink {
                PlaylistPickerView()
            } label: {
                Image(systemName: "music.note.list")
                    .font(.title3)
                    .foregroundStyle(ColorTokens.brandWarmOrange)
                    .frame(width: 44, height: 44)
            }

            Spacer()

            Button {
                if let url = URL(string: "music://") {
                    UIApplication.shared.open(url)
                }
            } label: {
                Image(systemName: "arrow.up.forward.app")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Helpers

    private func formatTime(_ seconds: TimeInterval) -> String {
        let totalSeconds = Int(max(seconds, 0))
        let minutes = totalSeconds / 60
        let secs = totalSeconds % 60
        return String(format: "%d:%02d", minutes, secs)
    }
}

#Preview {
    NowPlayingSheet()
        .environment(MusicPlayerService())
}
