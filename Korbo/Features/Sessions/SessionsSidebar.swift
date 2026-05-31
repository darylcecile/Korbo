import SwiftUI

struct SessionsSidebar: View {
    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var store: KorboStore

    @State private var showSearch = false
    @State private var collapsed: Set<String> = []
    @State private var renameTarget: OCSession?
    @State private var renameText: String = ""
    @State private var deleteTarget: OCSession?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            toolbar
            if showSearch { searchField }
            content
            Spacer(minLength: 0)
            footer
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.panel)
        .alert("Rename session", isPresented: renameBinding) {
            TextField("Title", text: $renameText)
            Button("Cancel", role: .cancel) { renameTarget = nil }
            Button("Save") {
                if let target = renameTarget {
                    let title = renameText
                    Task { await store.renameSession(target.id, title: title) }
                }
                renameTarget = nil
            }
        }
        .confirmationDialog(
            "Delete this session?",
            isPresented: deleteBinding,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let target = deleteTarget {
                    Task { await store.deleteSession(target.id) }
                }
                deleteTarget = nil
            }
            Button("Cancel", role: .cancel) { deleteTarget = nil }
        } message: {
            Text(deleteTarget?.title ?? "This session will be permanently removed.")
        }
    }

    private var renameBinding: Binding<Bool> {
        Binding(get: { renameTarget != nil }, set: { if !$0 { renameTarget = nil } })
    }
    private var deleteBinding: Binding<Bool> {
        Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } })
    }

    // MARK: Toolbar

    private var toolbar: some View {
        HStack(spacing: 16) {
            Button {
                Task { await store.createSession() }
            } label: { Image(systemName: "square.and.pencil") }
                .buttonStyle(.plain)
                .disabled(!store.status.isConnected)
            Image(systemName: "bubble.left.and.bubble.right")
            Image(systemName: "arrow.triangle.branch")
            Spacer()
            Button {
                Task { await store.reloadSessions() }
            } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.plain)
                .disabled(!store.status.isConnected)
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { showSearch.toggle() }
                if !showSearch { store.sessionQuery = "" }
            } label: {
                Image(systemName: showSearch ? "magnifyingglass.circle.fill" : "magnifyingglass")
            }
            .buttonStyle(.plain)
            .foregroundStyle(showSearch ? Theme.accent : Theme.textSecondary)
            .disabled(!store.status.isConnected)
        }
        .font(.system(size: 15, weight: .medium))
        .foregroundStyle(Theme.textSecondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textTertiary)
            TextField("Search sessions", text: $store.sessionQuery)
                .font(.system(size: 13))
                .foregroundStyle(Theme.textPrimary)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
            if !store.sessionQuery.isEmpty {
                Button { store.sessionQuery = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.panelRaised))
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        switch store.status {
        case .connected where store.sessions.isEmpty:
            emptyState(icon: "tray", title: "No sessions yet",
                       subtitle: "Start one with the compose button above.")
        case .connected:
            sessionList
        case .connecting:
            emptyState(icon: "arrow.triangle.2.circlepath", title: "Connecting…",
                       subtitle: store.servers.selectedServer?.normalizedURLString ?? "")
        case .failed(let message):
            disconnectedState(message: message)
        case .disconnected:
            disconnectedState(message: nil)
        }
    }

    @ViewBuilder
    private var sessionList: some View {
        let groups = store.sessionGroups
        if groups.isEmpty {
            emptyState(icon: "magnifyingglass", title: "No matches",
                       subtitle: store.sessionQuery.isEmpty ? "" : "No sessions match “\(store.sessionQuery)”.")
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(groups) { group in
                        sectionHeader(group)
                        if !collapsed.contains(group.id) {
                            ForEach(group.sessions) { session in
                                sessionRow(session)
                            }
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 16)
            }
        }
    }

    private func sessionRow(_ session: OCSession) -> some View {
        let selected = store.selectedSessionID == session.id
        let active = store.activeSessionIDs.contains(session.id)
        return Button {
            Task { await store.selectSession(session.id) }
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    if active {
                        Circle().fill(Theme.accent).frame(width: 6, height: 6)
                    }
                    Text(session.title ?? "Untitled session")
                        .font(.system(size: 13, weight: selected ? .semibold : .regular))
                        .lineLimit(1)
                        .foregroundStyle(selected ? Theme.accent : Theme.textPrimary)
                    Spacer(minLength: 8)
                    Text(RelativeTime.short(session.lastActivity))
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textTertiary)
                }
                metaRow(session)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(selected ? Theme.panelRaised : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu { rowMenu(session) }
    }

    @ViewBuilder
    private func metaRow(_ session: OCSession) -> some View {
        let project = session.projectName
        let adds = session.additions
        let dels = session.deletions
        if project != nil || adds > 0 || dels > 0 {
            HStack(spacing: 8) {
                if let project {
                    HStack(spacing: 3) {
                        Image(systemName: "folder").font(.system(size: 9))
                        Text(project).lineLimit(1)
                    }
                    .foregroundStyle(Theme.textTertiary)
                }
                Spacer(minLength: 4)
                if adds > 0 { Text("+\(adds)").foregroundStyle(Theme.added) }
                if dels > 0 { Text("-\(dels)").foregroundStyle(Theme.removed) }
            }
            .font(.system(size: 10, weight: .medium))
        }
    }

    @ViewBuilder
    private func rowMenu(_ session: OCSession) -> some View {
        Button {
            renameText = session.title ?? ""
            renameTarget = session
        } label: { Label("Rename", systemImage: "pencil") }

        Button {
            Task { await store.setSessionArchived(session.id, archived: !session.isArchived) }
        } label: {
            Label(session.isArchived ? "Unarchive" : "Archive",
                  systemImage: session.isArchived ? "tray.and.arrow.up" : "archivebox")
        }

        Divider()

        Button(role: .destructive) {
            deleteTarget = session
        } label: { Label("Delete", systemImage: "trash") }
    }

    // MARK: States

    private func disconnectedState(message: String?) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 26))
                .foregroundStyle(Theme.textTertiary)
            Text("Not connected")
                .font(.system(size: 14, weight: .semibold))
            if let message {
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textTertiary)
                    .multilineTextAlignment(.center)
            }
            Button {
                app.showConnectionSheet = true
            } label: {
                Text("Configure connection")
                    .font(.system(size: 13, weight: .medium))
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Theme.accent.opacity(0.18)))
                    .foregroundStyle(Theme.accent)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.top, 40)
    }

    private func emptyState(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundStyle(Theme.textTertiary)
            Text(title).font(.system(size: 14, weight: .semibold))
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textTertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.top, 40)
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 18) {
            Button {
                app.showSettingsSheet = true
            } label: {
                HStack(spacing: 6) {
                    Circle().fill(statusColor).frame(width: 8, height: 8)
                    Image(systemName: "gearshape")
                }
            }
            .buttonStyle(.plain)
            Image(systemName: "questionmark.circle")
            Image(systemName: "info.circle")
            Spacer()
        }
        .font(.system(size: 14))
        .foregroundStyle(Theme.textTertiary)
        .padding(16)
    }

    private var statusColor: Color {
        switch store.status {
        case .connected: return Theme.added
        case .connecting: return Theme.accent
        case .failed: return Theme.removed
        case .disconnected: return Theme.textTertiary
        }
    }

    private func sectionHeader(_ group: SessionGroup) -> some View {
        let isCollapsed = collapsed.contains(group.id)
        return Button {
            withAnimation(.easeInOut(duration: 0.12)) {
                if isCollapsed { collapsed.remove(group.id) } else { collapsed.insert(group.id) }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                Text(group.title)
                Text("\(group.sessions.count)")
                    .foregroundStyle(Theme.textTertiary.opacity(0.7))
                Spacer()
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Theme.textTertiary)
            .padding(.horizontal, 8)
            .padding(.top, 10)
            .padding(.bottom, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
