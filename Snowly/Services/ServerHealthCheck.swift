//
//  ServerHealthCheck.swift
//  Snowly
//
//  Stateless utility for checking server connectivity.
//  Pure function — no @Observable, no stored state.
//

import Foundation

enum ServerHealthStatus: Sendable {
    case reachable(latencyMs: Int)
    case unreachable(String)
}

enum ServerHealthCheck {
    /// Sends a GET request to `baseURL/api/v1/health` and returns connectivity status.
    static func check(baseURL: URL, timeout: TimeInterval = 5) async -> ServerHealthStatus {
        let healthURL = baseURL.appendingPathComponent("api/v1/health")
        var request = URLRequest(url: healthURL)
        request.httpMethod = "GET"
        request.timeoutInterval = timeout

        let start = ContinuousClock.now

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let elapsed = ContinuousClock.now - start
            let latencyMs = Int(elapsed.components.seconds * 1000
                + elapsed.components.attoseconds / 1_000_000_000_000_000)

            guard let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode) else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                return .unreachable("HTTP \(code)")
            }
            return .reachable(latencyMs: latencyMs)
        } catch let error as URLError where error.code == .timedOut {
            return .unreachable(String(localized: "server_health_timeout"))
        } catch let error as URLError where error.code == .cannotConnectToHost {
            return .unreachable(String(localized: "server_health_cannot_connect"))
        } catch {
            return .unreachable(error.localizedDescription)
        }
    }
}
