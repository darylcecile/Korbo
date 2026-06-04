import SwiftUI

/// Server connection editor + status. Lets the user point Korbo at an opencode
/// endpoint (e.g. korbo.app:4096), choose an auth method, enter credentials
/// (stored in the Keychain), and connect.
struct ConnectionSheet: View {
    @EnvironmentObject private var store: KorboStore
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var urlString: String = ""
    @State private var authKind: AuthKind = .basic
    @State private var username: String = ""
    @State private var secret: String = ""
    @State private var configID: UUID?
    @State private var isConnecting = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Korbo Cloud") {
                    Button {
                        // Hand off to the cloud sheet; close this one first so the
                        // two sheets (both anchored to the root) don't collide.
                        app.showConnectionSheet = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            app.showCloudSheet = true
                        }
                    } label: {
                        Label("Manage Korbo Cloud…", systemImage: "cloud")
                    }
                    Text("Sign in to run opencode on a provisioned cloud instance — no server setup required.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Server") {
                    TextField("Name", text: $name)
                    TextField("URL (e.g. korbo.app:4096)", text: $urlString)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                }

                Section("Authentication") {
                    Picker("Method", selection: $authKind) {
                        ForEach(AuthKind.allCases) { kind in
                            Text(kind.label).tag(kind)
                        }
                    }
                    if authKind == .basic {
                        TextField("Username", text: $username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        SecureField("Password", text: $secret)
                    } else if authKind == .bearer {
                        SecureField("Token", text: $secret)
                    }
                    if authKind != .none {
                        Text("Credentials are stored in the iPad Keychain, never in plain text.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    statusRow
                    if case .failed(let message) = store.status {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(Theme.removed)
                    }
                }

                if store.servers.servers.count > 1 {
                    Section("Saved servers") {
                        ForEach(store.servers.servers) { server in
                            Button {
                                load(server)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(server.name)
                                        Text(server.normalizedURLString)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if server.id == configID {
                                        Image(systemName: "checkmark").foregroundStyle(Theme.accent)
                                    }
                                }
                            }
                            .tint(.primary)
                        }
                    }
                }
            }
            .navigationTitle("Connection")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Connect") { connect() }
                        .disabled(urlString.trimmingCharacters(in: .whitespaces).isEmpty || isConnecting)
                }
            }
        }
        .onAppear(perform: loadSelected)
    }

    private var statusRow: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)
            Text(store.status.label)
            Spacer()
            if isConnecting { ProgressView() }
        }
    }

    private var statusColor: Color {
        switch store.status {
        case .connected: return Theme.added
        case .connecting: return Theme.accent
        case .failed: return Theme.removed
        case .disconnected: return Theme.textTertiary
        }
    }

    private func loadSelected() {
        if let server = store.servers.selectedServer {
            load(server)
        } else {
            authKind = .basic
        }
    }

    private func load(_ server: ServerConfig) {
        configID = server.id
        name = server.name
        urlString = server.baseURLString
        authKind = server.authKind
        username = server.username
        secret = "" // never surface the stored secret; blank means "leave unchanged"
    }

    private func connect() {
        var config = ServerConfig(
            name: name.isEmpty ? "Server" : name,
            baseURLString: urlString,
            authKind: authKind,
            username: username
        )
        if let configID { config.id = configID }
        // Only overwrite the Keychain secret when the user typed a new one.
        let secretToStore: String? = secret.isEmpty ? nil : secret
        store.servers.save(config, secret: secretToStore)
        configID = config.id

        isConnecting = true
        Task {
            await store.connect()
            isConnecting = false
            if store.status.isConnected { dismiss() }
        }
    }
}
