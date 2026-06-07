import SwiftUI

/// Korbo Cloud "Instances" section. Lists the account's provisioned cloud
/// instances and lets the user spawn, connect to, inspect, and delete them.
///
/// This is a self-contained `View` meant to be embedded inside a parent
/// dashboard's `ScrollView`/`List` — it deliberately avoids wrapping itself in a
/// `NavigationStack`. The parent owns the account / sign-in surface; when the
/// user is signed out this view renders a minimal placeholder. The spawn flow is
/// presented internally as a sheet.
struct CloudInstancesView: View {
    @EnvironmentObject private var cloud: CloudStore

    @State private var showSpawnSheet = false
    @State private var pendingDelete: CloudInstance?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if cloud.isSignedIn {
                header
                if let error = cloud.lastError, !error.isEmpty {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(Theme.removed)
                }
                instanceList
            } else {
                signedOutPlaceholder
            }
        }
        .task { if cloud.isSignedIn { await cloud.refreshInstances() } }
        .sheet(isPresented: $showSpawnSheet) {
            SpawnInstanceSheet().environmentObject(cloud)
        }
        .alert(
            "Delete instance?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            presenting: pendingDelete
        ) { instance in
            Button("Delete", role: .destructive) { delete(instance) }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: { instance in
            Text("This permanently terminates \(instance.id).")
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Text("Instances")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            Button {
                Task { await cloud.refreshInstances() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .tint(Theme.accent)
            .disabled(cloud.isBusy)

            Button {
                showSpawnSheet = true
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.borderless)
            .tint(Theme.accent)
            .accessibilityLabel("New instance")
        }
    }

    // MARK: - List

    @ViewBuilder
    private var instanceList: some View {
        if cloud.instances.isEmpty {
            Text("No instances yet. Tap + to spawn one.")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
        } else {
            VStack(spacing: 10) {
                ForEach(cloud.instances) { instance in
                    InstanceRow(instance: instance) { pendingDelete = instance }
                        .environmentObject(cloud)
                }
            }
        }
    }

    private var signedOutPlaceholder: some View {
        Text("Sign in to manage cloud instances.")
            .font(.subheadline)
            .foregroundStyle(Theme.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Actions

    private func delete(_ instance: CloudInstance) {
        pendingDelete = nil
        Task {
            try? await cloud.deleteInstance(instance.id)
            await cloud.refreshInstances()
        }
    }
}

// MARK: - Instance row

/// A single instance card: identity, machine type, state pill, optional repo,
/// relative age, primary Connect action, an expandable details disclosure, and a
/// delete affordance (context menu).
private struct InstanceRow: View {
    @EnvironmentObject private var cloud: CloudStore
    @Environment(\.openURL) private var openURL

    let instance: CloudInstance
    let onDelete: () -> Void

    /// Top-up amounts (in credits) offered when resuming a suspended instance.
    private let topupAmounts = [1000, 5000, 10000]

    @State private var showDetails = false
    @State private var detail: CloudInstanceStateDetail?
    @State private var loadingDetail = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            topLine
            metaLine
            if let repo = instance.repo, !repo.isEmpty {
                Label(repo, systemImage: "folder")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if isBlocked, let reason = instance.reason, !reason.isEmpty {
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(Theme.removed)
            } else if instance.state.isSuspended {
                suspendedBanner
            } else if let warning = cloneWarning {
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(Theme.removed)
                    .fixedSize(horizontal: false, vertical: true)
            }
            actionRow
            if showDetails { detailsBlock }
        }
        .padding(14)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.border, lineWidth: 1)
        )
        .contextMenu {
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private var topLine: some View {
        HStack(spacing: 10) {
            Text(instance.id)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            statePill
        }
    }

    private var metaLine: some View {
        HStack(spacing: 8) {
            Text(instance.machineType)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
            if let created = instance.createdAt {
                Text("·").foregroundStyle(Theme.textTertiary)
                Text(RelativeTime.short(created))
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
            }
        }
    }

    private var statePill: some View {
        Text(instance.state.displayLabel)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(pillColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(pillColor.opacity(0.15)))
    }

    /// Out-of-credits (suspended) affordance: the instance is recoverable — its
    /// workspace + conversation are retained until `purgeAt`. Top up, then
    /// Connect to resume right where it left off.
    private var suspendedBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text(suspendedMessage)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "bolt.slash.fill")
            }
            .font(.caption)
            .foregroundStyle(Theme.warning)

            Menu {
                ForEach(topupAmounts, id: \.self) { amount in
                    Button("\(amount) credits") { buyCredits(amount) }
                }
            } label: {
                Label("Buy credits to resume", systemImage: "creditcard")
                    .font(.caption.weight(.semibold))
            }
            .disabled(cloud.isBusy)
        }
    }

    private var suspendedMessage: String {
        if let purge = instance.purgeAt {
            return "Out of credits. Your workspace and conversation are saved until "
                + purge.formatted(date: .abbreviated, time: .shortened)
                + ". Top up, then Connect to resume."
        }
        return "Out of credits. Top up, then Connect to resume where you left off."
    }

    private var actionRow: some View {
        HStack(spacing: 12) {
            Button {
                Task { await cloud.connectToInstance(instance) }
            } label: {
                Text("Connect")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(canConnect ? Color.white : Theme.textTertiary)
            .background(
                RoundedRectangle(cornerRadius: 9)
                    .fill(canConnect ? Theme.accent : Theme.panelRaised)
            )
            .disabled(!canConnect)

            Button {
                toggleDetails()
            } label: {
                HStack(spacing: 4) {
                    if loadingDetail {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: showDetails ? "chevron.up" : "chevron.down")
                    }
                    Text("Details")
                }
                .font(.caption)
            }
            .buttonStyle(.borderless)
            .tint(Theme.textSecondary)
        }
    }

    @ViewBuilder
    private var detailsBlock: some View {
        if let detail {
            VStack(alignment: .leading, spacing: 4) {
                detailRow("Credits / min", String(format: "%.2f", detail.creditsPerMinute))
                detailRow("Balance", String(format: "%.0f", detail.balanceCredits))
                if let expires = detail.expiresAt {
                    detailRow("Expires", expires.formatted(date: .abbreviated, time: .shortened))
                }
                if let purge = detail.purgeAt {
                    detailRow("Recoverable until", purge.formatted(date: .abbreviated, time: .shortened))
                }
            }
            .padding(.top, 2)
        } else if !loadingDetail {
            Text("Details unavailable.")
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
        }
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(Theme.textTertiary)
            Spacer()
            Text(value).foregroundStyle(Theme.textSecondary)
        }
        .font(.caption)
    }

    // MARK: Derived

    private var pillColor: Color {
        let state = instance.state
        if state.isReady { return Theme.added }
        if state.isSuspended { return Theme.warning }
        if state.isTerminal { return Theme.removed }
        if state.isTransitional { return Theme.accent }
        return Theme.textSecondary
    }

    private var isBlocked: Bool { instance.state.isTerminal }

    /// A non-fatal clone failure surfaced by the backend as the ready instance's
    /// `reason` (e.g. repo not found, or the Korbo GitHub App isn't installed on
    /// the owner). Shown as a warning so the empty workspace isn't a mystery.
    private var cloneWarning: String? {
        guard let reason = instance.reason, reason.hasPrefix("repo_clone_failed") else { return nil }
        let cleaned = reason.replacingOccurrences(of: "repo_clone_failed: ", with: "")
        return cleaned == reason ? reason : cleaned
    }

    private var canConnect: Bool { !cloud.isBusy && !isBlocked }

    // MARK: Actions

    private func toggleDetails() {
        if showDetails {
            showDetails = false
            return
        }
        showDetails = true
        guard detail == nil else { return }
        loadingDetail = true
        Task {
            detail = try? await cloud.instanceState(instance.id)
            loadingDetail = false
        }
    }

    private func buyCredits(_ amount: Int) {
        Task {
            if let url = try? await cloud.topupURL(credits: amount) {
                openURL(url)
            }
        }
    }
}

