import SwiftUI

/// Full-screen pull-request diff reviewer. Loads the PR's changed files and
/// existing inline review comments, renders each file's unified diff with
/// per-line numbers, lets you tap any diff line to add an inline review
/// comment, and submit a review verdict (Comment / Approve / Request changes).
struct PRDiffView: View {
    let pr: GHPullRequest
    let owner: String
    let repo: String

    @EnvironmentObject var github: GitHubStore

    @State private var files: [GHPRFile] = []
    @State private var comments: [GHReviewComment] = []
    @State private var collapsed: Set<String> = []
    @State private var loading = false
    @State private var errorText: String?

    @State private var composerTarget: CommentTarget?
    @State private var showReviewSheet = false

    private var commitID: String? { pr.head.sha }

    var body: some View {
        Group {
            if loading && files.isEmpty {
                loadingView
            } else if let err = errorText, files.isEmpty {
                errorView(err)
            } else if files.isEmpty {
                emptyView
            } else {
                diffContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bg)
        .navigationTitle("Files changed")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showReviewSheet = true
                } label: {
                    Text("Review")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(Theme.accent)
                .disabled(!github.isSignedIn)
            }
        }
        .task { await load() }
        .sheet(item: $composerTarget) { target in
            CommentComposer(target: target) { body in
                await postComment(target: target, body: body)
            }
        }
        .sheet(isPresented: $showReviewSheet) {
            ReviewComposer { event, body in
                await submitReview(event: event, body: body)
            }
        }
    }

    // MARK: - Content

    private var diffContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: []) {
                summaryHeader
                if commitID == nil {
                    Text("Inline comments are unavailable: this PR has no head commit SHA.")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textTertiary)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 6)
                } else {
                    Text("Tap any line to add an inline comment.")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textTertiary)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 6)
                }
                ForEach(files) { file in
                    fileSection(file)
                }
            }
            .padding(.vertical, 8)
        }
    }

    private var summaryHeader: some View {
        HStack(spacing: 10) {
            Text("#\(pr.number)")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.textTertiary)
            Text("\(files.count) file\(files.count == 1 ? "" : "s")")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
            Text("+\(totalAdditions)")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.added)
            Text("-\(totalDeletions)")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.removed)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private func fileSection(_ file: GHPRFile) -> some View {
        let isCollapsed = collapsed.contains(file.id)
        VStack(alignment: .leading, spacing: 0) {
            Button {
                toggle(file.id)
            } label: {
                FileHeader(file: file, collapsed: isCollapsed)
            }
            .buttonStyle(.plain)

            if !isCollapsed {
                if let patch = file.patch, !patch.isEmpty {
                    let parsed = PRDiffParser.parse(patch)
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(parsed.rows) { row in
                            diffRow(file: file, row: row)
                        }
                        if parsed.truncated {
                            Text("… diff truncated")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(Theme.textTertiary)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 4)
                        }
                    }
                    .padding(.vertical, 4)
                } else {
                    Text(file.status == "renamed" ? "Renamed (no content diff)." : "No textual diff available.")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textTertiary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                }
            }
        }
        .background(Theme.panel.opacity(0.4))
        .overlay(alignment: .top) { Divider().overlay(Theme.border) }
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private func diffRow(file: GHPRFile, row: PRDiffRow) -> some View {
        let anchor = row.commentAnchor
        let rowComments = commentsFor(file: file, row: row)
        VStack(alignment: .leading, spacing: 0) {
            Button {
                guard let anchor, commitID != nil else { return }
                composerTarget = CommentTarget(
                    path: file.filename, line: anchor.line,
                    side: anchor.side, snippet: row.text
                )
            } label: {
                DiffRowView(row: row, commentable: anchor != nil && commitID != nil)
            }
            .buttonStyle(.plain)
            .disabled(anchor == nil || commitID == nil)

            ForEach(rowComments) { comment in
                InlineCommentView(comment: comment)
            }
        }
    }

    // MARK: - States

    private var loadingView: some View {
        VStack(spacing: 10) {
            ProgressView().tint(Theme.accent)
            Text("Loading diff…")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textTertiary)
        }
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 26))
                .foregroundStyle(Theme.removed)
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
            Button("Retry") { Task { await load() } }
                .foregroundStyle(Theme.accent)
        }
        .padding(24)
    }

    private var emptyView: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 26))
                .foregroundStyle(Theme.textTertiary)
            Text("No file changes in this pull request.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
        }
    }

    // MARK: - Derived

    private var totalAdditions: Int { files.reduce(0) { $0 + $1.additions } }
    private var totalDeletions: Int { files.reduce(0) { $0 + $1.deletions } }

    private func commentsFor(file: GHPRFile, row: PRDiffRow) -> [GHReviewComment] {
        guard let anchor = row.commentAnchor else { return [] }
        return comments.filter { c in
            c.path == file.filename
                && (c.side ?? "RIGHT") == anchor.side
                && (c.line ?? c.originalLine) == anchor.line
        }
    }

    private func toggle(_ id: String) {
        if collapsed.contains(id) { collapsed.remove(id) } else { collapsed.insert(id) }
    }

    // MARK: - Networking

    private func load() async {
        loading = true
        errorText = nil
        defer { loading = false }
        do {
            async let filesReq = github.loadFiles(owner: owner, repo: repo, number: pr.number)
            async let commentsReq = github.loadReviewComments(owner: owner, repo: repo, number: pr.number)
            files = try await filesReq
            comments = (try? await commentsReq) ?? []
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func postComment(target: CommentTarget, body: String) async -> String? {
        guard let commitID else { return "This PR has no head commit to anchor a comment." }
        do {
            let created = try await github.addReviewComment(
                owner: owner, repo: repo, number: pr.number,
                body: body, commitID: commitID,
                path: target.path, line: target.line, side: target.side
            )
            comments.append(created)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    private func submitReview(event: String, body: String) async -> String? {
        do {
            _ = try await github.submitReview(
                owner: owner, repo: repo, number: pr.number,
                body: body.isEmpty ? nil : body, event: event
            )
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}

// MARK: - Comment target

struct CommentTarget: Identifiable, Equatable {
    let path: String
    let line: Int
    let side: String
    let snippet: String
    var id: String { "\(path):\(side):\(line)" }
}

// MARK: - File header

private struct FileHeader: View {
    let file: GHPRFile
    let collapsed: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: collapsed ? "chevron.right" : "chevron.down")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)
                .frame(width: 12)
            statusChip
            Text(file.filename)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 6)
            Text("+\(file.additions)")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.added)
            Text("-\(file.deletions)")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.removed)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .contentShape(Rectangle())
    }

    private var statusChip: some View {
        let (label, color): (String, Color) = {
            switch file.status {
            case "added":    return ("A", Theme.added)
            case "removed":  return ("D", Theme.removed)
            case "renamed":  return ("R", Theme.accent)
            case "modified": return ("M", Theme.textSecondary)
            default:         return (String(file.status.prefix(1)).uppercased(), Theme.textTertiary)
            }
        }()
        return Text(label)
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundStyle(color)
            .frame(width: 16, height: 16)
            .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: 3))
    }
}

