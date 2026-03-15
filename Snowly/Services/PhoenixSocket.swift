//
//  PhoenixSocket.swift
//  Snowly
//
//  Minimal Phoenix WebSocket client using URLSessionWebSocketTask.
//  Wire format: [join_ref, ref, topic, event, payload] JSON array.
//

import Foundation
import os

// MARK: - Protocol

protocol PhoenixSocketProviding: AnyObject {
    var isConnected: Bool { get }
    func connect()
    func disconnect()
    func join(
        topic: String,
        params: [String: Any],
        onJoin: @escaping ([String: Any]) -> Void,
        onError: @escaping ([String: Any]) -> Void,
        onMessage: @escaping (String, [String: Any]) -> Void
    ) -> String
    func push(topic: String, event: String, payload: [String: Any]) async throws -> [String: Any]
}

// MARK: - Errors

enum PhoenixSocketError: Error {
    case notConnected
    case timeout
    case serverError([String: Any])
    case invalidResponse
}

// MARK: - PhoenixSocket

@Observable
@MainActor
final class PhoenixSocket: NSObject, PhoenixSocketProviding {

    private(set) var isConnected = false

    private let url: URL
    private var task: URLSessionWebSocketTask?
    private var session: URLSession?

    private var refCounter: Int = 0
    private var pendingReplies: [String: CheckedContinuation<[String: Any], Error>] = [:]
    private var channelHandlers: [String: ChannelHandler] = [:]
    private var heartbeatTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var reconnectAttempt = 0
    private var shouldReconnect = true

    private static let heartbeatInterval: TimeInterval = 30
    private static let backoffDelays: [TimeInterval] = [1, 2, 4, 8, 30]

    nonisolated private static let logger = Logger(
        subsystem: "com.Snowly",
        category: "PhoenixSocket"
    )

    private struct ChannelHandler {
        let joinRef: String
        let params: [String: Any]
        let onJoin: ([String: Any]) -> Void
        let onError: ([String: Any]) -> Void
        let onMessage: (String, [String: Any]) -> Void
    }

    init(url: URL) {
        self.url = url
    }

    // MARK: - Connection

    func connect() {
        shouldReconnect = true
        reconnectAttempt = 0
        openConnection()
    }

    func disconnect() {
        shouldReconnect = false
        reconnectTask?.cancel()
        reconnectTask = nil
        heartbeatTask?.cancel()
        heartbeatTask = nil
        task?.cancel(with: .normalClosure, reason: nil)
        task = nil
        isConnected = false
    }

    private func openConnection() {
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        self.session = session
        let wsTask = session.webSocketTask(with: url)
        task = wsTask
        wsTask.resume()
        scheduleReceive()
    }

    private func onConnected() {
        isConnected = true
        reconnectAttempt = 0
        startHeartbeat()
        rejoinAllChannels()
    }

