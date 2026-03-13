//
//  CrewEmptyState.swift
//  Snowly
//
//  Compact card shown on the Map page when the user is not in any crew.
//

import SwiftUI

struct CrewEmptyState: View {
    @Environment(CrewService.self) private var crewService
    @State private var crewName = ""
    @State private var showCreateAlert = false
    @State private var isCreating = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: Spacing.gap) {
            HStack(spacing: Spacing.md) {
                Image(systemName: "person.2.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(String(localized: "crew_empty_title"))
                        .font(.subheadline.weight(.semibold))
                    Text(String(localized: "crew_empty_subtitle"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                Button {
                    showCreateAlert = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                }
                .disabled(isCreating)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption2)
                    .foregroundStyle(ColorTokens.error)
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.gutter)
        .snowlyGlass(in: RoundedRectangle(cornerRadius: CornerRadius.medium, style: .continuous))
        .alert(String(localized: "crew_create_title"), isPresented: $showCreateAlert) {
            TextField(String(localized: "crew_name_placeholder"), text: $crewName)
            Button(String(localized: "common_create")) {
                createCrew()
            }
            .disabled(crewName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button(String(localized: "common_cancel"), role: .cancel) {
                crewName = ""
            }
        }
    }

    private func createCrew() {
        let name = crewName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        isCreating = true
        errorMessage = nil

        Task {
            do {
                _ = try await crewService.createCrew(name: name)
                crewName = ""
            } catch {
                errorMessage = error.localizedDescription
            }
            isCreating = false
        }
    }
}
