//
//  DeepLinkHandlerTests.swift
//  SnowlyTests
//

import Testing
import Foundation
@testable import Snowly

struct DeepLinkHandlerTests {

    @Test func parse_universalLink() {
        let url = URL(string: "https://snowly.app/crew/join/ABC123")!

        let result = DeepLinkHandler.parse(url: url)

        if case .crewJoin(let token)? = result {
            #expect(token == "ABC123")
        } else {
            Issue.record("Expected crew join link to parse")
        }
    }

    @Test func parse_customScheme() {
        let url = URL(string: "snowly://crew/join/ABC123")!

        let result = DeepLinkHandler.parse(url: url)

        if case .crewJoin(let token)? = result {
            #expect(token == "ABC123")
        } else {
            Issue.record("Expected custom-scheme join link to parse")
        }
    }

    @Test func inviteToken_acceptsRawToken() {
        #expect(DeepLinkHandler.inviteToken(from: "ABC123") == "ABC123")
    }

    @Test func inviteToken_acceptsUniversalLink() {
        let token = DeepLinkHandler.inviteToken(
            from: "https://snowly.app/crew/join/ABC123"
        )

        #expect(token == "ABC123")
    }

    @Test func inviteToken_rejectsInvalidInput() {
        #expect(DeepLinkHandler.inviteToken(from: "not an invite") == nil)
    }
}
