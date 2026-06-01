import SwiftUI

/// A searchable project switcher. A single opencode server can host many
/// projects (each an `?directory=` worktree/sandbox), so a dropdown doesn't
/// scale — this sheet lets the user filter by name or path and pick one,
/// re-scoping all sessions, files and git to that project.
struct ProjectPickerView: View {
    @EnvironmentObject private var store: KorboStore
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @FocusState private var searchFocused: Bool

    private var filtered: [OCProject] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return store.projects }
        return store.projects.filter {
            $0.name.localizedCaseInsensitiveContains(trimmed)
                || $0.scopeDirectory.localizedCaseInsensitiveContains(trimmed)
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
        }
        .background(Theme.panel)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var header: some View {
        HStack {
            Text("Switch Project")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            Text("\(store.projects.count)")
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
            TextField("Search projects", text: $query)
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
                ForEach(filtered) { project in
                    row(project)
                    if project.id != filtered.last?.id {
                        Divider().overlay(Theme.panelRaised.opacity(0.5))
                            .padding(.leading, 44)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    private func row(_ project: OCProject) -> some View {
        let isSelected = project.scopeDirectory == store.selectedProjectDirectory
        return Button {
            Task { await store.switchProject(to: project.scopeDirectory) }
            dismiss()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "folder")
                    .font(.system(size: 14))
                    .foregroundStyle(isSelected ? Theme.accent : Theme.textTertiary)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text(project.name)
                        .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Text(project.scopeDirectory)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.head)
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
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Theme.panelRaised : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(project.name)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "folder.badge.questionmark")
                .font(.system(size: 32))
                .foregroundStyle(Theme.textTertiary)
            Text("No matching projects")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
