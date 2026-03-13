//
//  ServerManagementView.swift
//  Snowly
//
//  Manage backend server profiles: add, edit, delete, health check,
//  and select the active server for API requests.
//

import SwiftUI
import SwiftData

struct ServerManagementView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(CrewService.self) private var crewService
    @Query(sort: \ServerProfile.createdAt) private var servers: [ServerProfile]

    @State private var editingServer: ServerProfile?
    @State private var showingAddSheet = false
    @State private var healthStatuses: [UUID: HealthCheckState] = [:]
    @State private var serverToDelete: ServerProfile?
    @State private var showingDeleteConfirmation = false

    var body: some View {
        List {
            Section {
                ForEach(servers) { server in
                    serverRow(server)
                        .contentShape(Rectangle())
                        .onTapGesture { selectServer(server) }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            if !server.isDefault {
                                Button(role: .destructive) {
                                    serverToDelete = server
                                    showingDeleteConfirmation = true
                                } label: {
                                    Label(String(localized: "server_action_delete"), systemImage: "trash")
                                }
                            }

                            Button {
                                editingServer = server
                            } label: {
                                Label(String(localized: "server_action_edit"), systemImage: "pencil")
                            }
                            .tint(ColorTokens.info)
                        }
                }
            } header: {
                Label(String(localized: "server_section_servers"), systemImage: "server.rack")
            } footer: {
                Text(String(localized: "server_section_footer"))
            }
        }
        .scrollContentBackground(.hidden)
        .background(
            LinearGradient(
                colors: [
                    Color(uiColor: .systemGroupedBackground),
                    Color(uiColor: .secondarySystemGroupedBackground)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
        .navigationTitle(String(localized: "server_nav_title"))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAddSheet = true
                } label: {
                    Image(systemName: "plus")
                }
            }

            ToolbarItem(placement: .secondaryAction) {
                Button {
                    checkAllServers()
                } label: {
                    Label(String(localized: "server_check_all"), systemImage: "arrow.trianglehead.2.clockwise")
                }
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            ServerEditSheet(mode: .add)
        }
        .sheet(item: $editingServer) { server in
            ServerEditSheet(mode: .edit(server))
        }
        .confirmationDialog(
            String(localized: "server_delete_title"),
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button(String(localized: "server_delete_confirm"), role: .destructive) {
                if let server = serverToDelete {
                    deleteServer(server)
                }
            }
            Button(String(localized: "common_cancel"), role: .cancel) {
                serverToDelete = nil
            }
        } message: {
            Text(String(localized: "server_delete_message"))
        }
        .onAppear {
            ensureDefaultServerExists()
            checkActiveServerHealth()
        }
    }

    // MARK: - Row

    private func serverRow(_ server: ServerProfile) -> some View {
        HStack(spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack(spacing: Spacing.sm) {
                    Text(server.alias)
                        .font(.headline)

                    if server.isDefault {
                        Text(String(localized: "server_badge_default"))
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, Spacing.gap)
                            .padding(.vertical, Spacing.xxs)
                            .snowlyGlass(in: Capsule())
                    }
                }

                Text(server.urlString)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if let status = healthStatuses[server.id] {
                    healthLabel(status)
                }
            }

            Spacer()

            // Health check button
            Button {
                checkHealth(for: server)
            } label: {
                healthIndicator(for: server.id)
            }
            .buttonStyle(.plain)

            // Active indicator
            if server.isActive {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(ColorTokens.success)
                    .font(.title3)
            }
        }
        .padding(.vertical, Spacing.xs)
    }

    // MARK: - Health Indicators

    private func healthIndicator(for serverId: UUID) -> some View {
        Group {
            switch healthStatuses[serverId] {
            case .checking:
                ProgressView()
                    .controlSize(.small)
            case .reachable:
                Image(systemName: "circle.fill")
                    .foregroundStyle(ColorTokens.success)
                    .font(.caption)
            case .unreachable:
                Image(systemName: "circle.fill")
                    .foregroundStyle(ColorTokens.error)
                    .font(.caption)
            case nil, .idle:
                Image(systemName: "circle")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        }
    }

    private func healthLabel(_ status: HealthCheckState) -> some View {
        Group {
            switch status {
            case .idle:
                EmptyView()
            case .checking:
                Text(String(localized: "server_health_checking"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            case .reachable(let latencyMs):
                Text(String(localized: "server_health_reachable \(latencyMs)"))
                    .font(.caption2)
                    .foregroundStyle(ColorTokens.success)
            case .unreachable(let reason):
                Text(reason)
                    .font(.caption2)
                    .foregroundStyle(ColorTokens.error)
                    .lineLimit(1)
            }
        }
    }

    // MARK: - Actions

    private func selectServer(_ server: ServerProfile) {
        for s in servers where s.isActive {
            s.isActive = false
        }
        server.isActive = true

        if let apiBaseURL = server.apiBaseURL {
            crewService.updateServerBaseURL(apiBaseURL)
        }
    }

    private func deleteServer(_ server: ServerProfile) {
        guard !server.isDefault else { return }

        if server.isActive {
            if let defaultServer = servers.first(where: \.isDefault) {
                selectServer(defaultServer)
            }
        }
        modelContext.delete(server)
        serverToDelete = nil
    }

    private func checkHealth(for server: ServerProfile) {
        guard let url = server.url else {
            healthStatuses[server.id] = .unreachable(
                String(localized: "server_health_invalid_url")
            )
            return
        }
        healthStatuses[server.id] = .checking
        Task {
            let result = await ServerHealthCheck.check(baseURL: url)
            switch result {
            case .reachable(let latencyMs):
                healthStatuses[server.id] = .reachable(latencyMs: latencyMs)
            case .unreachable(let reason):
                healthStatuses[server.id] = .unreachable(reason)
            }
        }
    }

    private func checkAllServers() {
        for server in servers {
            checkHealth(for: server)
        }
    }

    private func checkActiveServerHealth() {
        guard let active = servers.first(where: \.isActive) else { return }
        checkHealth(for: active)
    }

    private func ensureDefaultServerExists() {
        let hasDefault = servers.contains(where: \.isDefault)
        guard !hasDefault else { return }

        let production = ServerProfile(
            alias: String(localized: "server_default_alias"),
            urlString: "https://api.snowly.app",
            isActive: true,
            isDefault: true
        )
        modelContext.insert(production)
    }
}

// MARK: - Health Check State

private enum HealthCheckState {
    case idle
    case checking
    case reachable(latencyMs: Int)
    case unreachable(String)
}

// MARK: - Edit Sheet

private struct ServerEditSheet: View {
    enum Mode: Identifiable {
        case add
        case edit(ServerProfile)

        var id: String {
            switch self {
            case .add: "add"
            case .edit(let server): server.id.uuidString
            }
        }
    }

    let mode: Mode
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var alias: String = ""
    @State private var urlString: String = ""
    @State private var healthStatus: HealthCheckState = .idle
    @State private var isTestingConnection = false

    private var isValid: Bool {
        !alias.trimmingCharacters(in: .whitespaces).isEmpty
            && !urlString.trimmingCharacters(in: .whitespaces).isEmpty
            && URL(string: urlString) != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(
                        String(localized: "server_edit_alias_placeholder"),
                        text: $alias
                    )

                    TextField(
                        String(localized: "server_edit_url_placeholder"),
                        text: $urlString
                    )
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                } header: {
                    Label(String(localized: "server_edit_section_info"), systemImage: "info.circle")
                }

                Section {
                    Button {
                        testConnection()
                    } label: {
                        HStack {
                            Label(
                                String(localized: "server_edit_test_connection"),
                                systemImage: "bolt.horizontal"
                            )

                            Spacer()

                            switch healthStatus {
                            case .idle:
                                EmptyView()
                            case .checking:
                                ProgressView()
                                    .controlSize(.small)
                            case .reachable(let latencyMs):
                                Text(String(localized: "server_health_reachable \(latencyMs)"))
                                    .foregroundStyle(ColorTokens.success)
                                    .font(.caption)
                            case .unreachable(let reason):
                                Text(reason)
                                    .foregroundStyle(ColorTokens.error)
                                    .font(.caption)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .disabled(!isValid || isTestingConnection)
                } header: {
                    Label(String(localized: "server_edit_section_test"), systemImage: "antenna.radiowaves.left.and.right")
                }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "common_cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "common_save")) {
                        save()
                        dismiss()
                    }
                    .disabled(!isValid)
                }
            }
            .onAppear { loadExistingValues() }
        }
    }

    private var navigationTitle: String {
        switch mode {
        case .add: String(localized: "server_edit_title_add")
        case .edit: String(localized: "server_edit_title_edit")
        }
    }

    private func loadExistingValues() {
        if case .edit(let server) = mode {
            alias = server.alias
            urlString = server.urlString
        }
    }

    private func save() {
        let trimmedAlias = alias.trimmingCharacters(in: .whitespaces)
        let trimmedURL = urlString.trimmingCharacters(in: .whitespaces)

        switch mode {
        case .add:
            let server = ServerProfile(
                alias: trimmedAlias,
                urlString: trimmedURL
            )
            modelContext.insert(server)
        case .edit(let server):
            server.alias = trimmedAlias
            server.urlString = trimmedURL
        }
    }

    private func testConnection() {
        guard let url = URL(string: urlString.trimmingCharacters(in: .whitespaces)) else {
            return
        }
        healthStatus = .checking
        isTestingConnection = true
        Task {
            let result = await ServerHealthCheck.check(baseURL: url)
            switch result {
            case .reachable(let latencyMs):
                healthStatus = .reachable(latencyMs: latencyMs)
            case .unreachable(let reason):
                healthStatus = .unreachable(reason)
            }
            isTestingConnection = false
        }
    }
}
