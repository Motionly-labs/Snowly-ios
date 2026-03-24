//
//  SkiDataAPIClient.swift
//  Snowly
//
//  HTTP client for uploading ski session data.
//  Independent from CrewAPIClient — keeps ski data upload self-contained.
//

import Foundation
import os

// MARK: - API Error

enum SkiDataAPIError: LocalizedError {
    case unauthorized
    case httpError(statusCode: Int, message: String?)
    case networkUnavailable
    case decodingFailed(Error)

    var errorDescription: String? {
        switch self {
        case .unauthorized:
            return "Authentication failed. Please try again."
        case .httpError(let code, let msg):
            return "Upload failed (\(code))\(msg.map { ": \($0)" } ?? "")."
        case .networkUnavailable:
            return "Network unavailable. Check your connection and try again."
        case .decodingFailed(let error):
            return "Response error: \(error.localizedDescription)"
        }
    }
}

// MARK: - Upload Payloads

struct SessionUploadPayload: Encodable {
    let id: String
    let startDate: Date
    let endDate: Date
    let totalDistance: Double
    let totalVertical: Double
    let maxSpeed: Double
    let runCount: Int
    let noteTitle: String?
    let noteBody: String?
    let runs: [RunUploadPayload]
}

struct RunUploadPayload: Encodable {
    let id: String
    let startDate: Date
    let endDate: Date
    let distance: Double
    let verticalDrop: Double
    let maxSpeed: Double
    let averageSpeed: Double
    let activityType: String
    let trackPoints: [FilteredTrackPoint]
}

// MARK: - API Client

@Observable
@MainActor
final class SkiDataAPIClient: SkiDataAPIProviding {
    private(set) var baseURL: URL
    private var apiToken: String?
    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    nonisolated private static let logger = Logger(
        subsystem: "com.Snowly",
        category: "SkiDataAPI"
    )

    init(
        baseURL: URL = ServerEnvironment.current.baseURL,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.session = session

        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        self.encoder = enc

        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        self.decoder = dec
    }

    func updateBaseURL(_ url: URL) {
        self.baseURL = url
    }

    func setToken(_ token: String) {
        self.apiToken = token
    }

    // MARK: - Registration

    func register(userId: String, displayName: String, deviceSecret: String) async throws -> ServerRegistrationResult {
        struct Body: Encodable {
            let userId: String
            let displayName: String
            let deviceSecret: String
        }

        let req = try buildRequest(
            method: "POST",
            path: "/users/register",
            body: Body(userId: userId, displayName: displayName, deviceSecret: deviceSecret),
            authenticated: false
        )
        logRequest(req, action: "register")
        let (data, response) = try await performRequest(req)
        try checkStatus(response, data: data)

        do {
            return try decoder.decode(ServerRegistrationResult.self, from: data)
        } catch {
            throw SkiDataAPIError.decodingFailed(error)
        }
    }

    func reauthenticate(userId: String, deviceSecret: String) async throws -> String {
        struct Body: Encodable {
            let userId: String
            let deviceSecret: String
        }
        struct Response: Decodable {
            let apiToken: String
        }

        let req = try buildRequest(
            method: "POST",
            path: "/users/reauthenticate",
            body: Body(userId: userId, deviceSecret: deviceSecret),
            authenticated: false
        )
        logRequest(req, action: "reauthenticate")
        let (data, response) = try await performRequest(req)
        try checkStatus(response, data: data)

        do {
            return try decoder.decode(Response.self, from: data).apiToken
        } catch {
            throw SkiDataAPIError.decodingFailed(error)
        }
    }

    // MARK: - Upload

    func uploadSession(_ payload: SessionUploadPayload, userId: String) async throws {
        let req = try buildRequest(
            method: "POST",
            path: "/snowly/users/\(userId)/sessions",
            body: payload,
            authenticated: true
        )
        logRequest(req, action: "uploadSession")
        let (data, response) = try await performRequest(req)
        try checkStatus(response, data: data)
    }

    func updateProfile(userId: String, displayName: String) async throws -> ServerUserIdentity {
        struct Body: Encodable { let displayName: String }
        let req = try buildRequest(
            method: "PATCH",
            path: "/users/\(userId)",
            body: Body(displayName: displayName),
            authenticated: true
        )
        logRequest(req, action: "updateProfile")
        let (data, response) = try await performRequest(req)
        try checkStatus(response, data: data)

        do {
            return try decoder.decode(ServerUserIdentity.self, from: data)
        } catch {
            throw SkiDataAPIError.decodingFailed(error)
        }
    }

    // MARK: - Private Helpers

    private func buildRequest(
        method: String,
        path: String,
        body: (any Encodable)? = nil,
        authenticated: Bool = true
    ) throws -> URLRequest {
        guard
            let components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: true),
            let url = components.url
        else {
            throw SkiDataAPIError.networkUnavailable
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if authenticated {
            guard let token = apiToken else {
                throw SkiDataAPIError.unauthorized
            }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try encoder.encode(body)
        }

        return request
    }

    private func performRequest(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await session.data(for: request)
        } catch {
            let method = request.httpMethod ?? "UNKNOWN"
            let url = request.url?.absoluteString ?? "<nil>"
            debugConsole("Network error during \(method) \(url): \(String(describing: error))")
            Self.logger.error(
                "Network error during \(method, privacy: .public) \(url, privacy: .public): \(String(describing: error), privacy: .public)"
            )
            throw SkiDataAPIError.networkUnavailable
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SkiDataAPIError.networkUnavailable
        }

        return (data, httpResponse)
    }

    private func checkStatus(_ response: HTTPURLResponse, data: Data) throws {
        let code = response.statusCode
        guard !(200...299).contains(code) else { return }

        struct ServerErrorResponse: Decodable {
            let error: ServerError
            struct ServerError: Decodable {
                let code: String
                let message: String
            }
        }

        let serverMessage = (try? decoder.decode(ServerErrorResponse.self, from: data))?.error.message
        let responseBody = summarizeResponseBody(data)
        let url = response.url?.absoluteString ?? "<nil>"
        debugConsole("HTTP \(code) from \(url). serverMessage=\(serverMessage ?? "<none>") body=\(responseBody)")
        Self.logger.error(
            "HTTP \(code, privacy: .public) from \(url, privacy: .public). serverMessage=\(serverMessage ?? "<none>", privacy: .public) body=\(responseBody, privacy: .public)"
        )

        switch code {
        case 401:
            throw SkiDataAPIError.unauthorized
        default:
            throw SkiDataAPIError.httpError(statusCode: code, message: serverMessage)
        }
    }

    private func logRequest(_ request: URLRequest, action: String) {
        let method = request.httpMethod ?? "UNKNOWN"
        let url = request.url?.absoluteString ?? "<nil>"
        let bodyBytes = request.httpBody?.count ?? 0
        debugConsole("Starting \(action): \(method) \(url) bodyBytes=\(bodyBytes)")
        Self.logger.info(
            "Starting \(action, privacy: .public): \(method, privacy: .public) \(url, privacy: .public) bodyBytes=\(bodyBytes, privacy: .public)"
        )
    }

    private func summarizeResponseBody(_ data: Data) -> String {
        guard !data.isEmpty else { return "<empty>" }
        let text = String(decoding: data, as: UTF8.self)
        if text.count <= 500 {
            return text
        }
        return String(text.prefix(500)) + "...<truncated>"
    }

    private func debugConsole(_ message: String) {
#if DEBUG
        print("[SkiDataAPI] \(message)")
#endif
    }
}
