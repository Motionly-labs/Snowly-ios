//
//  SkiDataAPIProviding.swift
//  Snowly
//

import Foundation

@MainActor
protocol SkiDataAPIProviding {
    func updateBaseURL(_ url: URL)
    func setToken(_ token: String)
    func register(userId: String, displayName: String, deviceSecret: String) async throws -> String
    func reauthenticate(userId: String, deviceSecret: String) async throws -> String
    func uploadSession(_ payload: SessionUploadPayload, userId: String) async throws
}
