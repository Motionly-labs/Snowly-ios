//
//  SkiDataAPIProviding.swift
//  Snowly
//

import Foundation

struct ServerUserIdentity: Decodable, Sendable, Equatable {
    let userId: String
    let username: String
    let displayName: String
    let tag: String
}

struct ServerRegistrationResult: Decodable, Sendable, Equatable {
    let userId: String
    let username: String
    let displayName: String
    let tag: String
    let apiToken: String
}

@MainActor
protocol SkiDataAPIProviding {
    func updateBaseURL(_ url: URL)
    func setToken(_ token: String)
    func register(userId: String, displayName: String, deviceSecret: String) async throws -> ServerRegistrationResult
    func reauthenticate(userId: String, deviceSecret: String) async throws -> String
    func uploadSession(_ payload: SessionUploadPayload, userId: String) async throws
    func updateProfile(userId: String, displayName: String) async throws -> ServerUserIdentity
}
