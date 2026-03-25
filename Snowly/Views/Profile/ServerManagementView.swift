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
    @Environment(SkiDataUploadService.self) private var uploadService
    @Query(sort: \ServerProfile.createdAt) private var servers: [ServerProfile]

    @State private var editingServer: ServerProfile?
    @State private var showingAddSheet = false
    @State private var healthStatuses: [UUID: HealthCheckState] = [:]
    @State private var serverToDelete: ServerProfile?
    @State private var showingDeleteConfirmation = false

    var body: some View {
        Group {
            if servers.isEmpty {
                ContentUnavailableView(
                    String(localized: "server_empty_title"),
                    systemImage: "server.rack",
                    description: Text(String(localized: "server_empty_description"))
                )
            } else {
                serverList
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

            if !servers.isEmpty {
                ToolbarItem(placement: .secondaryAction) {
                    Button {
                        checkAllServers()
                    } label: {
                        Label(String(localized: "server_check_all"), systemImage: "arrow.trianglehead.2.clockwise")
                    }
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
            checkActiveServerHealth()
        }
    }

    private var serverList: some View {
        List {
            Section {
                ForEach(servers) { server in
                    serverRow(server)
                        .contentShape(Rectangle())
                        .onTapGesture { selectServer(server) }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                serverToDelete = server
                                showingDeleteConfirmation = true
                            } label: {
                                Label(String(localized: "server_action_delete"), systemImage: "trash")
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
    }

    // MARK: - Row

    private func serverRow(_ server: ServerProfile) -> some View {
        HStack(spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack(spacing: Spacing.sm) {
                    Text(server.alias)
                        .font(.headline)

                    registrationBadge(for: server)

                    if let username = serverUsername(for: server), !username.isEmpty {
                        Label(username, systemImage: "person.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
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

            // Role icons
            ForEach(server.typedRoles) { role in
                Image(systemName: role.iconName)
                    .font(.caption)
                    .foregroundStyle(role.color)
            }

            // Retry registration button for failed servers
            if server.resolvedRegistrationStatus == .failed {
                Button {
                    retryRegistration(for: server)
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                        .foregroundStyle(ColorTokens.error)
                }
                .buttonStyle(.plain)
            }

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

    // MARK: - Registration Badge

    @ViewBuilder
    private func registrationBadge(for server: ServerProfile) -> some View {
        switch server.resolvedRegistrationStatus {
        case .registered:
            Image(systemName: "checkmark.seal.fill")
                .font(.caption2)
                .foregroundStyle(ColorTokens.success)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption2)
                .foregroundStyle(ColorTokens.error)
        case .pending:
            Image(systemName: "clock.fill")
                .font(.caption2)
                .foregroundStyle(.orange)
        }
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
        activateServer(server, among: servers)

        if let apiBaseURL = server.apiBaseURL {
            crewService.updateServerBaseURL(apiBaseURL)
            uploadService.updateBaseURL(apiBaseURL)
        }
    }

    private func deleteServer(_ server: ServerProfile) {
        ServerCredentialService.delete(
            forServerURL: ServerCredentialService.normalizeURL(server.urlString)
        )

        if server.isActive, let next = servers.first(where: { $0.id != server.id }) {
            selectServer(next)
        }
        modelContext.delete(server)
        serverToDelete = nil
    }

    private func retryRegistration(for server: ServerProfile) {
        guard let serverURL = server.url else { return }

        let context = modelContext
        let serverId = server.id

        Task {
            let registrationService = ServerRegistrationService()

            // Fetch userId and username from UserProfile
            let profileDescriptor = FetchDescriptor<UserProfile>(sortBy: [SortDescriptor(\.createdAt)])
            guard let profile = (try? context.fetch(profileDescriptor))?.first else { return }

            await registrationService.register(
                serverBaseURL: serverURL,
                userId: profile.id.uuidString,
                displayName: profile.resolvedDisplayName
            )

            // Update the server's registration status
            let serverDescriptor = FetchDescriptor<ServerProfile>(
                predicate: #Predicate<ServerProfile> { $0.id == serverId }
            )
            guard let updatedServer = (try? context.fetch(serverDescriptor))?.first else { return }

            switch registrationService.state {
            case .success:
                updatedServer.registrationStatus = RegistrationStatus.registered.rawValue
                if !servers.contains(where: \.isActive) {
                    selectServer(updatedServer)
                }
            case .failed:
                updatedServer.registrationStatus = RegistrationStatus.failed.rawValue
            default:
                break
            }
        }
    }

    private func serverUsername(for server: ServerProfile) -> String? {
        let normalizedURL = ServerCredentialService.normalizeURL(server.urlString)
        return ServerCredentialService.load(forServerURL: normalizedURL)?.username
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
    @Query(sort: \UserProfile.createdAt) private var profiles: [UserProfile]

    @State private var alias: String = ""
    @State private var urlString: String = ""
    @State private var selectedRoles: Set<ServerRole> = []
    @State private var healthStatus: HealthCheckState = .idle
    @State private var isTestingConnection = false
    @State private var registrationService = ServerRegistrationService()
    @State private var registrationError: String?

    private var isValid: Bool {
        !alias.trimmingCharacters(in: .whitespaces).isEmpty
            && !urlString.trimmingCharacters(in: .whitespaces).isEmpty
            && URL(string: urlString) != nil
            && !selectedRoles.isEmpty
    }

    private var isRegistering: Bool {
        registrationService.state == .registering
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

                Section {
                    ForEach(ServerRole.allCases) { role in
                        Button {
                            if selectedRoles.contains(role) {
                                selectedRoles.remove(role)
                            } else {
                                selectedRoles.insert(role)
                            }
                        } label: {
                            HStack {
                                Label(role.label, systemImage: role.iconName)
                                    .foregroundStyle(role.color)
                                Spacer()
                                if selectedRoles.contains(role) {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(role.color)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Label(String(localized: "server_edit_section_roles"), systemImage: "tag")
                } footer: {
                    Text(String(localized: "server_edit_roles_footer"))
                }

                if isRegistering {
                    Section {
                        HStack {
                            ProgressView()
                                .controlSize(.small)
                            Text(String(localized: "server_registering"))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if let error = registrationError {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(ColorTokens.error)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "common_cancel")) { dismiss() }
                        .disabled(isRegistering)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "common_save")) {
                        performSave()
                    }
                    .disabled(!isValid || isRegistering)
                }
            }
            .interactiveDismissDisabled(isRegistering)
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
            selectedRoles = Set(server.typedRoles)
        }
    }

    private func performSave() {
        let trimmedAlias = alias.trimmingCharacters(in: .whitespaces)
        let trimmedURL = urlString.trimmingCharacters(in: .whitespaces)

        switch mode {
        case .add:
            let server = ServerProfile(
                alias: trimmedAlias,
                urlString: trimmedURL,
                registrationStatus: .pending,
                roles: selectedRoles.map(\.rawValue)
            )
            modelContext.insert(server)
            try? modelContext.save()

            guard let serverBaseURL = URL(string: trimmedURL) else {
                dismiss()
                return
            }

            let profile = profiles.first
            let userId = profile?.id.uuidString ?? UUID().uuidString
            let displayName = profile?.resolvedDisplayName ?? ""
            let serverId = server.id

            Task {
                await registrationService.register(
                    serverBaseURL: serverBaseURL,
                    userId: userId,
                    displayName: displayName
                )

                let descriptor = FetchDescriptor<ServerProfile>(
                    predicate: #Predicate<ServerProfile> { $0.id == serverId }
                )
                guard let savedServer = (try? modelContext.fetch(descriptor))?.first else {
                    dismiss()
                    return
                }

                switch registrationService.state {
                case .success:
                    savedServer.registrationStatus = RegistrationStatus.registered.rawValue
                    let allServers = (try? modelContext.fetch(FetchDescriptor<ServerProfile>())) ?? []
                    activateServer(savedServer, among: allServers)
                    dismiss()
                case .failed(let message):
                    savedServer.registrationStatus = RegistrationStatus.failed.rawValue
                    registrationError = message
                    // Keep sheet open briefly so user sees the error, then dismiss
                    try? await Task.sleep(for: .seconds(2))
                    dismiss()
                default:
                    dismiss()
                }
            }

        case .edit(let server):
            server.alias = trimmedAlias
            server.urlString = trimmedURL
            server.roles = selectedRoles.map(\.rawValue)
            dismiss()
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

// MARK: - Server Activation Helper

/// Deactivates all servers then activates the given one.
private func activateServer(_ server: ServerProfile, among allServers: [ServerProfile]) {
    for s in allServers where s.isActive {
        s.isActive = false
    }
    server.isActive = true
}
