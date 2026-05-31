import SwiftUI

/// Right-pane **Files** tab. opencode's server exposes a read-only file surface
/// (`/file`, `/file/content`, `/find/file`), so this panel is a lazy, collapsible
/// workspace browser with fuzzy path search and a line-numbered viewer. Editing,
/// creating and deleting files aren't in the opencode REST API and are deferred.
struct FilesPane: View {
    @EnvironmentObject private var store: KorboStore

    var body: some View {
        Group {
            if store.selectedFilePath != nil {
                FileViewer()
            } else {
                browser
            }
        }
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
                else { await store.openFile(node.path) }
            }
        } label: {
            HStack(spacing: 6) {
                if node.isDirectory {
                    Image(systemName: isOpen ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Theme.textTertiary)
                        .frame(width: 10)
                } else {
                    Spacer().frame(width: 10)
                }
                Image(systemName: icon(for: node, isOpen: isOpen))
                    .font(.system(size: 12))
                    .foregroundStyle(node.isDirectory ? Theme.accent : Theme.textSecondary)
                    .frame(width: 16)
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
                        Button { Task { await store.openFile(path) } } label: {
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

// MARK: - File viewer (read-only)

/// Read-only file viewer: header with the path + close, then line-numbered,
/// monospaced content (capped) or a binary-file notice.
private struct FileViewer: View {
    @EnvironmentObject private var store: KorboStore

    private static let maxLines = 1500

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.border)
            content
        }
    }

    private var header: some View {
        let (dir, name) = splitPath(store.selectedFilePath ?? "")
        return HStack(spacing: 8) {
            Button { store.closeFile() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.system(size: 13, weight: .semibold))
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
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var content: some View {
        if store.isLoadingFile {
            VStack(spacing: 10) {
                Spacer()
                ProgressView().tint(Theme.textTertiary)
                Text("Loading…").font(.system(size: 12)).foregroundStyle(Theme.textTertiary)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let file = store.fileContent {
            if file.isBinary {
                centeredNotice(icon: "doc.badge.ellipsis", text: "Binary file — preview unavailable")
            } else {
                codeView(file.content ?? "")
            }
        } else {
            centeredNotice(icon: "exclamationmark.triangle", text: "Couldn't load file")
        }
    }

    private func codeView(_ text: String) -> some View {
        let all = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let lines = Array(all.prefix(Self.maxLines))
        let truncated = all.count > Self.maxLines
        let gutter = max(2, String(lines.count).count)
        return ScrollView([.vertical, .horizontal]) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(lines.enumerated()), id: \.offset) { idx, line in
                    HStack(alignment: .top, spacing: 10) {
                        Text(String(format: "%\(gutter)d", idx + 1))
                            .foregroundStyle(Theme.textTertiary)
                        Text(line.isEmpty ? " " : line)
                            .foregroundStyle(Theme.textPrimary)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    .font(.system(size: 12, design: .monospaced))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 1)
                }
                if truncated {
                    Text("… file truncated at \(Self.maxLines) lines")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Theme.textTertiary)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                }
            }
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func centeredNotice(icon: String, text: String) -> some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: icon).font(.system(size: 30)).foregroundStyle(Theme.textTertiary)
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private func splitPath(_ path: String) -> (dir: String, name: String) {
        guard let slash = path.lastIndex(of: "/") else { return ("", path) }
        return (String(path[..<slash]), String(path[path.index(after: slash)...]))
    }
}
