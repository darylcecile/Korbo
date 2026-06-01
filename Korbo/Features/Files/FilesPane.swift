import SwiftUI

/// Right-pane **Files** tab. opencode's server exposes a read-only file surface
/// (`/file`, `/file/content`, `/find/file`), so this panel is a lazy, collapsible
/// workspace browser with fuzzy path search. The file viewer now lives in the
/// wide centre pane (like the terminal) for better readability.
struct FilesPane: View {
    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var store: KorboStore

    var body: some View {
        browser
            .task { await store.loadFileRootIfNeeded() }
    }

    // MARK: Browser (search + tree)

    private var browser: some View {
        VStack(spacing: 0) {
            searchBar
            Divider().overlay(Theme.border)
            if store.fileQuery.isEmpty {
                tree
            } else {
                searchResults
            }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textTertiary)
            TextField("Search files", text: $store.fileQuery)
                .font(.system(size: 13))
                .foregroundStyle(Theme.textPrimary)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .onChange(of: store.fileQuery) { _ in store.scheduleFileSearch() }
            if !store.fileQuery.isEmpty {
                Button { store.fileQuery = ""; store.scheduleFileSearch() } label: {
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
        .padding(12)
    }

    // MARK: Tree

    @ViewBuilder
    private var tree: some View {
        let rows = flattenedRows()
        if rows.isEmpty {
            centeredState {
                if store.loadingDirs.contains(".") {
                    ProgressView().tint(Theme.textTertiary)
                    Text("Loading files…")
                        .font(.system(size: 12)).foregroundStyle(Theme.textTertiary)
                } else {
                    Image(systemName: "folder")
                        .font(.system(size: 30)).foregroundStyle(Theme.textTertiary)
                    Text("No files").font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(rows) { row in
                        treeRow(row)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func treeRow(_ row: FileRow) -> some View {
        let node = row.node
        let isOpen = store.expandedDirs.contains(node.path)
        let isLoading = store.loadingDirs.contains(node.path)
        return Button {
            Task {
                if node.isDirectory { await store.toggleDir(node) }
                else { await openFileInCenter(node.path) }
            }
        } label: {
            HStack(spacing: 6) {
                if node.isDirectory {
                    Image(systemName: isOpen ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Theme.textTertiary)
                        .frame(width: 10)
                        .accessibilityHidden(true)
                } else {
                    Spacer().frame(width: 10)
                }
                Image(systemName: icon(for: node, isOpen: isOpen))
                    .font(.system(size: 12))
                    .foregroundStyle(node.isDirectory ? Theme.accent : Theme.textSecondary)
                    .frame(width: 16)
                    .accessibilityHidden(true)
                Text(node.name)
                    .font(.system(size: 13))
                    .foregroundStyle(node.ignored ? Theme.textTertiary : Theme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 4)
                if isLoading {
                    ProgressView().controlSize(.mini).tint(Theme.textTertiary)
                }
            }
            .padding(.leading, CGFloat(row.depth) * 14 + 12)
            .padding(.trailing, 12)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Search results

    @ViewBuilder
    private var searchResults: some View {
        if store.isSearchingFiles && store.fileSearchResults.isEmpty {
            centeredState {
                ProgressView().tint(Theme.textTertiary)
                Text("Searching…").font(.system(size: 12)).foregroundStyle(Theme.textTertiary)
            }
        } else if store.fileSearchResults.isEmpty {
            centeredState {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 30)).foregroundStyle(Theme.textTertiary)
                Text("No matches").font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
            }
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(store.fileSearchResults, id: \.self) { path in
                        Button { Task { await openFileInCenter(path) } } label: {
                            resultRow(path)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func resultRow(_ path: String) -> some View {
        let (dir, name) = splitPath(path)
        return HStack(spacing: 8) {
            Image(systemName: icon(forName: name))
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 16)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1).truncationMode(.middle)
                if !dir.isEmpty {
                    Text(dir)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1).truncationMode(.head)
                }
            }
            Spacer(minLength: 4)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
    }

    // MARK: Helpers

    /// Open a file and switch the center pane to the file viewer.
    private func openFileInCenter(_ path: String) async {
        await store.openFile(path)
        app.showFilesCenter()
    }

    private func centeredState<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        VStack(spacing: 10) { Spacer(); content(); Spacer() }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(24)
    }

    /// Flatten the lazily-loaded tree into rows honouring `expandedDirs`.
    private func flattenedRows() -> [FileRow] {
        var rows: [FileRow] = []
        func walk(_ path: String, depth: Int) {
            guard let children = store.fileChildren[path] else { return }
            for node in children {
                rows.append(FileRow(node: node, depth: depth))
                if node.isDirectory && store.expandedDirs.contains(node.path) {
                    walk(node.path, depth: depth + 1)
                }
            }
        }
        walk(".", depth: 0)
        return rows
    }

    private func icon(for node: OCFileNode, isOpen: Bool) -> String {
        node.isDirectory ? (isOpen ? "folder.fill" : "folder") : icon(forName: node.name)
    }

    private func icon(forName name: String) -> String {
        switch (name as NSString).pathExtension.lowercased() {
        case "swift": return "swift"
        case "md", "markdown", "txt": return "doc.text"
        case "json", "yml", "yaml", "toml", "plist", "xml": return "curlybraces"
        case "png", "jpg", "jpeg", "gif", "svg", "webp", "heic", "pdf": return "photo"
        case "sh", "bash", "zsh": return "terminal"
        case "js", "ts", "tsx", "jsx", "py", "rb", "go", "rs", "c", "cpp", "h", "hpp", "java", "kt":
            return "chevron.left.forwardslash.chevron.right"
        default:
            return name.hasPrefix(".") ? "gearshape" : "doc"
        }
    }

    private func splitPath(_ path: String) -> (dir: String, name: String) {
        guard let slash = path.lastIndex(of: "/") else { return ("", path) }
        return (String(path[..<slash]), String(path[path.index(after: slash)...]))
    }
}

/// One flattened tree entry plus its indentation depth.
private struct FileRow: Identifiable {
    let node: OCFileNode
    let depth: Int
    var id: String { node.path }
}


// MARK: - File viewer (read-only, tabbed, syntax-highlighted)

struct FindMatch: Equatable { let line: Int; let occ: Int }

/// Read-only viewer with a tab strip, syntax highlighting, find and go-to-line.
/// Editing is not part of the opencode REST API, so this stays read-only.
/// Now lives in the centre pane for better width; the back button returns to chat.
struct FileViewer: View {
    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var store: KorboStore

    private static let maxLines = 2000

    // Highlight cache (whole-file tokenisation is reused across find keystrokes).
    @State private var lines: [[CodeRun]] = []
    @State private var renderedKey: String = ""
    @State private var truncated = false

    // Find / go-to-line state (reset per tab).
    @State private var findActive = false
    @State private var findQuery = ""
    @State private var matches: [FindMatch] = []
    @State private var current = 0
    @State private var gotoText = ""
    @FocusState private var findFocused: Bool

    private var activeKey: String {
        let f = store.activeFile
        return (f?.path ?? "") + "#" + String(f?.content?.content?.count ?? -1)
    }

    var body: some View {
        VStack(spacing: 0) {
            tabStrip
            Divider().overlay(Theme.border)
            toolbar
            Divider().overlay(Theme.border)
            content
        }
        .onChange(of: store.activeFilePath) { _ in resetFind(); refreshHighlight() }
        .onChange(of: activeKey) { _ in refreshHighlight() }
        .onChange(of: findQuery) { _ in recomputeMatches() }
        .onChange(of: store.openFiles.isEmpty) { empty in
            if empty { returnToChat() }
        }
        .onAppear { refreshHighlight() }
    }

    // MARK: Tab strip

    private var tabStrip: some View {
        HStack(spacing: 6) {
            Button { returnToChat() } label: {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
            }
            .buttonStyle(.plain)
            .help("Return to chat and show file browser")
            .accessibilityLabel("Return to chat")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(store.openFiles) { file in
                        tab(file)
                    }
                }
                .padding(.vertical, 6)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 40)
    }

    private func returnToChat() {
        app.showChat()
        app.showRightTab(.files)
    }

    private func tab(_ file: OpenFile) -> some View {
        let isActive = file.path == store.activeFilePath
        let name = (file.path as NSString).lastPathComponent
        return HStack(spacing: 6) {
            Button { store.focusFile(file.path) } label: {
                HStack(spacing: 5) {
                    if file.isLoading {
                        ProgressView().controlSize(.mini).tint(Theme.textTertiary)
                    }
                    Text(name)
                        .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                        .foregroundStyle(isActive ? Theme.textPrimary : Theme.textSecondary)
                        .lineLimit(1)
                }
            }
            .buttonStyle(.plain)
            Button { store.closeFile(file.path) } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Theme.textTertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close \(name)")
        }
        .padding(.leading, 10)
        .padding(.trailing, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(isActive ? Theme.panelRaised : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .strokeBorder(isActive ? Theme.border : Color.clear, lineWidth: 1)
        )
    }

    // MARK: Toolbar (find + go-to-line)

    private var toolbar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12)).foregroundStyle(Theme.textTertiary)
            TextField("Find in file", text: $findQuery)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textPrimary)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .focused($findFocused)
                .frame(maxWidth: 220, alignment: .leading)

            if !findQuery.isEmpty {
                Text(matches.isEmpty ? "0/0" : "\(current + 1)/\(matches.count)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.textTertiary)
                navButton("chevron.up") { step(-1) }
                    .accessibilityLabel("Previous match")
                navButton("chevron.down") { step(1) }
                    .accessibilityLabel("Next match")
                Button { findQuery = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12)).foregroundStyle(Theme.textTertiary)
                }.buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
            }

            Spacer(minLength: 8)

            Image(systemName: "number")
                .font(.system(size: 11)).foregroundStyle(Theme.textTertiary)
            TextField("Line", text: $gotoText)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Theme.textPrimary)
                .textFieldStyle(.plain)
                .keyboardType(.numberPad)
                .frame(width: 52)
                .onSubmit { gotoLine() }
            Button { gotoLine() } label: {
                Text("Go").font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            }.buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
    }

    private func navButton(_ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(matches.isEmpty ? Theme.textTertiary : Theme.textSecondary)
        }
        .buttonStyle(.plain)
        .disabled(matches.isEmpty)
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if let file = store.activeFile {
            if file.isLoading && file.content == nil {
                centeredNotice(spinner: true, icon: "", text: "Loading…")
            } else if let c = file.content {
                if c.isBinary {
                    centeredNotice(spinner: false, icon: "doc.badge.ellipsis",
                                   text: "Binary file — preview unavailable")
                } else {
                    codeView
                }
            } else {
                centeredNotice(spinner: false, icon: "exclamationmark.triangle",
                               text: "Couldn't load file")
            }
        } else {
            Color.clear
        }
    }

