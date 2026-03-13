//
//  CrewAPIClient.swift
//  Snowly
//
//  HTTP client for the Crew REST API.
//  Pure network layer — no business logic, no @Observable.
//  Thread-safe via @MainActor (consistent with other services).
//

import Foundation
import os

// MARK: - Server Environment

enum ServerEnvironment {
    case production
    case local

    nonisolated var baseURL: URL {
        switch self {
        case .production:
            return URL(string: "https://api.snowly.app/api/v1")!
        case .local:
            return URL(string: "http://localhost:4000/api/v1")!
        }
    }

    nonisolated static var current: ServerEnvironment {
        #if DEBUG
        return .local
        #else
        return .production
        #endif
    }
}

// MARK: - API Error

enum CrewAPIError: LocalizedError {
    case unauthorized
    case forbidden(String?)
    case crewNotFound
    case conflict(String?)
    case inviteExpired
    case rateLimited
    case httpError(statusCode: Int, message: String?)
    case networkUnavailable
    case decodingFailed(Error)

    var errorDescription: String? {
        switch self {
        case .unauthorized:
            return String(localized: "crew_error_unauthorized")
        case .forbidden(let msg):
            return msg ?? String(localized: "crew_error_forbidden")
        case .crewNotFound:
            return String(localized: "crew_error_not_found")
        case .conflict(let msg):
            return msg ?? String(localized: "crew_error_conflict")
        case .inviteExpired:
            return String(localized: "crew_error_invite_expired")
        case .rateLimited:
            return String(localized: "crew_error_rate_limited")
        case .httpError(let code, let msg):
            return String(localized: "crew_error_http_format \(code) \(msg ?? "")")
        case .networkUnavailable:
            return String(localized: "crew_error_network")
        case .decodingFailed(let error):
            return String(localized: "crew_error_decoding_format \(error.localizedDescription)")
        }
    }
}

// MARK: - Server Error Envelope

private struct ServerErrorResponse: Decodable {
    let error: ServerError

    struct ServerError: Decodable {
        let code: String
        let message: String
    }
}

// MARK: - API Client

@MainActor
final class CrewAPIClient: CrewAPIProviding {
    private(set) var baseURL: URL
    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var memberToken: String?

