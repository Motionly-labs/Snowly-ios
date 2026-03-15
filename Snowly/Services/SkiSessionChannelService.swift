//
//  SkiSessionChannelService.swift
//  Snowly
//
//  Wraps the ski_session:user:<userId> channel on /ski_socket.
//

import Foundation
import os

@Observable
@MainActor
final class SkiSessionChannelService {

    private(set) var isConnected = false

    private var socket: PhoenixSocket?
    private var userId: String = ""

    nonisolated private static let logger = Logger(
        subsystem: "com.Snowly",
        category: "SkiSessionChannelService"
    )

    func connect(userId: String, apiToken: String, serverBaseURL: URL) async {
        self.userId = userId

        var components = URLComponents(url: serverBaseURL, resolvingAgainstBaseURL: false)!
        components.scheme = serverBaseURL.scheme == "https" ? "wss" : "ws"
        components.path = "/ski_socket/websocket"
        components.queryItems = [URLQueryItem(name: "token", value: apiToken)]

        guard let wsURL = components.url else { return }

        let newSocket = PhoenixSocket(url: wsURL)
        socket = newSocket

        _ = newSocket.join(
            topic: "ski_session:user:\(userId)",
            params: [:],
            onJoin: { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.isConnected = true
                    Self.logger.info("SkiSessionChannel joined for user \(userId, privacy: .public)")
                }
            },
            onError: { [weak self] error in
                Task { @MainActor [weak self] in
                    self?.isConnected = false
                    Self.logger.error(
                        "SkiSessionChannel join error: \(String(describing: error), privacy: .public)"
                    )
                }
            },
            onMessage: { _, _ in }
        )

        newSocket.connect()
    }

    func disconnect() {
        socket?.disconnect()
        socket = nil
        isConnected = false
    }

    func uploadSession(_ payload: SessionUploadPayload) async -> Result<String, Error> {
        guard isConnected, let socket, !userId.isEmpty else {
            return .failure(SkiSessionChannelError.notConnected)
        }

        let params = encodePayload(payload)

        do {
            let response = try await socket.push(
                topic: "ski_session:user:\(userId)",
                event: "upload_session",
                payload: params
            )
            if let sessionId = response["sessionId"] as? String {
                return .success(sessionId)
            }
            return .failure(SkiSessionChannelError.invalidResponse)
        } catch {
            return .failure(error)
        }
    }

    // MARK: - Private

    private func encodePayload(_ payload: SessionUploadPayload) -> [String: Any] {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        var dict: [String: Any] = [
            "id": payload.id,
            "startDate": formatter.string(from: payload.startDate),
            "endDate": formatter.string(from: payload.endDate),
            "totalDistance": payload.totalDistance,
            "totalVertical": payload.totalVertical,
            "maxSpeed": payload.maxSpeed,
            "runCount": payload.runCount
        ]

        if let noteTitle = payload.noteTitle { dict["noteTitle"] = noteTitle }
        if let noteBody = payload.noteBody { dict["noteBody"] = noteBody }

        dict["runs"] = payload.runs.map { run -> [String: Any] in
            let runDict: [String: Any] = [
                "id": run.id,
                "startDate": formatter.string(from: run.startDate),
                "endDate": formatter.string(from: run.endDate),
                "distance": run.distance,
                "verticalDrop": run.verticalDrop,
                "maxSpeed": run.maxSpeed,
                "averageSpeed": run.averageSpeed,
                "activityType": run.activityType,
                "trackPoints": run.trackPoints.map { tp -> [String: Any] in
                    [
                        "rawTimestamp": formatter.string(from: tp.rawTimestamp),
                        "latitude": tp.latitude,
                        "longitude": tp.longitude,
                        "altitude": tp.altitude,
                        "estimatedSpeed": tp.estimatedSpeed,
                        "horizontalAccuracy": tp.horizontalAccuracy,
                        "verticalAccuracy": tp.verticalAccuracy,
                        "course": tp.course
                    ]
                }
            ]
            return runDict
        }

        return dict
    }
}

enum SkiSessionChannelError: LocalizedError {
    case notConnected
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .notConnected: return "Channel not connected"
        case .invalidResponse: return "Invalid server response"
        }
    }
}
