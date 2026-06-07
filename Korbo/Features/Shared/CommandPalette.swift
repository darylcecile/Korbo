import SwiftUI

/// A single runnable entry in the command palette.
private struct PaletteItem: Identifiable {
    let id: String
    let icon: String
    let title: String
    let subtitle: String?
    let group: String
    let action: () -> Void
}

/// ⌘P / ⌘K command palette: fuzzy-jump to sessions and files, run opencode slash
/// commands, and fire navigation actions. Keyboard-driven (↑/↓ to move, ↵ to run,
/// Esc to dismiss) with pointer/touch fallbacks.
struct CommandPalette: View {
    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var store: KorboStore
    @EnvironmentObject private var cloud: CloudStore

    @State private var query = ""
    @State private var selection = 0
    @State private var fileResults: [String] = []
    @State private var searchTask: Task<Void, Never>?
    @FocusState private var fieldFocused: Bool

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture { close() }

            card
                .frame(maxWidth: 640, maxHeight: 480)
                .background(Theme.panelRaised)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.border))
                .shadow(color: .black.opacity(0.4), radius: 30, y: 12)
                .padding(.top, 72)
                .padding(.horizontal, 24)
        }
        .onAppear { fieldFocused = true }
        .onChange(of: query) { _, q in
            selection = 0
            scheduleSearch(q)
        }
    }

    private var card: some View {
        VStack(spacing: 0) {
            field
            Divider().overlay(Theme.border)
            results
        }
    }

    private var field: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Theme.textTertiary)
            TextField("Search sessions, files, commands…", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 16))
                .focused($fieldFocused)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.go)
                .onSubmit(runSelected)
                .onKeyPress(.downArrow) { move(1); return .handled }
                .onKeyPress(.upArrow) { move(-1); return .handled }
                .onKeyPress(.escape) { close(); return .handled }
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.textTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private var results: some View {
        let list = items
        if list.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 22))
                Text(store.status.isConnected ? "No matches" : "Not connected")
                    .font(.system(size: 13))
            }
            .foregroundStyle(Theme.textTertiary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.vertical, 40)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                        ForEach(Array(list.enumerated()), id: \.element.id) { index, item in
                            if index == 0 || list[index - 1].group != item.group {
                                sectionHeader(item.group)
                            }
                            row(item, index: index)
                                .id(index)
                        }
                    }
                }
                .onChange(of: selection) { _, sel in
                    withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(sel, anchor: .center) }
                }
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Theme.textTertiary)
            .padding(.horizontal, 16)
            .padding(.top, 12).padding(.bottom, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.panelRaised)
    }

    private func row(_ item: PaletteItem, index: Int) -> some View {
        Button { item.action() } label: {
            HStack(spacing: 12) {
                Image(systemName: item.icon)
                    .font(.system(size: 14))
                    .frame(width: 20)
                    .foregroundStyle(index == selection ? Theme.accent : Theme.textSecondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title)
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    if let subtitle = item.subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textTertiary)
                            .lineLimit(1).truncationMode(.middle)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
            .background(index == selection ? Theme.accent.opacity(0.16) : .clear)
        }
        .buttonStyle(.plain)
        .onHover { hovering in if hovering { selection = index } }
    }

    // MARK: - Items

    private var items: [PaletteItem] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        var out: [PaletteItem] = []
        out += actionItems.filter { q.isEmpty || $0.title.lowercased().contains(q) }
        out += sessionItems(q)
        out += instanceItems(q)
        out += projectItems(q)
        out += fileItems
        out += commandItems(q)
        return out
    }

    private var actionItems: [PaletteItem] {
        var out: [PaletteItem] = [
            PaletteItem(id: "act-new", icon: "square.and.pencil", title: "New session",
                        subtitle: nil, group: "Actions") { perform { Task { await store.createSession() } } },
            PaletteItem(id: "act-focus", icon: "text.cursor", title: "Focus message composer",
                        subtitle: nil, group: "Actions") { perform { app.focusComposer() } },
            PaletteItem(id: "act-toggle", icon: "sidebar.right", title: "Toggle right panel",
                        subtitle: nil, group: "Actions") { perform { app.showRightSidebar.toggle() } },
            PaletteItem(id: "act-git", icon: "arrow.triangle.branch", title: "Show Git",
                        subtitle: nil, group: "Actions") { perform { app.showRightTab(.git) } },
            PaletteItem(id: "act-files", icon: "folder", title: "Show Files",
                        subtitle: nil, group: "Actions") { perform { app.showRightTab(.files) } },
            PaletteItem(id: "act-term", icon: "terminal", title: "Toggle Terminal",
                        subtitle: nil, group: "Actions") { perform { app.toggleTerminal() } },
            PaletteItem(id: "act-context", icon: "doc.text.magnifyingglass", title: "Show Context",
                        subtitle: nil, group: "Actions") { perform { app.showRightTab(.context) } },
            PaletteItem(id: "act-settings", icon: "gearshape", title: "Open Settings",
                        subtitle: nil, group: "Actions") { perform { app.showSettingsSheet = true } },
            PaletteItem(id: "act-server", icon: "server.rack", title: "Change server…",
                        subtitle: nil, group: "Actions") { perform { app.showConnectionSheet = true } },
            PaletteItem(id: "act-reload", icon: "arrow.clockwise", title: "Reload sessions",
                        subtitle: nil, group: "Actions") { perform { Task { await store.reloadSessions() } } },
            PaletteItem(id: "act-shortcuts", icon: "keyboard", title: "Keyboard Shortcuts",
                        subtitle: "⌘/", group: "Actions") { perform { app.showShortcutsCheatSheet = true } },
        ]
        if store.isGenerating {
            out.insert(
                PaletteItem(id: "act-stop", icon: "stop.fill", title: "Stop generation",
                            subtitle: nil, group: "Actions") { perform { Task { await store.abort() } } },
                at: 1)
        }
        return out
    }

    private func sessionItems(_ q: String) -> [PaletteItem] {
        let roots = store.sessions.filter { ($0.parentID ?? "").isEmpty }
        let filtered = q.isEmpty
            ? Array(roots.prefix(6))
            : roots.filter {
                ($0.title ?? "").lowercased().contains(q)
                    || ($0.projectName ?? "").lowercased().contains(q)
            }
        return filtered.prefix(8).map { session in
            let isActive = session.id == store.selectedSessionID
            return PaletteItem(
                id: "ses-\(session.id)",
                icon: isActive ? "bubble.left.fill" : "bubble.left",
                title: session.title?.isEmpty == false ? session.title! : "Untitled session",
                subtitle: session.projectName,
                group: "Sessions"
            ) { perform { Task { await store.selectSession(session.id) } } }
        }
    }

    /// Cloud-instance switcher entries. Lets the user jump to another provisioned
    /// instance (labelled by repo) without leaving the keyboard. Matches on the
    /// repo/id and the synthetic keyword "switch instance" so typing "switch" or
    /// "instance" surfaces them. Only shown when signed into Cloud.
    private func instanceItems(_ q: String) -> [PaletteItem] {
        guard cloud.isSignedIn else { return [] }
        let connectedID = cloud.connectedInstance?.id
        let filtered = q.isEmpty
            ? Array(cloud.instances.prefix(6))
            : cloud.instances.filter {
                $0.displayName.lowercased().contains(q)
                    || ($0.repo ?? "").lowercased().contains(q)
                    || $0.id.lowercased().contains(q)
                    || "switch to instance".contains(q)
            }
        return filtered.prefix(8).map { instance in
            let isConnected = instance.id == connectedID
            return PaletteItem(
                id: "inst-\(instance.id)",
                icon: isConnected ? "cloud.fill" : "cloud",
                title: "Switch to \(instance.displayName)",
                subtitle: "\(instance.state.displayLabel) · \(instance.machineType)",
                group: "Switch to instance"
            ) { perform { Task { await cloud.connectToInstance(instance) } } }
        }
    }

    /// Project switcher entries: a single opencode server can host several
    /// projects (each an `?directory=` worktree). Lets the user re-scope sessions,
    /// files and git to another project from the keyboard. Matches on name/path
    /// and the synthetic keyword "switch project". Only on a local/LAN server (not
    /// a single-workspace cloud instance) that exposes more than one project.
    private func projectItems(_ q: String) -> [PaletteItem] {
        guard cloud.connectedInstance == nil, store.projects.count > 1 else { return [] }
        let selectedDir = store.selectedProjectDirectory
        let filtered = q.isEmpty
            ? Array(store.projects.prefix(6))
            : store.projects.filter {
                $0.name.lowercased().contains(q)
                    || $0.scopeDirectory.lowercased().contains(q)
                    || "switch project".contains(q)
            }
        return filtered.prefix(8).map { project in
            let isSelected = project.scopeDirectory == selectedDir
            return PaletteItem(
                id: "proj-\(project.id)",
                icon: isSelected ? "folder.fill" : "folder",
                title: "Switch to \(project.name)",
                subtitle: project.scopeDirectory,
                group: "Switch project"
            ) { perform { Task { await store.switchProject(to: project.scopeDirectory) } } }
        }
    }

    private var fileItems: [PaletteItem] {
        fileResults.prefix(8).map { path in
            PaletteItem(id: "file-\(path)", icon: "doc", title: basename(path),
                        subtitle: path, group: "Files") {
                perform {
                    app.showRightTab(.files)
                    Task { await store.openFile(path) }
                }
            }
        }
    }

    private func commandItems(_ q: String) -> [PaletteItem] {
        let filtered = q.isEmpty
            ? []
            : store.commands.filter {
                $0.name.lowercased().contains(q)
                    || ($0.description ?? "").lowercased().contains(q)
            }
        return filtered.prefix(8).map { command in
            PaletteItem(id: "cmd-\(command.name)", icon: "chevron.left.forwardslash.chevron.right",
                        title: "/\(command.name)", subtitle: command.description, group: "Commands") {
                perform {
                    app.composerDraft = "/\(command.name) "
                    app.focusComposer()
                }
            }
        }
    }

    // MARK: - Behaviour

    private func move(_ delta: Int) {
        let count = items.count
        guard count > 0 else { return }
        selection = (selection + delta + count) % count
    }

    private func runSelected() {
        let list = items
        guard list.indices.contains(selection) else { return }
        list[selection].action()
    }

    /// Dismiss the palette, then run the entry's effect.
    private func perform(_ action: () -> Void) {
        close()
        action()
    }

    private func close() {
        searchTask?.cancel()
        app.showCommandPalette = false
    }

    private func scheduleSearch(_ raw: String) {
        searchTask?.cancel()
        let q = raw.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2 else { fileResults = []; return }
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard !Task.isCancelled else { return }
            let results = await store.paletteFileSearch(q)
            guard !Task.isCancelled else { return }
            fileResults = results
        }
    }

    private func basename(_ path: String) -> String {
        path.split(separator: "/").last.map(String.init) ?? path
    }
}