    nonisolated private static let logger = Logger(
        subsystem: "com.Snowly",
        category: "CrewAPI"
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

    /// Set the member token after creating/joining a crew or Keychain restore.
    func setToken(_ token: String) {
        self.memberToken = token
    }

    /// Switch to a different server's base URL.
    func updateBaseURL(_ url: URL) {
        self.baseURL = url
    }

    // MARK: - Crew CRUD

    func createCrew(
        userId: String,
        displayName: String,
        crewName: String,
        avatarData: Data?
    ) async throws -> CreateCrewResponse {
        struct Body: Encodable {
            let userId: String
            let displayName: String
            let crewName: String
            let avatarData: String?
        }

        let body = Body(
            userId: userId,
            displayName: displayName,
            crewName: crewName,
            avatarData: avatarData?.base64EncodedString()
        )

        let response: CreateCrewResponse = try await post(
            path: "/crews",
            body: body,
            authenticated: false
        )
        memberToken = response.memberToken
        return response
    }

    func fetchCrew(id: String) async throws -> Crew {
        try await get(path: "/crews/\(id)")
    }

    func dissolveCrew(id: String) async throws {
        let _: EmptyResponse = try await request(
            method: "DELETE",
            path: "/crews/\(id)"
        )
    }

    // MARK: - Membership

    func previewInvite(token: String) async throws -> CrewPreview {
        try await get(path: "/crews/join/\(token)")
    }

    func joinCrew(
        token: String,
        userId: String,
        displayName: String,
        avatarData: Data?
    ) async throws -> JoinCrewResponse {
        struct Body: Encodable {
            let userId: String
            let displayName: String
            let avatarData: String?
        }

        let body = Body(
            userId: userId,
            displayName: displayName,
            avatarData: avatarData?.base64EncodedString()
        )

        let response: JoinCrewResponse = try await post(
            path: "/crews/join/\(token)",
            body: body,
            authenticated: false
        )
        memberToken = response.memberToken
        return response
    }

    func leaveCrew(crewId: String) async throws {
        let noBody: EmptyBody? = nil
        let _: EmptyResponse = try await post(
            path: "/crews/\(crewId)/leave",
            body: noBody
        )
    }

    func kickMember(crewId: String, userId: String) async throws {
        let _: EmptyResponse = try await request(
            method: "DELETE",
            path: "/crews/\(crewId)/members/\(userId)"
        )
    }

    // MARK: - Invite

    func regenerateInvite(crewId: String) async throws -> CrewInvite {
        let noBody: EmptyBody? = nil
        return try await post(
            path: "/crews/\(crewId)/invite/regenerate",
            body: noBody
        )
    }

    // MARK: - Location

    func uploadLocation(crewId: String, location: LocationUpload) async throws {
        let _: EmptyResponse = try await request(
            method: "PUT",
            path: "/crews/\(crewId)/location",
            body: location
        )
    }

    func fetchLocations(
        crewId: String,
        since: Date?,
        etag: String?
    ) async throws -> LocationPollResult {
        var queryItems: [URLQueryItem] = []
        if let since {
            queryItems.append(URLQueryItem(
                name: "since",
                value: ISO8601DateFormatter().string(from: since)
            ))
        }

        let urlRequest = try buildRequest(
            method: "GET",
            path: "/crews/\(crewId)/locations",
            queryItems: queryItems.isEmpty ? nil : queryItems
        )
        var req = urlRequest
        if let etag {
            req.setValue("\"\(etag)\"", forHTTPHeaderField: "If-None-Match")
        }

        let (data, response) = try await performRequest(req)
        let httpResponse = response

        // 304 Not Modified
        if httpResponse.statusCode == 304 {
            let interval = pollInterval(from: httpResponse)
            return LocationPollResult(
                locations: nil,
                pins: nil,
                crew: nil,
                membershipVersion: nil,
                etag: etag,
                pollInterval: interval,
                serverTimestamp: nil
            )
        }

        try checkStatus(httpResponse, data: data)

        struct LocationsResponse: Decodable {
            let locations: [MemberLocation]
            let pins: [CrewPin]?
            let crew: Crew?
            let membershipVersion: String?
            let serverTimestamp: Date?
        }

        let decoded = try decoder.decode(LocationsResponse.self, from: data)
        let newEtag = httpResponse.value(forHTTPHeaderField: "ETag")?
            .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        let interval = pollInterval(from: httpResponse)

        return LocationPollResult(
            locations: decoded.locations,
            pins: decoded.pins,
            crew: decoded.crew,
            membershipVersion: decoded.membershipVersion,
            etag: newEtag,
            pollInterval: interval,
            serverTimestamp: decoded.serverTimestamp
        )
    }

    // MARK: - Pins

    func createPin(crewId: String, pin: CrewPinUpload) async throws -> CrewPin {
        try await post(path: "/crews/\(crewId)/pins", body: pin)
    }

    func deletePin(crewId: String, pinId: String) async throws {
        let _: EmptyResponse = try await request(
            method: "DELETE",
            path: "/crews/\(crewId)/pins/\(pinId)"
        )
    }

    // MARK: - Private Helpers

    private struct EmptyBody: Encodable {}
    private struct EmptyResponse: Decodable {}

    private func get<T: Decodable>(path: String) async throws -> T {
        try await request(method: "GET", path: path)
    }

    private func post<T: Decodable, B: Encodable>(
        path: String,
        body: B?,
        authenticated: Bool = true
    ) async throws -> T {
        try await request(
            method: "POST",
            path: path,
            body: body,
            authenticated: authenticated
        )
    }

    private func request<T: Decodable>(
        method: String,
        path: String,
        body: (any Encodable)? = nil,
        authenticated: Bool = true
    ) async throws -> T {
        let req = try buildRequest(
            method: method,
            path: path,
            body: body,
            authenticated: authenticated
        )

        let (data, response) = try await performRequest(req)
        try checkStatus(response, data: data)

        if T.self == EmptyResponse.self {
            // swiftlint:disable:next force_cast
            return EmptyResponse() as! T
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw CrewAPIError.decodingFailed(error)
        }
    }

    private func buildRequest(
        method: String,
        path: String,
        queryItems: [URLQueryItem]? = nil,
        body: (any Encodable)? = nil,
        authenticated: Bool = true
    ) throws -> URLRequest {
        var components = URLComponents(
            url: baseURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: true
        )!
        components.queryItems = queryItems

        guard let url = components.url else {
            throw CrewAPIError.networkUnavailable
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if authenticated {
            guard let token = memberToken else {
                throw CrewAPIError.unauthorized
            }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try encoder.encode(body)
        }

        return request
    }

    private func performRequest(
        _ request: URLRequest
    ) async throws -> (Data, HTTPURLResponse) {
        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await session.data(for: request)
        } catch {
            Self.logger.error("Network error: \(error.localizedDescription, privacy: .public)")
            throw CrewAPIError.networkUnavailable
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw CrewAPIError.networkUnavailable
        }

        return (data, httpResponse)
    }

    private func checkStatus(_ response: HTTPURLResponse, data: Data) throws {
        let code = response.statusCode
        guard !(200...299).contains(code) else { return }

        let serverMessage = (try? decoder.decode(ServerErrorResponse.self, from: data))?.error.message

        switch code {
        case 401:
            throw CrewAPIError.unauthorized
        case 403:
            throw CrewAPIError.forbidden(serverMessage ?? "Forbidden")
        case 404:
            throw CrewAPIError.crewNotFound
        case 409:
            throw CrewAPIError.conflict(serverMessage ?? "Conflict")
        case 410:
            throw CrewAPIError.inviteExpired
        case 422:
            throw CrewAPIError.httpError(statusCode: 422, message: serverMessage ?? "Validation failed")
        case 429:
            throw CrewAPIError.rateLimited
        default:
            throw CrewAPIError.httpError(statusCode: code, message: serverMessage)
        }
    }

    private func pollInterval(from response: HTTPURLResponse) -> TimeInterval {
        if let header = response.value(forHTTPHeaderField: "X-Poll-Interval"),
           let value = TimeInterval(header) {
            return max(3, min(30, value))
        }
        return 5
    }
}