// MARK: - Spawn sheet

/// Modal for provisioning a new instance: pick a machine type, optionally bind a
/// GitHub repository (via installation → repo lookup, or a manual `owner/name`
/// fallback), then create.
private struct SpawnInstanceSheet: View {
    @EnvironmentObject private var cloud: CloudStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    /// Source of the repository the new instance is bound to.
    private enum RepoMode: String, CaseIterable, Identifiable {
        case none = "No repo"
        case pick = "From GitHub"
        case manual = "Enter manually"
        var id: String { rawValue }
    }

    @State private var machineType: String = CloudMachineType.default.id
    @State private var repoMode: RepoMode = .none

    @State private var installations: [CloudInstallation] = []
    @State private var selectedInstallation: Int?
    @State private var repos: [CloudRepo] = []
    @State private var selectedRepo: String?
    @State private var repoSearch: String = ""

    @State private var manualRepo: String = ""

    @State private var loadingInstallations = false
    @State private var loadingRepos = false
    @State private var creating = false
    @State private var openingInstall = false
    @State private var localError: String?

    private static let manualRepoPattern = #"^[\w.-]+/[\w.-]+$"#

    var body: some View {
        NavigationStack {
            Form {
                Section("Machine type") {
                    Picker("Type", selection: $machineType) {
                        ForEach(CloudMachineType.all) { type in
                            Text(type.label).tag(type.id)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Section("Repository") {
                    Picker("Source", selection: $repoMode) {
                        ForEach(RepoMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    switch repoMode {
                    case .none:
                        Text("Creates a blank instance with no repository.")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    case .pick:
                        githubRepoPicker
                    case .manual:
                        manualRepoField
                    }
                }

                if let error = errorText, !error.isEmpty {
                    Section {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(Theme.removed)
                    }
                }
            }
            .navigationTitle("New instance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if creating {
                        ProgressView()
                    } else {
                        Button("Create") { create() }
                            .disabled(!canCreate)
                    }
                }
            }
        }
    }

    // MARK: - GitHub repo flow

    @ViewBuilder
    private var githubRepoPicker: some View {
        if installations.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    loadInstallations()
                } label: {
                    HStack {
                        Text("Load repos")
                        if loadingInstallations {
                            Spacer()
                            ProgressView().controlSize(.mini)
                        }
                    }
                }
                .disabled(loadingInstallations || openingInstall)
                .tint(Theme.accent)

                installAppButton
                Text("Private repos need the Korbo GitHub App installed on the owner. Installing lets you pick exactly which repos Korbo can access.")
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
            }
        } else {
            Picker("Account", selection: Binding(
                get: { selectedInstallation },
                set: { newValue in
                    selectedInstallation = newValue
                    selectedRepo = nil
                    repos = []
                    if let id = newValue { loadRepos(installationId: id) }
                }
            )) {
                Text("Select").tag(Int?.none)
                ForEach(installations) { installation in
                    Text(installation.account).tag(Int?.some(installation.id))
                }
            }

            if loadingRepos {
                HStack {
                    Text("Loading repositories…")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                    ProgressView().controlSize(.mini)
                }
            } else if !repos.isEmpty {
                TextField("Filter", text: $repoSearch)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Picker("Repository", selection: $selectedRepo) {
                    Text("None").tag(String?.none)
                    ForEach(filteredRepos) { repo in
                        Text(repo.fullName).tag(String?.some(repo.fullName))
                    }
                }
            } else if selectedInstallation != nil {
                Text("No repositories available for this account.")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }

            // Always offer the install/manage link so a missing repo can be
            // granted access without leaving for GitHub settings manually.
            installAppButton
        }
    }

