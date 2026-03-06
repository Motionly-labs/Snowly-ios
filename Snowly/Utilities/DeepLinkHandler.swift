//
//  DeepLinkHandler.swift
//  Snowly
//
//  Routes incoming Universal Links and custom scheme URLs
//  to typed actions.
//

import Foundation

enum DeepLinkHandler {

    enum DeepLink {
        case crewJoin(token: String)
    }

    /// Parse a URL into a typed deep link, or nil if unrecognized.
    /// Supports:
    ///   - Universal Link: https://snowly.app/crew/join/{token}
    ///   - Custom scheme:  snowly://crew/join/{token}
    static func parse(url: URL) -> DeepLink? {
        let pathComponents = normalizedRouteComponents(for: url)
        let route = Array(pathComponents.suffix(3))

        guard route.count == 3,
              route[0] == "crew",
              route[1] == "join",
              let token = route.last,
              isValidInviteToken(token)
        else { return nil }

        return .crewJoin(token: token)
    }

    /// Extract an invite token from either a raw token or a full invite link.
    static func inviteToken(from input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if isValidInviteToken(trimmed) {
            return trimmed
        }

        guard let url = URL(string: trimmed),
              case .crewJoin(let token) = parse(url: url)
        else { return nil }

        return token
    }

    private static func normalizedRouteComponents(for url: URL) -> [String] {
        var components = url.pathComponents.filter { $0 != "/" }

        if let scheme = url.scheme?.lowercased(),
           scheme != "http",
           scheme != "https",
           let host = url.host,
           !host.isEmpty {
            components.insert(host, at: 0)
        }

        return components
    }

    /// Validate invite token format before sending to server.
    private static func isValidInviteToken(_ token: String) -> Bool {
        let range = token.range(
            of: "^[a-zA-Z0-9]{6,20}$",
            options: .regularExpression
        )
        return range != nil
    }
}
