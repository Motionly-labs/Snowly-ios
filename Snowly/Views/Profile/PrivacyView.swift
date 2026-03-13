//
//  PrivacyView.swift
//  Snowly
//
//  Privacy policy display.
//

import SwiftUI

struct PrivacyView: View {
    var body: some View {
        List {
            section(
                title: String(localized: "privacy_section_collect_title"),
                content: String(localized: "privacy_section_collect_content")
            )

            section(
                title: String(localized: "privacy_section_storage_title"),
                content: String(localized: "privacy_section_storage_content")
            )

            section(
                title: String(localized: "privacy_section_sharing_title"),
                content: String(localized: "privacy_section_sharing_content")
            )

            section(
                title: String(localized: "privacy_section_share_cards_title"),
                content: String(localized: "privacy_section_share_cards_content")
            )

            section(
                title: String(localized: "privacy_section_rights_title"),
                content: String(localized: "privacy_section_rights_content")
            )

            section(
                title: String(localized: "privacy_section_background_location_title"),
                content: String(localized: "privacy_section_background_location_content")
            )

            Section {
                Text(String(localized: "privacy_last_updated"))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .navigationTitle(String(localized: "privacy_nav_title"))
    }

    private func section(title: String, content: String) -> some View {
        Section(title) {
            Text(content)
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }
}