    /// One-tap deep link to the Korbo GitHub App's install/configure page. Since
    /// GitHub requires explicit owner consent, this is the closest to "automatic"
    /// we can offer — and on return the new installation self-resolves at spawn.
    private var installAppButton: some View {
        Button {
            openInstall()
        } label: {
            HStack {
                Label("Install / manage GitHub App", systemImage: "arrow.up.forward.app")
                if openingInstall {
                    Spacer()
                    ProgressView().controlSize(.mini)
                }
            }
        }
        .disabled(openingInstall)
        .tint(Theme.accent)
    }

    private var manualRepoField: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("owner/name", text: $manualRepo)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !manualRepo.isEmpty && !manualRepoIsValid {
                Text("Use the format owner/name.")
                    .font(.caption)
                    .foregroundStyle(Theme.removed)
            }
        }
    }

    private var filteredRepos: [CloudRepo] {
        let term = repoSearch.trimmingCharacters(in: .whitespaces).lowercased()
        guard !term.isEmpty else { return repos }
        return repos.filter { $0.fullName.lowercased().contains(term) }
    }

    // MARK: - Validation

    private var manualRepoIsValid: Bool {
        manualRepo.range(of: Self.manualRepoPattern, options: .regularExpression) != nil
    }

    private var resolvedRepo: String? {
        switch repoMode {
        case .none: return nil
        case .pick: return selectedRepo
        case .manual:
            return manualRepoIsValid ? manualRepo : nil
        }
    }

    private var canCreate: Bool {
        guard !creating else { return false }
        switch repoMode {
        case .none, .pick: return true
        case .manual: return manualRepoIsValid
        }
    }

    private var errorText: String? { localError ?? cloud.lastError }

    // MARK: - Actions

    private func loadInstallations() {
        loadingInstallations = true
        localError = nil
        Task {
            do {
                installations = try await cloud.installations()
                if installations.isEmpty {
                    localError = "No GitHub installations yet. Install the Korbo GitHub App, or enter a repo manually."
                }
            } catch {
                localError = (error as? CloudError)?.errorDescription ?? error.localizedDescription
            }
            loadingInstallations = false
        }
    }

    /// Open the Korbo GitHub App install page. After the user grants access and
    /// returns, re-load installations so the freshly-granted repos appear.
    private func openInstall() {
        openingInstall = true
        localError = nil
        Task {
            defer { openingInstall = false }
            do {
                let url = try await cloud.installURL()
                openURL(url)
            } catch {
                localError = (error as? CloudError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    private func loadRepos(installationId: Int) {
        loadingRepos = true
        localError = nil
        Task {
            do {
                repos = try await cloud.repos(installationId: installationId)
            } catch {
                localError = (error as? CloudError)?.errorDescription ?? error.localizedDescription
            }
            loadingRepos = false
        }
    }

    private func create() {
        creating = true
        localError = nil
        let machine = machineType
        let repo = resolvedRepo
        Task {
            _ = try? await cloud.createInstance(machineType: machine, repo: repo)
            await cloud.refreshInstances()
            creating = false
            dismiss()
        }
    }
}
