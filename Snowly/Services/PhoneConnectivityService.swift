//
//  PhoneConnectivityService.swift
//  Snowly
//
//  Manages WCSession on the iOS side. Sends WatchMessage values to the
//  paired Apple Watch and routes incoming messages to registered handlers.
//

import Foundation
import WatchConnectivity
import Observation
import os

struct WatchConnectivityState: Sendable, Equatable {
    let isPaired: Bool
    let isWatchAppInstalled: Bool
    let isReachable: Bool

    var canCommunicate: Bool {
        isPaired && isWatchAppInstalled
    }
}

@Observable
@MainActor
final class PhoneConnectivityService: NSObject {

    // MARK: - Published state

    private(set) var isWatchReachable = false
    private(set) var isPaired = false
    private(set) var isWatchAppInstalled = false

    // MARK: - Callback

    /// Called on the main actor whenever a WatchMessage is received from the Watch.
    private var onMessageReceived: ((WatchMessage) -> Void)?
    private var onConnectivityStateChanged: ((WatchConnectivityState) -> Void)?

    /// Register a handler for incoming Watch messages.
    func registerMessageHandler(_ handler: @escaping (WatchMessage) -> Void) {
        onMessageReceived = handler
    }

    /// Register a handler for watch connectivity state changes.
    func registerConnectivityStateHandler(_ handler: @escaping (WatchConnectivityState) -> Void) {
        onConnectivityStateChanged = handler
    }

    func currentConnectivityState() -> WatchConnectivityState {
        WatchConnectivityState(
            isPaired: isPaired,
            isWatchAppInstalled: isWatchAppInstalled,
            isReachable: isWatchReachable
        )
    }

    /// Manual state refresh (useful on app foreground to catch pairing changes).
    func refreshWatchState() {
        guard let session else { return }
        handleSessionAvailabilityChange(session)
    }

    // MARK: - Private

    private nonisolated static let logger = Logger(subsystem: "com.Snowly", category: "PhoneConnectivity")
    private nonisolated static let maxPendingPayloads = 500

    private var session: WCSession?
    private var pendingPayloads: [[String: Any]] = []
    private var pendingApplicationContext: [String: Any]?
    private var hasLoggedUnavailableWatchState = false
    private var latestTrackingState: TrackingState = .idle
    private var latestLiveData: WatchMessage.LiveTrackingData?
    private var latestUnitPreference: UnitSystem?
    private var latestLastCompletedRun: WatchMessage.LastRunData?

    // MARK: - Init