    private var codeView: some View {
        let gutter = max(2, String(lines.count).count)
        let gutterWidth = CGFloat(gutter) * 7.4 + 4
        return ScrollViewReader { proxy in
            ScrollView([.vertical, .horizontal]) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { idx, runs in
                        lineRow(idx: idx, runs: runs, gutterWidth: gutterWidth)
                            .id(idx)
                    }
                    if truncated {
                        Text("… file truncated at \(Self.maxLines) lines")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Theme.textTertiary)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                    }
                }
                .padding(.vertical, 6)
            }
            .onChange(of: current) { _ in scrollToCurrent(proxy) }
            .onChange(of: scrollRequest) { target in
                guard let target else { return }
                withAnimation(.easeInOut(duration: 0.2)) { proxy.scrollTo(target, anchor: .center) }
            }
        }
    }

    // A one-shot scroll target consumed by codeView's onChange.
    @State private var scrollRequest: Int? = nil

    private func lineRow(idx: Int, runs: [CodeRun], gutterWidth: CGFloat) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(String(idx + 1))
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Theme.textTertiary)
                .frame(width: gutterWidth, alignment: .trailing)
            Text(attributed(idx: idx, runs: runs))
                .font(.system(size: 12, design: .monospaced))
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 1)
    }

    /// Build the coloured line, then overlay find-match backgrounds.
    private func attributed(idx: Int, runs: [CodeRun]) -> AttributedString {
        guard !runs.isEmpty else { return AttributedString(" ") }
        var s = AttributedString()
        for run in runs {
            var piece = AttributedString(run.text)
            piece.foregroundColor = run.kind.color
            s += piece
        }
        guard !findQuery.isEmpty else { return s }
        let active = matches.indices.contains(current) ? matches[current] : nil
        var start = s.startIndex
        var k = 0
        while let r = s[start...].range(of: findQuery, options: .caseInsensitive) {
            let isActive = (active?.line == idx && active?.occ == k)
            s[r].backgroundColor = isActive ? Theme.accent : Theme.accent.opacity(0.28)
            if isActive { s[r].foregroundColor = Theme.bg }
            start = r.upperBound
            k += 1
        }
        return s
    }

    private func centeredNotice(spinner: Bool, icon: String, text: String) -> some View {
        VStack(spacing: 10) {
            Spacer()
            if spinner {
                ProgressView().tint(Theme.textTertiary)
            } else {
                Image(systemName: icon).font(.system(size: 30)).foregroundStyle(Theme.textTertiary)
            }
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    // MARK: Logic

    private func refreshHighlight() {
        guard let file = store.activeFile, let content = file.content, !content.isBinary,
              let text = content.content else {
            lines = []; truncated = false; renderedKey = activeKey; return
        }
        if renderedKey == activeKey && !lines.isEmpty { return }
        let lang = SyntaxHighlighter.language(forPath: file.path)
        var tokenised = SyntaxHighlighter.highlight(text, language: lang)
        truncated = tokenised.count > Self.maxLines
        if truncated { tokenised = Array(tokenised.prefix(Self.maxLines)) }
        lines = tokenised
        renderedKey = activeKey
        recomputeMatches()
    }

    private func recomputeMatches() {
        guard !findQuery.isEmpty else { matches = []; current = 0; return }
        let q = findQuery.lowercased()
        var result: [FindMatch] = []
        for (idx, runs) in lines.enumerated() {
            let text = runs.map(\.text).joined().lowercased()
            guard !text.isEmpty else { continue }
            var range = text.startIndex..<text.endIndex
            var k = 0
            while let r = text.range(of: q, range: range) {
                result.append(FindMatch(line: idx, occ: k))
                k += 1
                range = r.upperBound..<text.endIndex
            }
        }
        matches = result
        current = result.isEmpty ? 0 : min(current, result.count - 1)
        if !result.isEmpty { scrollRequest = result[current].line }
    }

    private func step(_ delta: Int) {
        guard !matches.isEmpty else { return }
        current = (current + delta + matches.count) % matches.count
    }

    private func scrollToCurrent(_ proxy: ScrollViewProxy) {
        guard matches.indices.contains(current) else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            proxy.scrollTo(matches[current].line, anchor: .center)
        }
    }

    private func gotoLine() {
        guard let n = Int(gotoText.trimmingCharacters(in: .whitespaces)), !lines.isEmpty else { return }
        let target = min(max(1, n), lines.count) - 1
        scrollRequest = nil           // ensure onChange fires even for same value
        DispatchQueue.main.async { scrollRequest = target }
    }

    private func resetFind() {
        findQuery = ""; matches = []; current = 0; gotoText = ""
    }
}


// MARK: - Center pane wrapper

/// Wide centre-pane file viewer. If no file is open, shows an empty state and
/// the user can return to chat; otherwise displays the full FileViewer.
struct FileViewerPane: View {
    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var store: KorboStore

    var body: some View {
        Group {
            if store.activeFilePath != nil {
                FileViewer()
            } else {
                emptyState
            }
        }
        .background(Theme.bg)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "doc.text")
                .font(.system(size: 40))
                .foregroundStyle(Theme.textTertiary)
            Text("No file open")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
            Text("Open a file from the Files tab to view it here.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textTertiary)
                .multilineTextAlignment(.center)
            Button {
                app.showChat()
                app.showRightTab(.files)
            } label: {
                Text("Return to chat")
                    .font(.system(size: 13, weight: .medium))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Theme.accent.opacity(0.18)))
                    .foregroundStyle(Theme.accent)
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}
