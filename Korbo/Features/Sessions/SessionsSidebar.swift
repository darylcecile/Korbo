import SwiftUI
import UIKit

struct SessionsSidebar: View {
    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var store: KorboStore
    @Environment(\.openWindow) private var openWindow

    @State private var showSearch = false
    @State private var collapsed: Set<String> = []
    @State private var renameTarget: OCSession?
    @State private var renameText: String = ""
    @State private var deleteTarget: OCSession?
    @State private var shareItem: ShareURLItem?

    // Multi-select state
    @State private var isSelectMode = false
    @State private var selectedIDs: Set<String> = []
    @State private var showBulkDeleteConfirm = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            toolbar
            if showSearch { searchField }
            content
            Spacer(minLength: 0)
            if isSelectMode {
                bulkActionBar
            } else {
                footer
            }
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
        .sheet(item: $shareItem) { item in
            ActivityView(items: [URL(string: item.url) ?? item.url as Any])
        }
        .confirmationDialog(
            "Delete \(selectedIDs.count) session\(selectedIDs.count == 1 ? "" : "s")?",
            isPresented: $showBulkDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                Task { await bulkDelete() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently remove the selected sessions.")
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
            if isSelectMode {
                Button("Done") { exitSelectMode() }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.accent)
                Spacer()
                Text("\(selectedIDs.count) selected")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Button { selectAllVisible() } label: {
                    Text(allVisibleSelected ? "Deselect All" : "Select All")
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundStyle(Theme.accent)
            } else {
                Button {
                    Task { await store.createSession() }
                } label: { Image(systemName: "square.and.pencil") }
                    .buttonStyle(.plain)
                    .disabled(!store.status.isConnected)
                    .accessibilityLabel("New session")
                Spacer()
                Button {
                    Task { await store.reloadSessions() }
                } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.plain)
                    .disabled(!store.status.isConnected)
                    .accessibilityLabel("Refresh sessions")
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { app.toggleTerminal() }
                } label: {
                    Image(systemName: "terminal")
                }
                .buttonStyle(.plain)
                .foregroundStyle(app.showTerminal ? Theme.accent : Theme.textSecondary)
                .disabled(!store.status.isConnected)
                .accessibilityLabel("Toggle terminal")
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { showSearch.toggle() }
                    if !showSearch { store.sessionQuery = "" }
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .buttonStyle(.plain)
                .foregroundStyle(showSearch ? Theme.accent : Theme.textSecondary)
                .disabled(!store.status.isConnected)
                .accessibilityLabel("Search sessions")
                groupSortMenu
            }
        }
        .font(.system(size: 15, weight: .medium))
        .foregroundStyle(Theme.textSecondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var groupSortMenu: some View {
        Menu {
            Section("Group by") {
                ForEach(SessionGrouping.allCases) { g in
                    Button {
                        store.setSessionGrouping(g)
                    } label: {
                        Label(g.title, systemImage: store.sessionGrouping == g ? "checkmark" : g.icon)
                    }
                }
            }
            Section("Sort") {
                ForEach(SessionSort.allCases) { s in
                    Button {
                        store.setSessionSort(s)
                    } label: {
                        Label(s.title, systemImage: store.sessionSort == s ? "checkmark" : s.icon)
                    }
                }
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease.circle")
        }
        .buttonStyle(.plain)
        .foregroundStyle(store.sessionGrouping != .recency ? Theme.accent : Theme.textSecondary)
        .disabled(!store.status.isConnected)
        .accessibilityLabel("Filter and sort sessions")
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
                .accessibilityLabel("Clear search")
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
            List {
                ForEach(groups) { group in
                    Section {
                        if !collapsed.contains(group.id) {
                            ForEach(group.sessions) { session in
                                sessionRow(session)
                                    .id("\(session.id)|\(session.isShared)|\(session.isArchived)|\(store.isPinned(session.id))")
                                    .listRowInsets(EdgeInsets(top: 1, leading: 8, bottom: 1, trailing: 8))
                                    .listRowBackground(Color.clear)
                                    .listRowSeparator(.hidden)
                                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                        if !isSelectMode { archiveSwipeButton(session) }
                                    }
                                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                        if !isSelectMode { deleteSwipeButton(session) }
                                    }
                            }
                        }
                    } header: {
                        sectionHeader(group)
                            .listRowInsets(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8))
                            .listRowBackground(Color.clear)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Theme.panel)
            .environment(\.defaultMinListRowHeight, 0)
        }
    }

    /// Leading swipe: archive or unarchive via the existing API-backed store
    /// method (mirrors the row context menu and bulk-archive action).
    @ViewBuilder
    private func archiveSwipeButton(_ session: OCSession) -> some View {
        Button {
            Task { await store.setSessionArchived(session.id, archived: !session.isArchived) }
        } label: {
            Label(session.isArchived ? "Unarchive" : "Archive",
                  systemImage: session.isArchived ? "tray.and.arrow.up" : "archivebox")
        }
        .tint(Theme.accent)
    }

    /// Trailing swipe: route through the delete confirmation dialog rather than
    /// deleting immediately. A full swipe sets `deleteTarget`, surfacing the
    /// destructive confirmation before `store.deleteSession` runs.
    @ViewBuilder
    private func deleteSwipeButton(_ session: OCSession) -> some View {
        Button(role: .destructive) {
            deleteTarget = session
        } label: {
            Label("Delete", systemImage: "trash")
        }
        .tint(Theme.removed)
    }

    private func sessionRow(_ session: OCSession) -> some View {
        let selected = store.selectedSessionID == session.id
        let active = store.activeSessionIDs.contains(session.id)
        let pinned = store.isPinned(session.id)
        let isChecked = selectedIDs.contains(session.id)
        return Button {
            if isSelectMode {
                toggleSelection(session.id)
            } else {
                Task { await store.selectSession(session.id) }
                app.showChat()
                if app.layoutMode.isCompact { app.sessionsDrawerOpen = false }
            }
        } label: {
            HStack(spacing: 8) {
                if isSelectMode {
                    Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20))
                        .foregroundStyle(isChecked ? Theme.accent : Theme.textTertiary)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        if active {
                            Circle().fill(Theme.accent).frame(width: 6, height: 6)
                                .accessibilityHidden(true)
                        }
                        Text(session.title ?? "Untitled session")
                            .font(.system(size: 13, weight: selected ? .semibold : .regular))
                            .lineLimit(1)
                            .foregroundStyle(selected ? Theme.accent : Theme.textPrimary)
                        if pinned {
                            Image(systemName: "pin.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(Theme.textTertiary)
                                .accessibilityHidden(true)
                        }
                        if session.isShared {
                            Image(systemName: "link")
                                .font(.system(size: 9))
                                .foregroundStyle(Theme.accent)
                                .accessibilityHidden(true)
                        }
                        Spacer(minLength: 8)
                        Text(RelativeTime.short(session.lastActivity))
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    metaRow(session)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill((selected && !isSelectMode) ? Theme.panelRaised : (isChecked ? Theme.accent.opacity(0.1) : .clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu { if !isSelectMode { rowMenu(session) } }
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
                            .accessibilityHidden(true)
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
            withAnimation(.easeInOut(duration: 0.15)) {
                isSelectMode = true
                selectedIDs = [session.id]
            }
        } label: { Label("Select", systemImage: "checkmark.circle") }

        Button {
            openWindow(value: session.id)
        } label: { Label("Open in New Window", systemImage: "macwindow.badge.plus") }

        Divider()

        Button {
            renameText = session.title ?? ""
            renameTarget = session
        } label: { Label("Rename", systemImage: "pencil") }

        Button {
            store.togglePin(session.id)
        } label: {
            Label(store.isPinned(session.id) ? "Unpin" : "Pin",
                  systemImage: store.isPinned(session.id) ? "pin.slash" : "pin")
        }

        Button {
            Task { await store.forkSession(session.id) }
        } label: { Label("Duplicate", systemImage: "plus.square.on.square") }

        if session.isShared {
            Button {
                if let url = session.shareURL { shareItem = ShareURLItem(url: url) }
            } label: { Label("Share link", systemImage: "square.and.arrow.up") }
            Button {
                Task { await store.unshareSession(session.id) }
            } label: { Label("Stop sharing", systemImage: "person.crop.circle.badge.xmark") }
        } else {
            Button {
                Task {
                    if let url = await store.shareSession(session.id) {
                        shareItem = ShareURLItem(url: url)
                    }
                }
            } label: { Label("Share link", systemImage: "square.and.arrow.up") }
        }

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
            Menu {
                Section("Server") {
                    ForEach(store.servers.servers) { server in
                        Button {
                            Task { await store.switchServer(to: server.id) }
                        } label: {
                            if server.id == store.servers.selectedServerID {
                                Label(server.name, systemImage: "checkmark")
                            } else {
                                Text(server.name)
                            }
                        }
                    }
                }
                Divider()
                Button { app.showConnectionSheet = true } label: {
                    Label("Manage servers…", systemImage: "server.rack")
                }
            } label: {
                HStack(spacing: 6) {
                    Circle().fill(statusColor).frame(width: 8, height: 8)
                    Text(store.servers.selectedServer?.name ?? "Server")
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 9))
                }
            }
            .menuStyle(.borderlessButton)
            .accessibilityLabel("Server \(store.servers.selectedServer?.name ?? "none"), \(store.status.label)")
            .accessibilityHint("Switch or manage servers")

            Spacer()

            Button {
                app.showSettingsSheet = true
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
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
                    .accessibilityHidden(true)
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
        .accessibilityLabel("\(group.title), \(group.sessions.count) sessions, \(isCollapsed ? "collapsed" : "expanded")")
    }

    // MARK: - Multi-Select Helpers

    private var allVisibleIDs: Set<String> {
        Set(store.sessionGroups.flatMap { $0.sessions.map(\.id) })
    }

    private var allVisibleSelected: Bool {
        let visible = allVisibleIDs
        return !visible.isEmpty && visible.isSubset(of: selectedIDs)
    }

    private func toggleSelection(_ id: String) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }

    private func selectAllVisible() {
        let visible = allVisibleIDs
        if allVisibleSelected {
            selectedIDs.subtract(visible)
        } else {
            selectedIDs.formUnion(visible)
        }
    }

    private func exitSelectMode() {
        withAnimation(.easeInOut(duration: 0.15)) {
            isSelectMode = false
            selectedIDs.removeAll()
        }
    }

    // MARK: - Bulk Action Bar

    private var bulkActionBar: some View {
        HStack(spacing: 0) {
            bulkActionButton(icon: "pin", label: bulkPinLabel) {
                bulkTogglePin()
            }
            bulkActionButton(icon: "archivebox", label: bulkArchiveLabel) {
                Task { await bulkToggleArchive() }
            }
            bulkActionButton(icon: "trash", label: "Delete", destructive: true) {
                showBulkDeleteConfirm = true
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 10)
        .background(Theme.panelRaised)
        .disabled(selectedIDs.isEmpty)
        .opacity(selectedIDs.isEmpty ? 0.5 : 1)
    }

    private func bulkActionButton(icon: String, label: String, destructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                Text(label)
                    .font(.system(size: 11, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .foregroundStyle(destructive ? Theme.removed : Theme.textSecondary)
        }
        .buttonStyle(.plain)
    }

    // Returns "Pin" if majority are unpinned, else "Unpin"
    private var bulkPinLabel: String {
        let pinnedCount = selectedIDs.filter { store.isPinned($0) }.count
        return pinnedCount > selectedIDs.count / 2 ? "Unpin" : "Pin"
    }

    // Returns "Archive" if majority are unarchived, else "Unarchive"
    private var bulkArchiveLabel: String {
        let archivedCount = selectedIDs.filter { id in
            store.sessions.first { $0.id == id }?.isArchived == true
        }.count
        return archivedCount > selectedIDs.count / 2 ? "Unarchive" : "Archive"
    }

    // MARK: - Bulk Actions (reuse single-session store methods)

    private func bulkTogglePin() {
        let shouldPin = bulkPinLabel == "Pin"
        for id in selectedIDs {
            store.setPinned(id, pinned: shouldPin)
        }
        exitSelectMode()
    }

    private func bulkToggleArchive() async {
        let shouldArchive = bulkArchiveLabel == "Archive"
        for id in selectedIDs {
            await store.setSessionArchived(id, archived: shouldArchive)
        }
        exitSelectMode()
    }

    private func bulkDelete() async {
        for id in selectedIDs {
            await store.deleteSession(id)
        }
        exitSelectMode()
    }
}

/// Identifiable wrapper so a freshly-generated share URL can drive a
/// `.sheet(item:)` presentation of the native iOS share sheet.
struct ShareURLItem: Identifiable {
    let id = UUID()
    let url: String
}

/// Hosts a `UIActivityViewController` so share links open in the system share
/// sheet (AirDrop, Messages, copy, etc.) instead of a copy-only alert.
struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
