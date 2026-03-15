//
//  LocationChannelService.swift
//  Snowly
//
//  Wraps the location:crew:<crewId> channel on /socket.
//

import Foundation
import os

struct MemberChannelLocation {
    let userId: String
    let displayName: String
    let latitude: Double
    let longitude: Double
    let altitude: Double
    let speed: Double
    let course: Double
    let accuracy: Double
    let activityType: String?
    let isStale: Bool
}

@Observable
@MainActor
final class LocationChannelService {

    private(set) var isConnected = false
    var onLocationUpdated: ((MemberChannelLocation) -> Void)?
    var onSnapshot: (([MemberChannelLocation]) -> Void)?

    private var socket: PhoenixSocket?
    private var crewId: String = ""

    nonisolated private static let logger = Logger(
        subsystem: "com.Snowly",
        category: "LocationChannelService"
    )

    func connect(crewId: String, memberToken: String, serverBaseURL: URL) async {
        self.crewId = crewId

        var components = URLComponents(url: serverBaseURL, resolvingAgainstBaseURL: false)!
        components.scheme = serverBaseURL.scheme == "https" ? "wss" : "ws"
        components.path = "/socket/websocket"
        components.queryItems = [URLQueryItem(name: "token", value: memberToken)]

        guard let wsURL = components.url else { return }

        let newSocket = PhoenixSocket(url: wsURL)
        socket = newSocket

        _ = newSocket.join(
            topic: "location:crew:\(crewId)",
            params: [:],
            onJoin: { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.isConnected = true
                    Self.logger.info("LocationChannel joined crew \(crewId, privacy: .public)")
                }
            },
            onError: { [weak self] error in
                Task { @MainActor [weak self] in
                    self?.isConnected = false
                    Self.logger.error(
                        "LocationChannel join error: \(String(describing: error), privacy: .public)"
                    )
                }
            },
            onMessage: { [weak self] event, payload in
                Task { @MainActor [weak self] in
                    self?.handleChannelMessage(event: event, payload: payload)
                }
            }
        )

        newSocket.connect()
    }

    func disconnect() {
        socket?.disconnect()
        socket = nil
        isConnected = false
    }

    func sendLocationUpdate(_ location: LocationUpload) async -> Bool {
        guard isConnected, let socket, !crewId.isEmpty else { return false }

        let payload: [String: Any] = [
            "lat": location.latitude,
            "lon": location.longitude,
            "altitude": location.altitude,
            "speed": max(location.speed, 0),
            "heading": max(location.course, 0),
            "accuracy": max(location.horizontalAccuracy, 0),
            "activity": "skiing"
        ]

        do {
            _ = try await socket.push(
                topic: "location:crew:\(crewId)",
                event: "update_location",
                payload: payload
            )
            return true
        } catch {
            Self.logger.error("LocationChannel push failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    // MARK: - Private

    private func handleChannelMessage(event: String, payload: [String: Any]) {
        switch event {
        case "locations_snapshot":
            guard let locations = payload["locations"] as? [[String: Any]] else { return }
            let parsed = locations.compactMap { parseMemberLocation($0) }
            onSnapshot?(parsed)
            parsed.forEach { onLocationUpdated?($0) }

        case "location_updated":
            if let loc = parseMemberLocation(payload) {
                onLocationUpdated?(loc)
            }

        default:
            break
        }
    }

    private func parseMemberLocation(_ dict: [String: Any]) -> MemberChannelLocation? {
        guard
            let userId = dict["userId"] as? String,
            let displayName = dict["displayName"] as? String,
            let lat = dict["latitude"] as? Double,
            let lon = dict["longitude"] as? Double
        else { return nil }

        return MemberChannelLocation(
            userId: userId,
            displayName: displayName,
            latitude: lat,
            longitude: lon,
            altitude: dict["altitude"] as? Double ?? 0,
            speed: dict["speed"] as? Double ?? 0,
            course: dict["course"] as? Double ?? 0,
            accuracy: dict["accuracy"] as? Double ?? 0,
            activityType: dict["activityType"] as? String,
            isStale: dict["isStale"] as? Bool ?? false
        )
    }
}
