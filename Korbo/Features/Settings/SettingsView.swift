import SwiftUI

/// App settings, grounded in what the opencode REST API actually exposes:
/// provider/API-key management (`GET /provider`, `PUT`/`DELETE /auth/{id}`),
/// read-only agent/command catalogues (`GET /agent`, `GET /command`), and the
/// connection/server entry point. Things opencode only configures via its config
/// file (MCP servers, skills, plugins) are intentionally not faked here.
struct SettingsView: View {
    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var store: KorboStore
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var appearance = AppearanceStore.shared

    @State private var keyTarget: OCProvider?
    @State private var keyInput: String = ""
    @State private var removeTarget: OCProvider?
    @State private var showAllProviders = false

    var body: some View {
        NavigationStack {
            Form {
                connectionSection
                appearanceSection
                providersSection
                agentsSection
                commandsSection
                aboutSection
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Add API key", isPresented: keyAlertBinding) {
                SecureField("API key", text: $keyInput)
                Button("Cancel", role: .cancel) { keyTarget = nil; keyInput = "" }
                Button("Save") {
                    if let provider = keyTarget {
                        let key = keyInput
                        Task { await store.addProviderKey(provider.id, key: key) }
                    }
                    keyTarget = nil
                    keyInput = ""
                }
            } message: {
                Text("Stored on the opencode server for \(keyTarget?.name ?? keyTarget?.id ?? "this provider").")
            }
            .confirmationDialog(
                "Remove credentials?",
                isPresented: removeAlertBinding,
                titleVisibility: .visible
            ) {
                Button("Remove", role: .destructive) {
                    if let provider = removeTarget {
                        Task { await store.removeProviderKey(provider.id) }
                    }
                    removeTarget = nil
                }
                Button("Cancel", role: .cancel) { removeTarget = nil }
            } message: {
                Text("Disconnects \(removeTarget?.name ?? removeTarget?.id ?? "this provider") until you add a key again.")
            }
        }
    }

    // MARK: Connection

    private var connectionSection: some View {
        Section("Connection") {
            HStack(spacing: 10) {
                Circle().fill(statusColor).frame(width: 9, height: 9)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.servers.selectedServer?.name ?? "No server")
                    Text(store.servers.selectedServer?.normalizedURLString ?? store.status.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(store.status.label).font(.caption).foregroundStyle(.secondary)
            }
            Button("Change server…") {
                dismiss()
                app.showConnectionSheet = true
            }
        }
    }

    // MARK: Appearance

    private var appearanceSection: some View {
        Section {
            // Accent color swatches
            VStack(alignment: .leading, spacing: 8) {
                Text("Accent").font(.subheadline)
                HStack(spacing: 12) {
                    ForEach(AppearanceStore.Accent.allCases) { accent in
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                appearance.accent = accent
                            }
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(accent.color)
                                    .frame(width: 26, height: 26)
                                if appearance.accent == accent {
                                    Circle()
                                        .strokeBorder(Theme.textPrimary, lineWidth: 2)
                                        .frame(width: 32, height: 32)
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(.white)
                                        .accessibilityHidden(true)
                                }
                            }
                            .frame(width: 36, height: 36)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.vertical, 4)

            // Theme variant
            Picker("Theme", selection: $appearance.theme) {
                ForEach(AppearanceStore.ThemeVariant.allCases) { variant in
                    Text(variant.label).tag(variant)
                }
            }
            .pickerStyle(.segmented)

            // Text size
            Picker("Text size", selection: $appearance.textSize) {
                ForEach(AppearanceStore.TextSize.allCases) { size in
                    Text(size.label).tag(size)
                }
            }
            .pickerStyle(.segmented)

            // Density
            Picker("Density", selection: $appearance.density) {
                ForEach(AppearanceStore.Density.allCases) { density in
                    Text(density.label).tag(density)
                }
            }
            .pickerStyle(.segmented)
        } header: {
            Text("Appearance")
        } footer: {
            Text("Text size and density affect Dynamic Type–respecting text and standard controls.")
        }
    }

    // MARK: Providers & API keys

