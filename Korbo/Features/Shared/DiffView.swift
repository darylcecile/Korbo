import SwiftUI

/// Renders a unified-diff `patch` as colored add/remove/context/hunk lines.
/// Shared by the Git panel and the chat tool-call renderer (edit/patch tools).
struct DiffView: View {
    let patch: String
    let maxLines: Int

    init(patch: String, maxLines: Int = 600) {
        self.patch = patch
        self.maxLines = maxLines
    }

    var body: some View {
        let parsed = DiffLine.parse(patch, limit: maxLines)
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

struct DiffLine {
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
            || line.hasPrefix("Index: ")
            || line.hasPrefix("===")
            || line.hasPrefix("\\ No newline")
    }
}
