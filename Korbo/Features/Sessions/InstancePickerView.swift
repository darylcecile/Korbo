import SwiftUI

/// A searchable cloud-instance switcher. Replaces the old project switcher: the
/// unit a user moves between is a provisioned Korbo Cloud instance, labelled by
/// its repo (never the raw instance id). Picking one connects the shared opencode
/// session to that instance's proxy. A dropdown doesn't scale once an account has
/// several instances, so this sheet lets the user filter by repo or id.
struct InstancePickerView: View {
    @EnvironmentObject private var cloud: CloudStore
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @FocusState private var searchFocused: Bool
    @State private var renameTarget: CloudSession?
    @State private var renameText = ""

    private var filtered: [CloudInstance] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return cloud.instances }
        return cloud.instances.filter {
            $0.displayName.localizedCaseInsensitiveContains(trimmed)
                || ($0.repo ?? "").localizedCaseInsensitiveContains(trimmed)
                || $0.id.localizedCaseInsensitiveContains(trimmed)
        }
    }

    private var filteredSessions: [CloudSession] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return cloud.sessions }
        return cloud.sessions.filter {
            $0.displayName.localizedCaseInsensitiveContains(trimmed)
                || ($0.repo ?? "").localizedCaseInsensitiveContains(trimmed)
                || $0.id.localizedCaseInsensitiveContains(trimmed)
        }
    }

    private var hasResults: Bool { !filtered.isEmpty || !filteredSessions.isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            header
            searchField
            Divider().overlay(Theme.panelRaised)
            if hasResults {
                list
            } else {
                emptyState
            }
            Divider().overlay(Theme.panelRaised)
            manageButton
        }
        .background(Theme.panel)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task {
            if cloud.isSignedIn {
                await cloud.refreshInstances()
                await cloud.refreshSessions()
            }
        }
        .alert("Rename machine", isPresented: Binding(
            get: { renameTarget != nil },
            set: { if !$0 { renameTarget = nil } }
        )) {
            TextField("Name", text: $renameText)
            Button("Cancel", role: .cancel) { renameTarget = nil }
            Button("Save") {
                if let target = renameTarget {
                    cloud.renameSession(target.id, to: renameText)
                }
                renameTarget = nil
            }
        } message: {
            Text("Shown only on this device.")
        }
    }

    private var header: some View {
        HStack {
            Text("Switch Instance")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            Text("\(cloud.instances.count + cloud.sessions.count)")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
                .monospacedDigit()
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(Theme.textTertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 10)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textTertiary)
            TextField("Search instances", text: $query)
                .font(.system(size: 14))
                .foregroundStyle(Theme.textPrimary)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .focused($searchFocused)
                .submitLabel(.done)
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.panelRaised))
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }

    /// Promote "Your machines" above cloud instances once the user has at least
    /// one reachable machine — their own hardware is the thing they reach for most
    /// when it's online. Based on the full session set (not the search-filtered
    /// one) so the section order doesn't jump around while typing.
    private var machinesFirst: Bool {
        cloud.sessions.contains { $0.status.isOnline }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                if machinesFirst {
                    machinesSection
                    instancesSection
                } else {
                    instancesSection
                    machinesSection
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    @ViewBuilder
    private var instancesSection: some View {
        if !filtered.isEmpty {
            if !filteredSessions.isEmpty {
                sectionHeader("Cloud instances")
            }
            ForEach(filtered) { instance in
                row(instance)
                if instance.id != filtered.last?.id {
                    Divider().overlay(Theme.panelRaised.opacity(0.5))
                        .padding(.leading, 44)
                }
            }
        }
    }

    @ViewBuilder
    private var machinesSection: some View {
        if !filteredSessions.isEmpty {
            sectionHeader("Your machines")
            ForEach(filteredSessions) { session in
                sessionRow(session)
                if session.id != filteredSessions.last?.id {
                    Divider().overlay(Theme.panelRaised.opacity(0.5))
                        .padding(.leading, 44)
                }
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 4)
    }

    private func row(_ instance: CloudInstance) -> some View {
        let isSelected = instance.id == cloud.connectedInstance?.id
        let isTerminal = instance.state.isTerminal
        return Button {
            Task { await cloud.connectToInstance(instance) }
            dismiss()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "cloud")
                    .font(.system(size: 14))
                    .foregroundStyle(isSelected ? Theme.accent : Theme.textTertiary)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text(instance.displayName)
                        .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(subtitle(instance))
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 8)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .opacity(isTerminal ? 0.45 : 1)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Theme.panelRaised : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isTerminal || cloud.isBusy)
        .accessibilityLabel(instance.displayName)
        .accessibilityValue(instance.state.displayLabel)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    /// Disambiguating secondary line — distinguishes instances that share a repo
    /// (state · machine · short id).
    private func subtitle(_ instance: CloudInstance) -> String {
        "\(instance.state.displayLabel) · \(instance.machineType) · \(instance.id.suffix(6))"
    }

    /// A self-hosted (BYO) session row: a local-machine glyph, online/offline
    /// state, and a "Local" tag. Offline machines are disabled.
    private func sessionRow(_ session: CloudSession) -> some View {
        let isSelected = session.id == cloud.connectedSession?.id
        let isOnline = session.status.isOnline
        return Button {
            Task { await cloud.connectToSession(session) }
            dismiss()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "desktopcomputer")
                    .font(.system(size: 14))
                    .foregroundStyle(isSelected ? Theme.accent : Theme.textTertiary)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(session.displayName)
                            .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text("Local")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Theme.accent.opacity(0.15)))
                    }
                    HStack(spacing: 5) {
                        Circle()
                            .fill(isOnline ? Theme.added : Theme.textTertiary)
                            .frame(width: 6, height: 6)
                        Text("\(session.status.displayLabel) · \(session.id.suffix(6))")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textTertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                Spacer(minLength: 8)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .opacity(isOnline ? 1 : 0.45)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Theme.panelRaised : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isOnline || cloud.isBusy)
        .accessibilityLabel(session.displayName)
        .accessibilityValue("Local machine, \(session.status.displayLabel)")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .contextMenu {
            Button {
                renameText = session.name ?? ""
                renameTarget = session
            } label: {
                Label("Rename", systemImage: "pencil")
            }
        }
    }

    private var manageButton: some View {
        Button {
            // Mirror ConnectionSheet's pattern: dismiss this sheet first, then
            // present the cloud dashboard on the next runloop tick so the two
            // sheet presentations don't collide.
            dismiss()
            DispatchQueue.main.async { app.showCloudSheet = true }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 13))
                Text("Manage instances…")
                    .font(.system(size: 14, weight: .medium))
                Spacer()
            }
            .foregroundStyle(Theme.accent)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "cloud.badge.questionmark")
                .font(.system(size: 32))
                .foregroundStyle(Theme.textTertiary)
            Text(hasAny ? "No matching machines" : "Nothing to connect to yet")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
            if !hasAny {
                Text("Spawn a cloud instance from Manage, or run the korbo CLI to add your own machine.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textTertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var hasAny: Bool { !cloud.instances.isEmpty || !cloud.sessions.isEmpty }
}