    override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        let wcSession = WCSession.default
        session = wcSession
        wcSession.delegate = self
        wcSession.activate()
        // State is read in activationDidCompleteWith once activation finishes.
        // Accessing isPaired/isReachable before that triggers "WCSession has not been activated".
    }

    // MARK: - Public API

    /// Fire-and-forget send for ephemeral live data.
    /// Uses `sendMessage` only — does NOT fall back to `transferUserInfo`.
    /// Prevents persistent queue buildup for data that becomes stale immediately.
    func sendLive(_ message: WatchMessage) {
        guard let session, canCommunicateWithWatch(session), session.isReachable else { return }
        guard let data = try? JSONEncoder().encode(message) else { return }
        let payload: [String: Any] = [SharedConstants.watchSessionKey: data]
        session.sendMessage(payload, replyHandler: nil, errorHandler: nil)
    }

    /// Encodes and sends a WatchMessage to the Watch.
    /// Uses live sendMessage when reachable; falls back to transferUserInfo.
    func send(_ message: WatchMessage) {
        guard let session else { return }
        guard canCommunicateWithWatch(session) else {
            clearPendingStateForUnavailableWatch()
            logUnavailableWatchStateIfNeeded(session)
            return
        }

        guard let data = try? JSONEncoder().encode(message) else {
            Self.logger.error("Failed to encode WatchMessage")
            return
        }

        let payload: [String: Any] = [SharedConstants.watchSessionKey: data]
        if session.activationState != .activated {
            queuePendingPayload(payload)
            return
        }

        sendPayload(payload)
    }

    /// Pushes lightweight tracking state to the Watch complication / background context.
    func updateApplicationContext(state: TrackingState, liveData: WatchMessage.LiveTrackingData?) {
        latestTrackingState = state
        latestLiveData = liveData

        guard let session else { return }
        guard canCommunicateWithWatch(session) else {
            clearPendingStateForUnavailableWatch()
            logUnavailableWatchStateIfNeeded(session)
            return
        }
        pushApplicationContext(using: session)
    }

    /// Updates the latest unit preference sent to the Watch.
    func updateWatchMetadata(unitPreference: UnitSystem) {
        latestUnitPreference = unitPreference

        send(.unitPreference(unitPreference))

        guard let session else { return }
        guard canCommunicateWithWatch(session) else {
            clearPendingStateForUnavailableWatch()
            logUnavailableWatchStateIfNeeded(session)
            return
        }
        pushApplicationContext(using: session)
    }

    /// Updates the last completed skiing run summary sent to the Watch.
    func updateLastCompletedRun(_ lastCompletedRun: WatchMessage.LastRunData?) {
        latestLastCompletedRun = lastCompletedRun

        send(.lastCompletedRun(lastCompletedRun))

        guard let session else { return }
        guard canCommunicateWithWatch(session) else {
            clearPendingStateForUnavailableWatch()
            logUnavailableWatchStateIfNeeded(session)
            return
        }
        pushApplicationContext(using: session)
    }

    // MARK: - Private helpers

    private func trackingStateString(_ state: TrackingState) -> String {
        switch state {
        case .tracking: return "tracking"
        case .paused:   return "paused"
        case .idle:     return "idle"
        }
    }

    private func queuePendingPayload(_ payload: [String: Any]) {
        pendingPayloads.append(payload)
        if pendingPayloads.count > Self.maxPendingPayloads {
            let overflow = pendingPayloads.count - Self.maxPendingPayloads
            pendingPayloads.removeFirst(overflow)
            Self.logger.warning("Dropped \(overflow) pending WC payloads to cap queue size")
        }
    }

    private func canCommunicateWithWatch(_ session: WCSession) -> Bool {
        session.isPaired && session.isWatchAppInstalled
    }

    private func clearPendingStateForUnavailableWatch() {
        pendingPayloads.removeAll()
        pendingApplicationContext = nil
    }

    private func buildApplicationContext() -> [String: Any] {
        var context: [String: Any] = [
            SharedConstants.watchContextTrackingStateKey: trackingStateString(latestTrackingState)
        ]

        if let latestLiveData, let encoded = try? JSONEncoder().encode(latestLiveData) {
            context[SharedConstants.watchContextLiveDataKey] = encoded
        }

        if let latestUnitPreference, let encoded = try? JSONEncoder().encode(latestUnitPreference) {
            context[SharedConstants.watchContextUnitPreferenceKey] = encoded
        }

        if let latestLastCompletedRun,
           let encoded = try? JSONEncoder().encode(latestLastCompletedRun) {
            context[SharedConstants.watchContextLastCompletedRunKey] = encoded
        } else {
            context[SharedConstants.watchContextLastCompletedRunKey] = Data()
        }

        return context
    }

    private func logUnavailableWatchStateIfNeeded(_ session: WCSession) {
        guard !hasLoggedUnavailableWatchState else { return }
        if !session.isPaired {
            Self.logger.debug("Skipping WC payload: watch is not paired")
        } else if !session.isWatchAppInstalled {
            Self.logger.debug("Skipping WC payload: watch app is not installed")
        } else {
            Self.logger.debug("Skipping WC payload: unavailable watch state")
        }
        hasLoggedUnavailableWatchState = true
    }

    private func handleSessionAvailabilityChange(_ session: WCSession) {
        let previous = currentConnectivityState()
        isPaired = session.isPaired
        isWatchReachable = session.isReachable
        isWatchAppInstalled = session.isWatchAppInstalled
        let current = currentConnectivityState()

        if previous != current {
            onConnectivityStateChanged?(current)
        }

        if canCommunicateWithWatch(session) {
            hasLoggedUnavailableWatchState = false
            flushPendingPayloadsIfNeeded()
            flushPendingApplicationContextIfNeeded()
        } else {
            clearPendingStateForUnavailableWatch()
            logUnavailableWatchStateIfNeeded(session)
        }
    }

    private func sendPayload(_ payload: [String: Any]) {
        guard let session else { return }
        guard canCommunicateWithWatch(session) else { return }
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil) { [weak self] error in
                Self.logger.warning("sendMessage failed, falling back: \(error.localizedDescription)")
                self?.session?.transferUserInfo(payload)
            }
        } else {
            session.transferUserInfo(payload)
        }
    }

    private func flushPendingPayloadsIfNeeded() {
        guard let session, canCommunicateWithWatch(session), session.activationState == .activated, !pendingPayloads.isEmpty else {
            return
        }
        let queued = pendingPayloads
        pendingPayloads.removeAll()
        queued.forEach { sendPayload($0) }
    }

    private func flushPendingApplicationContextIfNeeded() {
        guard let session, canCommunicateWithWatch(session), session.activationState == .activated, let context = pendingApplicationContext else {
            return
        }
        do {
            try session.updateApplicationContext(context)
            pendingApplicationContext = nil
        } catch {
            Self.logger.error("flush updateApplicationContext failed: \(error.localizedDescription)")
        }
    }

    private func pushApplicationContext(using session: WCSession) {
        let context = buildApplicationContext()

        if session.activationState != .activated {
            pendingApplicationContext = context
            return
        }

        do {
            try session.updateApplicationContext(context)
            pendingApplicationContext = nil
        } catch {
            pendingApplicationContext = context
            Self.logger.error("updateApplicationContext failed: \(error.localizedDescription)")
        }
    }

    private func handleReceivedPayload(_ payload: [String: Any]) {
        guard let data = payload[SharedConstants.watchSessionKey] as? Data,
              let watchMessage = try? JSONDecoder().decode(WatchMessage.self, from: data) else {
            Self.logger.warning("Received payload missing or undecodable WatchMessage")
            return
        }
        onMessageReceived?(watchMessage)
    }
}

// MARK: - WCSessionDelegate

extension PhoneConnectivityService: WCSessionDelegate {

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        if let error {
            Self.logger.error("WCSession activation failed: \(error.localizedDescription)")
        }
        Task { @MainActor in
            self.handleSessionAvailabilityChange(session)
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        // Reactivate so the new primary Watch can pair
        session.activate()
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.handleSessionAvailabilityChange(session)
        }
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.handleSessionAvailabilityChange(session)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in
            self.handleReceivedPayload(message)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        Task { @MainActor in
            self.handleReceivedPayload(userInfo)
        }
    }
}
