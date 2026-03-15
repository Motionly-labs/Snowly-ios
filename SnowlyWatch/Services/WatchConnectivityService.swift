//
//  WatchConnectivityService.swift
//  SnowlyWatch
//
//  WCSession delegate for watch-side connectivity with iPhone.
//

import Foundation
import WatchConnectivity
import os

struct WatchApplicationContext: Sendable, Equatable {
    let trackingState: String
    let liveData: WatchMessage.LiveTrackingData?
    let unitPreference: UnitSystem?
    let lastCompletedRun: WatchMessage.LastRunData?
}

@Observable
@MainActor
final class WatchConnectivityService: NSObject {
    private static let maxPendingPayloads = 500
    private static let logger = Logger(subsystem: "com.Snowly", category: "WatchConnectivity")

    var isPhoneReachable = false
    var phoneTrackingState: String = "idle"
    var onMessageReceived: ((WatchMessage) -> Void)?
    var onReachabilityChanged: ((Bool) -> Void)?
    var onApplicationContextReceived: ((WatchApplicationContext) -> Void)?

    private var session: WCSession?
    private var pendingPayloads: [[String: Any]] = []
    private(set) var latestApplicationContext: WatchApplicationContext?
    private let encoder = JSONEncoder()

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
        guard let session else { return }

        guard let data = try? encoder.encode(message) else { return }
        let payload: [String: Any] = [SharedConstants.watchSessionKey: data]

        guard session.activationState == .activated else {
            pendingPayloads.append(payload)
            if pendingPayloads.count > Self.maxPendingPayloads {
                let overflow = pendingPayloads.count - Self.maxPendingPayloads
                pendingPayloads.removeFirst(overflow)
                Self.logger.warning("WatchConnectivity dropped \(overflow, privacy: .public) queued payloads")
            }
            return
        }

        sendPayload(payload)
    }

    // MARK: - Private

    private func transferAsUserInfo(payload: [String: Any]) {
        session?.transferUserInfo(payload)
    }

    private func sendPayload(_ payload: [String: Any]) {
        guard let session else { return }
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil) { [weak self] error in
                Self.logger.warning("WatchConnectivity send error: \(error.localizedDescription, privacy: .public)")
                Task { @MainActor [weak self] in
                    self?.transferAsUserInfo(payload: payload)
                }
            }
        } else {
            transferAsUserInfo(payload: payload)
        }
    }

    private func flushPendingPayloadsIfNeeded() {
        guard let session, session.activationState == .activated, !pendingPayloads.isEmpty else { return }
        let queued = pendingPayloads
        pendingPayloads.removeAll()
        queued.forEach { sendPayload($0) }
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

    private func updateReachability(_ reachable: Bool) {
        let didChange = isPhoneReachable != reachable
        isPhoneReachable = reachable
        if didChange {
            onReachabilityChanged?(reachable)
        }
    }

    private func handleApplicationContext(_ context: [String: Any]) {
        guard !context.isEmpty else { return }

        let trackingState = (context[SharedConstants.watchContextTrackingStateKey] as? String) ?? phoneTrackingState
        let liveData = decodeContextValue(
            WatchMessage.LiveTrackingData.self,
            from: context[SharedConstants.watchContextLiveDataKey]
        )
        let unitPreference = decodeContextValue(
            UnitSystem.self,
            from: context[SharedConstants.watchContextUnitPreferenceKey]
        )
        let lastCompletedRun = decodeOptionalContextValue(
            WatchMessage.LastRunData.self,
            from: context[SharedConstants.watchContextLastCompletedRunKey]
        )

        phoneTrackingState = trackingState

        let decoded = WatchApplicationContext(
            trackingState: trackingState,
            liveData: liveData,
            unitPreference: unitPreference,
            lastCompletedRun: lastCompletedRun
        )
        latestApplicationContext = decoded
        onApplicationContextReceived?(decoded)
    }

    private func decodeContextValue<T: Decodable>(
        _ type: T.Type,
        from rawValue: Any?
    ) -> T? {
        guard let data = rawValue as? Data else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func decodeOptionalContextValue<T: Decodable>(
        _ type: T.Type,
        from rawValue: Any?
    ) -> T? {
        guard let data = rawValue as? Data, !data.isEmpty else { return nil }
        return try? JSONDecoder().decode(type, from: data)
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
            updateReachability(session.isReachable)
            flushPendingPayloadsIfNeeded()
            handleApplicationContext(session.receivedApplicationContext)
            if session.isReachable {
                send(.requestStatus)
            }
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            let wasReachable = isPhoneReachable
            updateReachability(session.isReachable)
            if session.isReachable && !wasReachable {
                handleApplicationContext(session.receivedApplicationContext)
                send(.requestStatus)
            }
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        Task { @MainActor in
            handleApplicationContext(applicationContext)
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
