import SwiftUI

/// App settings, grounded in what the opencode REST API actually exposes:
/// provider/API-key management (`GET /provider`, `PUT`/`DELETE /auth/{id}`),
/// read-only agent/command catalogues (`GET /agent`, `GET /command`), and the
/// connection/server entry point. Things opencode only configures via its config
/// file (MCP servers, skills, plugins) are intentionally not faked here.
struct SettingsView: View {
    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var store: KorboStore
    @EnvironmentObject private var github: GitHubStore
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var appearance = AppearanceStore.shared
    @Environment(\.openURL) private var openURL

    @State private var keyTarget: OCProvider?
    @State private var keyInput: String = ""
    @State private var removeTarget: OCProvider?
    @State private var showAllProviders = false
    @State private var oauthLaunch: OAuthLaunch?

    /// Identifies a specific OAuth sign-in option (a provider + one of its
    /// `oauth`-type auth methods) so it can drive a `.sheet(item:)`.
    struct OAuthLaunch: Identifiable {
        let provider: OCProvider
        let methodIndex: Int
        let method: ProviderAuthMethod
        var id: String { "\(provider.id)#\(methodIndex)" }
    }

    var body: some View {
        NavigationStack {
            Form {
                connectionSection
                githubSection
                appearanceSection
                chatSection
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
            .sheet(isPresented: deviceFlowSheetBinding) {
                if let flow = github.deviceFlow {
                    DeviceFlowSheet(flow: flow) {
                        github.cancelDeviceFlow()
                    }
                    .presentationDetents([.medium])
                }
            }
            .sheet(item: $oauthLaunch) { launch in
                ProviderOAuthSheet(providerID: launch.provider.id,
                                   providerName: launch.provider.name ?? launch.provider.id,
                                   methodIndex: launch.methodIndex,
                                   method: launch.method)
                    .presentationDetents([.medium, .large])
            }
            .task {
                if store.status.isConnected { await store.loadProviderAuthMethods() }
            }
        }
    }

    // MARK: GitHub

    @ViewBuilder
    private var githubSection: some View {
        Section {
            if github.isSignedIn {
                HStack(spacing: 10) {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(Theme.textSecondary)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("@" + (github.authedUser?.login ?? "…"))
                            .foregroundStyle(Theme.textPrimary)
                        if let name = github.authedUser?.name, !name.isEmpty {
                            Text(name).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                }
                Button(role: .destructive) {
                    github.signOut()
                } label: {
                    Label("Sign out of GitHub", systemImage: "rectangle.portrait.and.arrow.right")
                }
            } else {
                Button {
                    Task { await github.startDeviceFlow() }
                } label: {
                    Label("Sign in with GitHub", systemImage: "arrow.right.circle")
                }
                .disabled(github.deviceFlow != nil)

                DisclosureGroup("Advanced") {
                    TextField("Custom OAuth App Client ID", text: $github.clientID)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .font(.system(size: 13, design: .monospaced))
                    Text("Optional. Leave blank to use Korbo's built-in GitHub app. Set this only if you want to authorize against your own OAuth App (Device Flow must be enabled).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("GitHub")
        } footer: {
            Text("Sign in with GitHub to open and review pull requests. Korbo uses GitHub's secure device flow — it never sees your password and never asks for a client secret.")
        }
    }

    private var deviceFlowSheetBinding: Binding<Bool> {
        Binding(
            get: { github.deviceFlow != nil },
            set: { if !$0 { github.cancelDeviceFlow() } }
        )
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

            // Code theme
            Picker("Code theme", selection: $appearance.codeTheme) {
                ForEach(AppearanceStore.CodeTheme.allCases) { theme in
                    Text(theme.label).tag(theme)
                }
            }
            CodeThemePreview(palette: appearance.codeTheme.palette)
                .padding(.vertical, 2)
        } header: {
            Text("Appearance")
        } footer: {
            Text("Text size and density affect Dynamic Type–respecting text and standard controls.")
        }
    }

    // MARK: Chat

    private var chatSection: some View {
        Section {
            Toggle("Render markdown", isOn: $appearance.renderMarkdown)

            LabeledContent("Default model") {
                Text(store.effectiveModelLabel)
                    .foregroundStyle(.secondary)
            }
            LabeledContent("Default agent") {
                Text(store.resolveAgent()?.capitalized ?? "Auto")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Chat")
        } footer: {
            Text("Markdown off shows assistant replies as plain monospaced text. The default model and agent are chosen from the composer and remembered for new sessions.")
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
                ForEach(Array(oauthMethods(for: provider).enumerated()), id: \.offset) { entry in
                    Button {
                        oauthLaunch = OAuthLaunch(provider: provider,
                                                  methodIndex: entry.element.index,
                                                  method: entry.element.method)
                    } label: {
                        Label(entry.element.method.label, systemImage: "person.badge.key")
                    }
                }
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

    /// OAuth sign-in methods for a provider (with their original index, which the
    /// authorize/callback endpoints require), from `GET /provider/auth`.
    private func oauthMethods(for provider: OCProvider) -> [(index: Int, method: ProviderAuthMethod)] {
        let methods = store.providerAuthMethods[provider.id] ?? []
        return methods.enumerated()
            .filter { $0.element.isOAuth }
            .map { (index: $0.offset, method: $0.element) }
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

/// Sheet shown while a GitHub Device Flow authorisation is in progress. The
/// user copies the short `userCode`, opens `verification_uri` in Safari,
/// pastes the code, and the polling loop in `GitHubStore` finishes sign-in.
private struct DeviceFlowSheet: View {
    let flow: DeviceFlowState
    let onCancel: () -> Void
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Text("Authorize Korbo on GitHub")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text("Open GitHub, paste the code below, and approve access.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Text(flow.userCode)
                    .font(.system(size: 32, weight: .bold, design: .monospaced))
                    .tracking(4)
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.vertical, 14)
                    .padding(.horizontal, 22)
                    .background(Theme.panelRaised, in: RoundedRectangle(cornerRadius: 10))

                HStack(spacing: 10) {
                    Button {
                        UIPasteboard.general.string = flow.userCode
                    } label: {
                        Label("Copy code", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        if let url = URL(string: flow.verificationURI) {
                            openURL(url)
                        }
                    } label: {
                        Label("Open github.com/login/device", systemImage: "safari")
                    }
                    .buttonStyle(.borderedProminent)
                }

                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Waiting for authorization…")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
                .padding(.top, 4)

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(24)
            .background(Theme.bg)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                        dismiss()
                    }
                }
            }
        }
    }
}

/// Small inline swatch row that previews the selected code theme's token
/// colours, so the picker shows its effect without leaving Settings.
private struct CodeThemePreview: View {
    let palette: AppearanceStore.CodeTheme.Palette

    var body: some View {
        HStack(spacing: 0) {
            Text("func ").foregroundStyle(palette.keyword)
            Text("greet").foregroundStyle(palette.type)
            Text("() { ").foregroundStyle(palette.plain ?? Theme.textPrimary)
            Text("// hi").foregroundStyle(palette.comment)
            Text(" ").foregroundStyle(palette.plain ?? Theme.textPrimary)
            Text("\"x\"").foregroundStyle(palette.string)
            Text(" ").foregroundStyle(palette.plain ?? Theme.textPrimary)
            Text("42").foregroundStyle(palette.number)
            Text(" }").foregroundStyle(palette.plain ?? Theme.textPrimary)
        }
        .font(.system(size: 12.5, design: .monospaced))
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.panelRaised)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Code theme preview")
    }
}
