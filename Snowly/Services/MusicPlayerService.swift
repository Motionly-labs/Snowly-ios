//
//  MusicPlayerService.swift
//  Snowly
//
//  MusicKit service layer managing authorization, playback, playlists,
//  and progress tracking for the in-app Apple Music experience.
//

import Foundation
import MusicKit
import Observation
import Combine
import os

@Observable
@MainActor
final class MusicPlayerService {

    // MARK: - Published State

    private(set) var authorizationStatus: MusicAuthorization.Status = .notDetermined
    private(set) var isPlaying = false
    private(set) var currentTitle: String?
    private(set) var currentArtist: String?
    private(set) var currentArtwork: MusicKit.Artwork?
    private(set) var playbackTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    private(set) var playlists: [Playlist] = []
    private(set) var isLoadingPlaylists = false

    // MARK: - Private

    private let isPlaybackSupported: Bool
    private let player: SystemMusicPlayer?
    private var stateObservation: AnyCancellable?
    private var queueObservation: AnyCancellable?
    private var progressTask: Task<Void, Never>?
    private static let logger = Logger(subsystem: "com.Snowly", category: "MusicPlayer")
    private nonisolated static let isPlaybackSupportedOnCurrentRuntime: Bool = {
#if targetEnvironment(simulator)
        false
#else
        true
#endif
    }()

    var isPlaybackAvailable: Bool {
        isPlaybackSupported
    }

    // MARK: - Init

    init() {
        isPlaybackSupported = Self.isPlaybackSupportedOnCurrentRuntime
        authorizationStatus = isPlaybackSupported ? MusicAuthorization.currentStatus : .restricted
        player = isPlaybackSupported ? SystemMusicPlayer.shared : nil
        guard isPlaybackSupported else { return }
        startObservingPlayer()
    }

    // MARK: - Authorization

    func requestAuthorization() async {
        guard isPlaybackSupported else {
            authorizationStatus = .restricted
            return
        }
        authorizationStatus = await MusicAuthorization.request()
    }

    // MARK: - Playback Controls

    func togglePlayback() async {
        guard isPlaybackSupported, let player else { return }
        if isPlaying {
            player.pause()
        } else {
            do {
                try await player.play()
            } catch {
                Self.logger.error("Failed to play: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func skipToNext() async {
        guard isPlaybackSupported, let player else { return }
        do {
            try await player.skipToNextEntry()
        } catch {
            Self.logger.error("Failed to skip to next: \(error.localizedDescription, privacy: .public)")
        }
    }

    func skipToPrevious() async {
        guard isPlaybackSupported, let player else { return }
        do {
            try await player.skipToPreviousEntry()
        } catch {
            Self.logger.error("Failed to skip to previous: \(error.localizedDescription, privacy: .public)")
        }
    }

    func seekTo(_ time: TimeInterval) {
        guard isPlaybackSupported, let player else { return }
        player.playbackTime = time
        playbackTime = time
    }

    // MARK: - Playlists

    func loadPlaylists() async {
        guard isPlaybackSupported else {
            playlists = []
            isLoadingPlaylists = false
            return
        }
        guard authorizationStatus == .authorized else { return }
        isLoadingPlaylists = true

        do {
            var request = MusicLibraryRequest<Playlist>()
            request.sort(by: \.lastPlayedDate, ascending: false)
            let response = try await request.response()
            playlists = response.items.map { $0 }
        } catch {
            playlists = []
        }

        isLoadingPlaylists = false
    }

    func playPlaylist(_ playlist: Playlist) async {
        guard isPlaybackSupported, let player else { return }
        player.queue = [playlist]
        do {
            try await player.play()
        } catch {
            Self.logger.error("Failed to play playlist: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Player Observation

    private func startObservingPlayer() {
        guard isPlaybackSupported, let player else { return }
        // Observe player state changes via Combine → update @Observable properties
        stateObservation = player.state.objectWillChange.receive(on: DispatchQueue.main).sink { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.syncState()
            }
        }

        // Observe queue changes
        queueObservation = player.queue.objectWillChange.receive(on: DispatchQueue.main).sink { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.syncQueue()
            }
        }

        // Initial sync
        syncState()
        syncQueue()
    }

    private func syncState() {
        guard isPlaybackSupported, let player else { return }
        let playing = player.state.playbackStatus == .playing
        isPlaying = playing

        if playing {
            startProgressPolling()
        } else {
            stopProgressPolling()
            // One final sync of playback time when paused
            playbackTime = player.playbackTime
        }
    }

    private func syncQueue() {
        guard isPlaybackSupported, let player else { return }
        let entry = player.queue.currentEntry
        currentTitle = entry?.title
        currentArtist = entry?.subtitle
        currentArtwork = entry?.artwork

        // Attempt to read duration from the current entry's item
        if let item = entry?.item {
            switch item {
            case .song(let song):
                duration = song.duration ?? 0
            default:
                duration = 0
            }
        } else {
            duration = 0
        }

        playbackTime = player.playbackTime
    }

    // MARK: - Progress Polling

    private func startProgressPolling() {
        guard isPlaybackSupported, let player else { return }
        guard progressTask == nil else { return }
        let task = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.playbackTime = player.playbackTime
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
        progressTask = task
    }

    private func stopProgressPolling() {
        progressTask?.cancel()
        progressTask = nil
    }
}