// MARK: - Diff row

private struct DiffRowView: View {
    let row: PRDiffRow
    let commentable: Bool

    var body: some View {
        HStack(spacing: 0) {
            gutter(row.oldLine)
            gutter(row.newLine)
            Text(prefix)
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(row.foreground)
                .frame(width: 10, alignment: .leading)
            Text(row.text.isEmpty ? " " : row.text)
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(row.foreground)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.trailing, 12)
        .padding(.vertical, 1)
        .background(row.background)
        .contentShape(Rectangle())
    }

    private var prefix: String {
        switch row.kind {
        case .add: return "+"
        case .remove: return "-"
        default: return ""
        }
    }

    private func gutter(_ n: Int?) -> some View {
        Text(n.map(String.init) ?? "")
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(Theme.textTertiary)
            .frame(width: 38, alignment: .trailing)
            .padding(.trailing, 4)
    }
}

// MARK: - Inline comment

private struct InlineCommentView: View {
    let comment: GHReviewComment

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "bubble.left.fill")
                .font(.system(size: 10))
                .foregroundStyle(Theme.accent)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text("@\(comment.user?.login ?? "?")")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(comment.body)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Theme.accent.opacity(0.07))
        .overlay(alignment: .leading) {
            Rectangle().fill(Theme.accent).frame(width: 2)
        }
        .padding(.leading, 52)
        .padding(.trailing, 12)
        .padding(.vertical, 2)
    }
}

// MARK: - Comment composer

private struct CommentComposer: View {
    let target: CommentTarget
    let onSubmit: (String) async -> String?

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var submitting = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(target.path):\(target.line) · \(target.side == "RIGHT" ? "new" : "old")")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(target.snippet.isEmpty ? " " : target.snippet)
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(2)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 6))
                }

                ThemedEditor(text: $text, placeholder: "Leave a comment…")
                    .frame(minHeight: 120)

                if let errorText {
                    Text(errorText)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.removed)
                }
                Spacer()
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.bg)
            .navigationTitle("Add comment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Theme.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await submit() }
                    } label: {
                        if submitting { ProgressView().controlSize(.small) }
                        else { Text("Comment").fontWeight(.semibold) }
                    }
                    .foregroundStyle(Theme.accent)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || submitting)
                }
            }
        }
    }

    private func submit() async {
        submitting = true
        errorText = nil
        defer { submitting = false }
        if let err = await onSubmit(text.trimmingCharacters(in: .whitespacesAndNewlines)) {
            errorText = err
        } else {
            dismiss()
        }
    }
}

// MARK: - Review composer

private struct ReviewComposer: View {
    let onSubmit: (_ event: String, _ body: String) async -> String?

    @Environment(\.dismiss) private var dismiss
    @State private var verdict: Verdict = .comment
    @State private var summary = ""
    @State private var submitting = false
    @State private var errorText: String?

