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

    private var filtered: [CloudInstance] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return cloud.instances }
        return cloud.instances.filter {
            $0.displayName.localizedCaseInsensitiveContains(trimmed)
                || ($0.repo ?? "").localizedCaseInsensitiveContains(trimmed)
                || $0.id.localizedCaseInsensitiveContains(trimmed)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            searchField
            Divider().overlay(Theme.panelRaised)
            if filtered.isEmpty {
                emptyState
            } else {
                list
            }
            Divider().overlay(Theme.panelRaised)
            manageButton
        }
        .background(Theme.panel)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task { if cloud.isSignedIn { await cloud.refreshInstances() } }
    }

    private var header: some View {
        HStack {
            Text("Switch Instance")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            Text("\(cloud.instances.count)")
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

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(filtered) { instance in
                    row(instance)
                    if instance.id != filtered.last?.id {
                        Divider().overlay(Theme.panelRaised.opacity(0.5))
                            .padding(.leading, 44)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
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
            Text(cloud.instances.isEmpty ? "No instances yet" : "No matching instances")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
            if cloud.instances.isEmpty {
                Text("Spawn one from Manage instances.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textTertiary)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
