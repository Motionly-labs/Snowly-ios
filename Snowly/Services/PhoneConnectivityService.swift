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

@Observable
@MainActor
final class PhoneConnectivityService: NSObject {

    // MARK: - Published state

    private(set) var isWatchReachable = false
    private(set) var isPaired = false

    // MARK: - Callback

    /// Called on the main actor whenever a WatchMessage is received from the Watch.
    private var onMessageReceived: ((WatchMessage) -> Void)?

    /// Register a handler for incoming Watch messages.
    func registerMessageHandler(_ handler: @escaping (WatchMessage) -> Void) {
        onMessageReceived = handler
    }

    // MARK: - Private

    private nonisolated static let logger = Logger(subsystem: "com.Snowly", category: "PhoneConnectivity")

    private var session: WCSession?

    // MARK: - Init

    override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        let wcSession = WCSession.default
        wcSession.delegate = self
        wcSession.activate()
        session = wcSession
    }

    // MARK: - Public API

    /// Encodes and sends a WatchMessage to the Watch.
    /// Uses live sendMessage when reachable; falls back to transferUserInfo.
    func send(_ message: WatchMessage) {
        guard let session, session.activationState == .activated else { return }

        guard let data = try? JSONEncoder().encode(message) else {
            Self.logger.error("Failed to encode WatchMessage")
            return
        }

        let payload: [String: Any] = [SharedConstants.watchSessionKey: data]

        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil) { [weak self] error in
                Self.logger.warning("sendMessage failed, falling back: \(error.localizedDescription)")
                self?.session?.transferUserInfo(payload)
            }
        } else {
            session.transferUserInfo(payload)
        }
    }

    /// Pushes lightweight tracking state to the Watch complication / background context.
    func updateApplicationContext(state: TrackingState, liveData: WatchMessage.LiveTrackingData?) {
        guard let session, session.activationState == .activated else { return }

        var context: [String: Any] = [
            "trackingState": trackingStateString(state)
        ]

        if let data = liveData, let encoded = try? JSONEncoder().encode(data) {
            context["liveData"] = encoded
        }

        do {
            try session.updateApplicationContext(context)
        } catch {
            Self.logger.error("updateApplicationContext failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Private helpers

    private func trackingStateString(_ state: TrackingState) -> String {
        switch state {
        case .tracking: return "tracking"
        case .paused:   return "paused"
        case .idle:     return "idle"
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
            self.isPaired = session.isPaired
            self.isWatchReachable = session.isReachable
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        // Reactivate so the new primary Watch can pair
        session.activate()
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.isWatchReachable = session.isReachable
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