    enum Verdict: String, CaseIterable, Identifiable {
        case comment, approve, requestChanges
        var id: String { rawValue }
        var label: String {
            switch self {
            case .comment: return "Comment"
            case .approve: return "Approve"
            case .requestChanges: return "Request changes"
            }
        }
        var event: String {
            switch self {
            case .comment: return "COMMENT"
            case .approve: return "APPROVE"
            case .requestChanges: return "REQUEST_CHANGES"
            }
        }
    }

    private var bodyRequired: Bool { verdict != .approve }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Verdict", selection: $verdict) {
                    ForEach(Verdict.allCases) { v in
                        Text(v.label).tag(v)
                    }
                }
                .pickerStyle(.segmented)

                ThemedEditor(
                    text: $summary,
                    placeholder: bodyRequired ? "Review summary (required)…" : "Optional review summary…"
                )
                .frame(minHeight: 140)

                if let errorText {
                    Text(errorText)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.removed)
                }
                Spacer()
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.bg)
            .navigationTitle("Submit review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Theme.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await submit() }
                    } label: {
                        if submitting { ProgressView().controlSize(.small) }
                        else { Text("Submit").fontWeight(.semibold) }
                    }
                    .foregroundStyle(Theme.accent)
                    .disabled(submitting || (bodyRequired && summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
                }
            }
        }
    }

    private func submit() async {
        submitting = true
        errorText = nil
        defer { submitting = false }
        let trimmed = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        if let err = await onSubmit(verdict.event, trimmed) {
            errorText = err
        } else {
            dismiss()
        }
    }
}

// MARK: - Themed text editor

private struct ThemedEditor: View {
    @Binding var text: String
    let placeholder: String

    var body: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text(placeholder)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .allowsHitTesting(false)
            }
            TextEditor(text: $text)
                .font(.system(size: 13))
                .foregroundStyle(Theme.textPrimary)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
        }
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 1))
    }
}

// MARK: - Diff parser

struct PRDiffRow: Identifiable {
    enum Kind { case add, remove, context, hunk }
    let id = UUID()
    let kind: Kind
    let text: String
    let oldLine: Int?
    let newLine: Int?

    /// The `(line, side)` pair GitHub needs to anchor an inline comment, or
    /// `nil` for hunk headers (which cannot be commented on).
    var commentAnchor: (line: Int, side: String)? {
        switch kind {
        case .add, .context: return newLine.map { ($0, "RIGHT") }
        case .remove:        return oldLine.map { ($0, "LEFT") }
        case .hunk:          return nil
        }
    }

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
}

enum PRDiffParser {
    /// Parse a single-file unified-diff `patch` (as returned by the GitHub
    /// `/pulls/{n}/files` endpoint) into rows carrying old/new line numbers so
    /// each line can be anchored for an inline comment.
    static func parse(_ patch: String, limit: Int = 1500) -> (rows: [PRDiffRow], truncated: Bool) {
        var rows: [PRDiffRow] = []
        var oldLine = 0
        var newLine = 0
        var total = 0

        for raw in patch.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)
            if line.hasPrefix("@@") {
                if let header = parseHunkHeader(line) {
                    oldLine = header.old
                    newLine = header.new
                }
                total += 1
                if rows.count < limit {
                    rows.append(PRDiffRow(kind: .hunk, text: line, oldLine: nil, newLine: nil))
                }
            } else if line.hasPrefix("+") {
                total += 1
                if rows.count < limit {
                    rows.append(PRDiffRow(kind: .add, text: String(line.dropFirst()), oldLine: nil, newLine: newLine))
                }
                newLine += 1
            } else if line.hasPrefix("-") {
                total += 1
                if rows.count < limit {
                    rows.append(PRDiffRow(kind: .remove, text: String(line.dropFirst()), oldLine: oldLine, newLine: nil))
                }
                oldLine += 1
            } else if line.hasPrefix("\\") {
                // "\ No newline at end of file" — not a real diff line.
                continue
            } else {
                let text = line.hasPrefix(" ") ? String(line.dropFirst()) : line
                total += 1
                if rows.count < limit {
                    rows.append(PRDiffRow(kind: .context, text: text, oldLine: oldLine, newLine: newLine))
                }
                oldLine += 1
                newLine += 1
            }
        }
        return (rows, total > limit)
    }

    /// Parse `@@ -oldStart,oldCount +newStart,newCount @@` → starting line numbers.
    private static func parseHunkHeader(_ line: String) -> (old: Int, new: Int)? {
        guard let firstAt = line.range(of: "@@"),
              let secondAt = line.range(of: "@@", range: firstAt.upperBound..<line.endIndex)
        else { return nil }
        let spec = line[firstAt.upperBound..<secondAt.lowerBound]
            .trimmingCharacters(in: .whitespaces)
        var old = 0, new = 0
        for token in spec.split(separator: " ") {
            if token.hasPrefix("-"), let v = Int(token.dropFirst().split(separator: ",").first ?? "") {
                old = v
            } else if token.hasPrefix("+"), let v = Int(token.dropFirst().split(separator: ",").first ?? "") {
                new = v
            }
        }
        return (old, new)
    }
}