    private func onDisconnected() {
        isConnected = false
        heartbeatTask?.cancel()
        heartbeatTask = nil

        // Fail pending replies
        let pending = pendingReplies
        pendingReplies = [:]
        for cont in pending.values {
            cont.resume(throwing: PhoenixSocketError.notConnected)
        }

        guard shouldReconnect else { return }

        reconnectTask = Task { [weak self] in
            guard let self else { return }
            let delay = Self.backoffDelays[min(self.reconnectAttempt, Self.backoffDelays.count - 1)]
            Self.logger.info("Reconnecting in \(delay)s (attempt \(self.reconnectAttempt + 1))")
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self.reconnectAttempt += 1
                self.openConnection()
            }
        }
    }

    // MARK: - Heartbeat

    private func startHeartbeat() {
        heartbeatTask?.cancel()
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Self.heartbeatInterval))
                guard !Task.isCancelled else { return }
                await self?.sendHeartbeat()
            }
        }
    }

    private func sendHeartbeat() async {
        let ref = nextRef()
        let msg: [Any?] = [nil, ref, "phoenix", "heartbeat", [:]]
        _ = try? await sendRaw(msg)
    }

    // MARK: - Channel Join

    func join(
        topic: String,
        params: [String: Any],
        onJoin: @escaping ([String: Any]) -> Void,
        onError: @escaping ([String: Any]) -> Void,
        onMessage: @escaping (String, [String: Any]) -> Void
    ) -> String {
        let joinRef = nextRef()
        let handler = ChannelHandler(
            joinRef: joinRef,
            params: params,
            onJoin: onJoin,
            onError: onError,
            onMessage: onMessage
        )
        channelHandlers[topic] = handler

        if isConnected {
            Task { [weak self] in
                await self?.sendJoin(topic: topic, joinRef: joinRef, params: params, handler: handler)
            }
        }
        return joinRef
    }

    private func rejoinAllChannels() {
        for (topic, handler) in channelHandlers {
            Task { [weak self] in
                await self?.sendJoin(
                    topic: topic,
                    joinRef: handler.joinRef,
                    params: handler.params,
                    handler: handler
                )
            }
        }
    }

    private func sendJoin(
        topic: String,
        joinRef: String,
        params: [String: Any],
        handler: ChannelHandler
    ) async {
        let ref = nextRef()
        let msg: [Any?] = [joinRef, ref, topic, "phx_join", params]
        do {
            let response = try await sendRaw(msg, ref: ref)
            if let status = response["status"] as? String, status == "ok" {
                let resp = response["response"] as? [String: Any] ?? [:]
                handler.onJoin(resp)
            } else {
                let resp = response["response"] as? [String: Any] ?? [:]
                handler.onError(resp)
            }
        } catch {
            handler.onError(["reason": error.localizedDescription])
        }
    }

    // MARK: - Push

    func push(topic: String, event: String, payload: [String: Any]) async throws -> [String: Any] {
        guard isConnected else { throw PhoenixSocketError.notConnected }

        let ref = nextRef()
        let handler = channelHandlers[topic]
        let joinRef = handler?.joinRef
        let msg: [Any?] = [joinRef, ref, topic, event, payload]

        let response = try await sendRaw(msg, ref: ref)
        if let status = response["status"] as? String, status == "ok" {
            return response["response"] as? [String: Any] ?? [:]
        } else {
            let resp = response["response"] as? [String: Any] ?? [:]
            throw PhoenixSocketError.serverError(resp)
        }
    }

    // MARK: - Send

    private func sendRaw(_ message: [Any?], ref: String? = nil) async throws -> [String: Any] {
        guard let task else { throw PhoenixSocketError.notConnected }

        let data = try JSONSerialization.data(withJSONObject: message)
        let wsMsg = URLSessionWebSocketTask.Message.data(data)
        try await task.send(wsMsg)

        guard let ref else { return [:] }

        return try await withCheckedThrowingContinuation { continuation in
            pendingReplies[ref] = continuation

            Task {
                try? await Task.sleep(for: .seconds(10))
                if let cont = self.pendingReplies.removeValue(forKey: ref) {
                    cont.resume(throwing: PhoenixSocketError.timeout)
                }
            }
        }
    }

    // MARK: - Receive

    private func scheduleReceive() {
        task?.receive { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch result {
                case .success(let message):
                    self.handleMessage(message)
                    self.scheduleReceive()
                case .failure:
                    self.onDisconnected()
                }
            }
        }
    }

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        let data: Data
        switch message {
        case .data(let d): data = d
        case .string(let s): data = Data(s.utf8)
        @unknown default: return
        }

        guard
            let json = try? JSONSerialization.jsonObject(with: data),
            let array = json as? [Any?],
            array.count == 5
        else { return }

        let joinRef = array[0] as? String
        let ref = array[1] as? String
        let topic = array[2] as? String ?? ""
        let event = array[3] as? String ?? ""
        let payload = array[4] as? [String: Any] ?? [:]

        _ = joinRef  // suppress unused warning

        if event == "phx_reply", let ref {
            if let cont = pendingReplies.removeValue(forKey: ref) {
                cont.resume(returning: payload)
            }
            return
        }

        if let handler = channelHandlers[topic] {
            handler.onMessage(event, payload)
        }
    }

    // MARK: - Helpers

    private func nextRef() -> String {
        refCounter += 1
        return "\(refCounter)"
    }
}

// MARK: - URLSessionWebSocketDelegate

extension PhoenixSocket: URLSessionWebSocketDelegate {
    nonisolated func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol proto: String?
    ) {
        Task { @MainActor [weak self] in
            self?.onConnected()
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        Task { @MainActor [weak self] in
            self?.onDisconnected()
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard error != nil else { return }
        Task { @MainActor [weak self] in
            self?.onDisconnected()
        }
    }
}