    @ViewBuilder
    private var providersSection: some View {
        Section {
            if let providers = store.providers, !providers.all.isEmpty {
                let connected = orderedProviders(providers).filter { providers.connected.contains($0.id) }
                let others = orderedProviders(providers).filter { !providers.connected.contains($0.id) }
                ForEach(connected) { provider in
                    providerRow(provider, connected: true)
                }
                if connected.isEmpty {
                    Text("No connected providers yet — add an API key below.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if !others.isEmpty {
                    DisclosureGroup(isExpanded: $showAllProviders) {
                        ForEach(others) { provider in
                            providerRow(provider, connected: false)
                        }
                    } label: {
                        Text("All providers (\(others.count))")
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            } else if store.status.isConnected {
                Text("No providers reported by the server.")
                    .foregroundStyle(.secondary)
            } else {
                Text("Connect to a server to manage providers.")
                    .foregroundStyle(.secondary)
            }
        } header: {
            HStack {
                Text("Providers & API keys")
                Spacer()
                if store.isUpdatingAuth { ProgressView().controlSize(.mini) }
                Button {
                    Task { await store.reloadProviders() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(!store.status.isConnected)
                .accessibilityLabel("Refresh providers")
            }
        } footer: {
            Text("API keys are sent to the opencode server, which stores them. Providers configured via environment variables or the server config file appear here too.")
        }
    }

    private func providerRow(_ provider: OCProvider, connected: Bool) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(connected ? Theme.added : Theme.textTertiary)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(provider.name ?? provider.id)
                Text(modelCountLabel(provider) + (connected ? " · Connected" : ""))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Menu {
                Button {
                    keyTarget = provider
                    keyInput = ""
                } label: {
                    Label(connected ? "Replace API key" : "Add API key", systemImage: "key")
                }
                if connected {
                    Button(role: .destructive) {
                        removeTarget = provider
                    } label: {
                        Label("Remove credentials", systemImage: "trash")
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle").foregroundStyle(Theme.textSecondary)
            }
            .disabled(!store.status.isConnected || store.isUpdatingAuth)
            .accessibilityLabel("Provider options")
        }
    }

    private func modelCountLabel(_ provider: OCProvider) -> String {
        let n = provider.models?.count ?? 0
        return n == 1 ? "1 model" : "\(n) models"
    }

    /// Connected providers first (so configured ones are easy to find), then the
    /// rest alphabetically by display name.
    private func orderedProviders(_ providers: OCProvidersResponse) -> [OCProvider] {
        providers.all.sorted { a, b in
            let ca = providers.connected.contains(a.id)
            let cb = providers.connected.contains(b.id)
            if ca != cb { return ca }
            return (a.name ?? a.id).localizedCaseInsensitiveCompare(b.name ?? b.id) == .orderedAscending
        }
    }

    // MARK: Agents (read-only)

    @ViewBuilder
    private var agentsSection: some View {
        Section {
            if store.agents.isEmpty {
                Text(store.status.isConnected ? "No agents configured." : "Connect to load agents.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(store.agents.filter { !($0.hidden ?? false) }) { agent in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(agent.name)
                            if let mode = agent.mode {
                                Text(mode)
                                    .font(.caption2)
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(Capsule().fill(Theme.panelRaised))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        if let description = agent.description, !description.isEmpty {
                            Text(description).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        } header: {
            Text("Agents")
        } footer: {
            Text("Agents are defined in the opencode workspace config; this list is read-only.")
        }
    }

    // MARK: Commands (read-only)

    @ViewBuilder
    private var commandsSection: some View {
        if !store.commands.isEmpty {
            Section("Commands") {
                ForEach(store.commands) { command in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("/" + command.name)
                        if let description = command.description, !description.isEmpty {
                            Text(description).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    // MARK: About

    private var aboutSection: some View {
        Section("About") {
            LabeledContent("App", value: "Korbo")
            LabeledContent("Version", value: appVersion)
            if let url = store.servers.selectedServer?.normalizedURLString {
                LabeledContent("Server", value: url)
            }
        }
    }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }

    // MARK: Helpers

    private var statusColor: Color {
        switch store.status {
        case .connected: return Theme.added
        case .connecting: return Theme.accent
        case .failed: return Theme.removed
        case .disconnected: return Theme.textTertiary
        }
    }

    private var keyAlertBinding: Binding<Bool> {
        Binding(get: { keyTarget != nil }, set: { if !$0 { keyTarget = nil; keyInput = "" } })
    }
    private var removeAlertBinding: Binding<Bool> {
        Binding(get: { removeTarget != nil }, set: { if !$0 { removeTarget = nil } })
    }
}
