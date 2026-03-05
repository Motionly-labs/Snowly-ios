//
//  WatchConnectivityService.swift
//  SnowlyWatch
//
//  WCSession delegate for watch-side connectivity with iPhone.
//

import Foundation
import WatchConnectivity

@Observable
@MainActor
final class WatchConnectivityService: NSObject {

    var isPhoneReachable = false
    var phoneTrackingState: String = "idle"
    var onMessageReceived: ((WatchMessage) -> Void)?

    private var session: WCSession?

    override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        let wcSession = WCSession.default
        wcSession.delegate = self
        wcSession.activate()
        session = wcSession
    }

    // MARK: - Sending

    func send(_ message: WatchMessage) {
        guard let session, session.activationState == .activated else { return }

        guard let data = try? JSONEncoder().encode(message) else { return }
        let payload: [String: Any] = [SharedConstants.watchSessionKey: data]

        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil) { [weak self] error in
                print("WatchConnectivity send error: \(error.localizedDescription)")
                self?.transferAsUserInfo(payload: payload)
            }
        } else {
            transferAsUserInfo(payload: payload)
        }
    }

    // MARK: - Private

    private func transferAsUserInfo(payload: [String: Any]) {
        session?.transferUserInfo(payload)
    }

    private func handleReceivedPayload(_ payload: [String: Any]) {
        guard let data = payload[SharedConstants.watchSessionKey] as? Data,
              let message = try? JSONDecoder().decode(WatchMessage.self, from: data) else {
            return
        }

        updateTrackingState(from: message)
        onMessageReceived?(message)
    }

    private func updateTrackingState(from message: WatchMessage) {
        switch message {
        case .trackingStarted:
            phoneTrackingState = "tracking"
        case .trackingPaused:
            phoneTrackingState = "paused"
        case .trackingResumed:
            phoneTrackingState = "tracking"
        case .trackingStopped:
            phoneTrackingState = "idle"
        default:
            break
        }
    }
}

// MARK: - WCSessionDelegate

extension WatchConnectivityService: WCSessionDelegate {

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor in
            isPhoneReachable = session.isReachable
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            isPhoneReachable = session.isReachable
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any]
    ) {
        Task { @MainActor in
            handleReceivedPayload(message)
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveMessageData messageData: Data
    ) {
        let payload = [SharedConstants.watchSessionKey: messageData]
        Task { @MainActor in
            handleReceivedPayload(payload)
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveUserInfo userInfo: [String: Any]
    ) {
        Task { @MainActor in
            handleReceivedPayload(userInfo)
        }
    }
}
