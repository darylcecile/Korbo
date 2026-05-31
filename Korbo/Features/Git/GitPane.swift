import SwiftUI

/// Right-pane **Git** tab. opencode's server exposes a read + diff VCS surface
/// (`/vcs`, `/vcs/diff`), so this panel focuses on understanding changes:
/// current branch, a working-vs-branch diff toggle, the changed-file list and an
/// inline unified-diff viewer. Mutations (commit/push/branch switch) aren't in the
/// opencode REST API and arrive in a later milestone via a server-side bridge.
struct GitPane: View {
    @EnvironmentObject private var store: KorboStore
    @State private var expanded: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.border)
            content
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                Text(store.vcsInfo?.branch ?? "—")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                if let base = store.vcsInfo?.defaultBranch,
                   base != store.vcsInfo?.branch {
                    Text("→ \(base)")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                Button {
                    Task { await store.loadGit() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                }
                .buttonStyle(.plain)
                .disabled(store.isLoadingGit)
            }

            Picker("Diff", selection: Binding(
                get: { store.gitMode },
                set: { mode in Task { await store.setGitMode(mode) } }
            )) {
                ForEach(KorboStore.GitMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            summaryRow
        }
        .padding(16)
    }

    private var summaryRow: some View {
        let files = store.gitFiles
        let adds = files.reduce(0) { $0 + $1.additions }
        let dels = files.reduce(0) { $0 + $1.deletions }
        return HStack(spacing: 12) {
            Text("\(files.count) file\(files.count == 1 ? "" : "s")")
                .foregroundStyle(Theme.textSecondary)
            if adds > 0 {
                Text("+\(adds)").foregroundStyle(Theme.added)
            }
            if dels > 0 {
                Text("-\(dels)").foregroundStyle(Theme.removed)
            }
            Spacer()
        }
        .font(.system(size: 12, weight: .medium))
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if store.gitFiles.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(store.gitFiles) { file in
                        fileSection(file)
                        Divider().overlay(Theme.border)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            if store.isLoadingGit {
                ProgressView().tint(Theme.textTertiary)
                Text("Loading changes…")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textTertiary)
            } else {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 30))
                    .foregroundStyle(Theme.textTertiary)
                Text(store.gitMode == .working ? "No working changes" : "No branch changes")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                Text(store.gitMode == .working
                     ? "The working tree is clean."
                     : "This branch matches its base.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textTertiary)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private func fileSection(_ file: OCVcsFileDiff) -> some View {
        let isOpen = expanded.contains(file.id)
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                if isOpen { expanded.remove(file.id) } else { expanded.insert(file.id) }
            } label: {
                fileRow(file, isOpen: isOpen)
            }
            .buttonStyle(.plain)

            if isOpen {
                DiffView(patch: file.patch ?? "")
                    .padding(.bottom, 8)
            }
        }
    }

    private func fileRow(_ file: OCVcsFileDiff, isOpen: Bool) -> some View {
        let (dir, name) = splitPath(file.file)
        return HStack(spacing: 8) {
            statusBadge(file.status)
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if !dir.isEmpty {
                    Text(dir)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            }
            Spacer(minLength: 6)
            if file.additions > 0 {
                Text("+\(file.additions)").foregroundStyle(Theme.added)
            }
            if file.deletions > 0 {
                Text("-\(file.deletions)").foregroundStyle(Theme.removed)
            }
            Image(systemName: isOpen ? "chevron.down" : "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)
        }
        .font(.system(size: 12, weight: .medium))
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    private func statusBadge(_ status: OCFileStatus?) -> some View {
        let letter: String
        let color: Color
        switch status {
        case .added:    letter = "A"; color = Theme.added
        case .deleted:  letter = "D"; color = Theme.removed
        case .modified: letter = "M"; color = Theme.accent
        default:        letter = "•"; color = Theme.textTertiary
        }
        return Text(letter)
            .font(.system(size: 11, weight: .bold, design: .monospaced))
            .foregroundStyle(color)
            .frame(width: 18, height: 18)
            .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
    }

    private func splitPath(_ path: String) -> (dir: String, name: String) {
        guard let slash = path.lastIndex(of: "/") else { return ("", path) }
        return (String(path[..<path.index(after: slash)]), String(path[path.index(after: slash)...]))
    }
}

// MARK: - Diff viewer

/// Renders a unified-diff `patch` as colored add/remove/context/hunk lines.
private struct DiffView: View {
    let patch: String

    private static let maxLines = 600

    var body: some View {
        let parsed = DiffLine.parse(patch, limit: Self.maxLines)
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(parsed.lines.enumerated()), id: \.offset) { _, line in
                row(line)
            }
            if parsed.truncated {
                Text("… diff truncated")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func row(_ line: DiffLine) -> some View {
        Text(line.text.isEmpty ? " " : line.text)
            .font(.system(size: 11.5, design: .monospaced))
            .foregroundStyle(line.foreground)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 1)
            .background(line.background)
    }
}

private struct DiffLine {
    enum Kind { case add, remove, context, hunk }
    let kind: Kind
    let text: String

    var foreground: Color {
        switch kind {
        case .add:     return Theme.added
        case .remove:  return Theme.removed
        case .context: return Theme.textSecondary
        case .hunk:    return Theme.textTertiary
        }
    }

    var background: Color {
        switch kind {
        case .add:     return Theme.added.opacity(0.10)
        case .remove:  return Theme.removed.opacity(0.10)
        default:       return .clear
        }
    }

    /// Parse a unified diff into displayable lines, dropping file-header noise.
    /// Returns up to `limit` lines plus whether more were elided.
    static func parse(_ patch: String, limit: Int) -> (lines: [DiffLine], truncated: Bool) {
        var out: [DiffLine] = []
        var total = 0
        for raw in patch.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)
            if isHeaderNoise(line) { continue }
            total += 1
            guard out.count < limit else { continue }
            if line.hasPrefix("@@") {
                out.append(DiffLine(kind: .hunk, text: line))
            } else if line.hasPrefix("+") {
                out.append(DiffLine(kind: .add, text: String(line.dropFirst())))
            } else if line.hasPrefix("-") {
                out.append(DiffLine(kind: .remove, text: String(line.dropFirst())))
            } else {
                out.append(DiffLine(kind: .context, text: line.hasPrefix(" ") ? String(line.dropFirst()) : line))
            }
        }
        return (out, total > limit)
    }

    private static func isHeaderNoise(_ line: String) -> Bool {
        line.hasPrefix("diff --git") || line.hasPrefix("index ")
            || line.hasPrefix("--- ") || line.hasPrefix("+++ ")
            || line.hasPrefix("new file") || line.hasPrefix("deleted file")
            || line.hasPrefix("rename ") || line.hasPrefix("similarity ")
            || line.hasPrefix("\\ No newline")
    }
}
