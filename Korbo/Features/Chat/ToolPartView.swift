import SwiftUI

/// Rich renderer for a tool invocation. Dispatches on the tool name to show a
/// purpose-built header (status, icon, clean argument, result summary, duration)
/// and an expandable body: unified diffs for `edit`, terminal-style output for
/// `bash`, todo checklists for `todowrite`, nested subagent results for `task`,
/// etc. Falls back to a generic input/output dump for unknown tools.
struct ToolPartView: View {
    let part: OCPart
    @State private var expanded = false

    private var state: OCToolState? { part.state }
    private var toolName: String { (part.tool ?? "tool").lowercased() }
    private var input: JSONValue? { state?.input }
    private var metadata: JSONValue? { state?.metadata }
    private var descriptor: ToolDescriptor { ToolDescriptor(part: part) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() } } label: {
                header
                    .padding(.vertical, 3)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                bodyContent
                    .padding(.top, 9)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.panel))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 1))
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            statusIcon
                .accessibilityHidden(true)
            Image(systemName: descriptor.icon)
                .font(.system(size: 12))
                .foregroundStyle(Theme.accent)
                .frame(width: 16)
                .accessibilityHidden(true)
            Text(descriptor.name)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            if let primary = descriptor.primary, !primary.isEmpty {
                Text(primary)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            if let badge = descriptor.summaryBadge {
                summaryBadge(badge)
            }
            if let duration = descriptor.duration {
                Text(duration)
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.textTertiary)
            }
            Image(systemName: expanded ? "chevron.down" : "chevron.right")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Theme.textTertiary)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private func summaryBadge(_ badge: ToolDescriptor.Badge) -> some View {
        Text(badge.text)
            .font(.system(size: 10.5, weight: .semibold, design: badge.monospaced ? .monospaced : .default))
            .foregroundStyle(badge.color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(badge.color.opacity(0.14)))
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch state?.status ?? .unknown {
        case .completed:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.added).font(.system(size: 13))
        case .error:
            Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.removed).font(.system(size: 13))
        case .running:
            ProgressView().scaleEffect(0.6).frame(width: 14, height: 14)
        case .pending, .unknown:
            Image(systemName: "circle.dashed").foregroundStyle(Theme.textTertiary).font(.system(size: 13))
        }
    }

    // MARK: Body

    @ViewBuilder
    private var bodyContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch toolName {
            case "edit", "patch":   editBody
            case "write":           writeBody
            case "bash":            bashBody
            case "todowrite", "todoread": todoBody
            case "task":            taskBody
            default:                genericBody
            }
            if let error = state?.error, !error.isEmpty {
                Text(error)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Theme.removed)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Theme.removed.opacity(0.10)))
            }
        }
    }

    @ViewBuilder
    private var editBody: some View {
        if let path = descriptor.fullPath { pathLabel(path) }
        if let diff = metadata?["diff"]?.stringValue, !diff.isEmpty {
            DiffView(patch: diff, maxLines: 400)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 6).fill(Theme.bg))
        } else if let out = state?.output, !out.isEmpty {
            ToolOutputBlock(text: out)
        }
    }

    @ViewBuilder
    private var writeBody: some View {
        if let path = descriptor.fullPath { pathLabel(path) }
        if let content = input?["content"]?.stringValue, !content.isEmpty {
            ToolOutputBlock(text: content)
        } else if let out = state?.output, !out.isEmpty {
            ToolOutputBlock(text: out)
        }
    }

    @ViewBuilder
    private var bashBody: some View {
        if let cmd = input?["command"]?.stringValue {
            HStack(alignment: .top, spacing: 6) {
                Text("$").foregroundStyle(Theme.accent)
                Text(cmd).foregroundStyle(Theme.textPrimary)
            }
            .font(.system(size: 12, design: .monospaced))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 6).fill(Theme.bg))
        }
        let out = metadata?["output"]?.stringValue ?? state?.output ?? ""
        if !out.isEmpty { ToolOutputBlock(text: out) }
    }

    @ViewBuilder
    private var todoBody: some View {
        let todos = (metadata?["todos"] ?? input?["todos"])?.arrayValue ?? []
        if todos.isEmpty {
            genericBody
        } else {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(todos.enumerated()), id: \.offset) { _, todo in
                    ToolTodoRow(todo: todo)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 6).fill(Theme.bg))
        }
    }

    @ViewBuilder
    private var taskBody: some View {
        HStack(spacing: 6) {
            if let type = input?["subagent_type"]?.stringValue {
                tag(type, icon: "sparkles")
            }
            if let model = metadata?["model"]?["modelID"]?.stringValue {
                tag(model, icon: "cpu")
            }
        }
        if let prompt = input?["prompt"]?.stringValue, !prompt.isEmpty {
            DisclosureText(label: "Prompt", text: prompt)
        }
        let result = Self.taskResult(state?.output ?? "")
        if !result.isEmpty {
            MarkdownView(text: result)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 6).fill(Theme.bg))
        }
    }

    @ViewBuilder
    private var genericBody: some View {
        let kvs = Self.keyValues(input)
        if !kvs.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(kvs, id: \.0) { key, value in
                    HStack(alignment: .top, spacing: 6) {
                        Text(key)
                            .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Theme.textTertiary)
                        Text(value)
                            .font(.system(size: 11.5, design: .monospaced))
                            .foregroundStyle(Theme.textSecondary)
                            .textSelection(.enabled)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if case .string(let s)? = input, !s.isEmpty {
            Text(s)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Theme.textTertiary)
        }
        if let out = state?.output, !out.isEmpty {
            ToolOutputBlock(text: out)
        }
    }

    // MARK: Small components

    @ViewBuilder
    private func pathLabel(_ path: String) -> some View {
        Text(path)
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(Theme.textTertiary)
            .lineLimit(1)
            .truncationMode(.head)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func tag(_ text: String, icon: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 9))
                .accessibilityHidden(true)
            Text(text).font(.system(size: 10.5, weight: .medium))
        }
        .foregroundStyle(Theme.accent)
        .padding(.horizontal, 7)
        .padding(.vertical, 2.5)
        .background(Capsule().fill(Theme.accent.opacity(0.14)))
    }

    // MARK: Helpers

    /// Extract the `<task_result>` body from a subagent `task` tool output,
    /// dropping the leading `task_id:` resume hint.
    static func taskResult(_ s: String) -> String {
        if let open = s.range(of: "<task_result>"), let close = s.range(of: "</task_result>") {
            return String(s[open.upperBound..<close.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        var lines = s.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if lines.first?.hasPrefix("task_id:") == true { lines.removeFirst() }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Flatten a tool's top-level JSON input into sorted key/value display rows.
    static func keyValues(_ value: JSONValue?) -> [(String, String)] {
        guard case .object(let dict)? = value else { return [] }
        return dict.sorted { $0.key < $1.key }.map { ($0.key, displayString($0.value)) }
    }

    static func displayString(_ value: JSONValue) -> String {
        switch value {
        case .string(let s): return s
        case .bool(let b):   return b ? "true" : "false"
        case .null:          return "null"
        case .number(let n):
            return n == n.rounded() ? String(Int(n)) : String(n)
        case .array(let a):  return "[\(a.count) item\(a.count == 1 ? "" : "s")]"
        case .object(let o): return "{\(o.count) field\(o.count == 1 ? "" : "s")}"
        }
    }
}

// MARK: - Tool descriptor

/// Computes the per-tool header presentation (icon, primary argument, result
/// summary badge, duration) from a tool part's name, input, and metadata.
struct ToolDescriptor {
    let part: OCPart

    private var name0: String { part.tool ?? "tool" }
    private var key: String { name0.lowercased() }
    private var input: JSONValue? { part.state?.input }
    private var meta: JSONValue? { part.state?.metadata }

    var name: String { name0 }

    var icon: String {
        switch key {
        case "read":              return "doc.text"
        case "write":             return "square.and.pencil"
        case "edit", "patch":     return "pencil.line"
        case "bash":              return "terminal"
        case "grep":              return "magnifyingglass"
        case "glob":              return "asterisk"
        case "list":              return "folder"
        case "task":              return "sparkles"
        case "todowrite", "todoread": return "checklist"
        case "webfetch":          return "globe"
        default:                  return "wrench.and.screwdriver"
        }
    }

    var fullPath: String? {
        input?["filePath"]?.stringValue ?? input?["path"]?.stringValue
    }

    var primary: String? {
        switch key {
        case "read", "write", "edit", "patch", "list":
            return fullPath.map(Self.basename)
        case "grep", "glob":
            return input?["pattern"]?.stringValue
        case "bash":
            return input?["command"]?.stringValue?
                .replacingOccurrences(of: "\n", with: " ")
        case "task":
            return input?["description"]?.stringValue ?? part.state?.title
        case "todowrite", "todoread":
            let n = (meta?["todos"] ?? input?["todos"])?.arrayValue?.count ?? 0
            return n > 0 ? "\(n) item\(n == 1 ? "" : "s")" : nil
        case "webfetch":
            return input?["url"]?.stringValue
        default:
            return part.state?.title
        }
    }

    struct Badge {
        let text: String
        var color: Color = Theme.textTertiary
        var monospaced: Bool = false
    }

    var summaryBadge: Badge? {
        switch key {
        case "grep":
            guard let n = meta?["matches"]?.doubleValue else { return nil }
            return Badge(text: "\(Int(n)) match\(Int(n) == 1 ? "" : "es")", color: Theme.textSecondary)
        case "glob":
            guard let n = meta?["count"]?.doubleValue else { return nil }
            return Badge(text: "\(Int(n)) file\(Int(n) == 1 ? "" : "s")", color: Theme.textSecondary)
        case "bash":
            guard let code = meta?["exit"]?.doubleValue else { return nil }
            let c = Int(code)
            return Badge(text: "exit \(c)", color: c == 0 ? Theme.added : Theme.removed, monospaced: true)
        case "task":
            return meta?["model"]?["modelID"]?.stringValue.map { Badge(text: $0, color: Theme.textSecondary) }
        default:
            return nil
        }
    }

    var duration: String? {
        guard let start = part.state?.time?.start, let end = part.state?.time?.end, end >= start else { return nil }
        let ms = end - start
        if ms < 1000 { return "\(Int(ms))ms" }
        return String(format: "%.1fs", ms / 1000)
    }

    static func basename(_ path: String) -> String {
        path.split(separator: "/").last.map(String.init) ?? path
    }
}

// MARK: - Reusable body components

/// Monospaced output panel that caps long output and reveals the rest on demand.
private struct ToolOutputBlock: View {
    let text: String
    @State private var showAll = false
    private static let cap = 30

    var body: some View {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        let overflow = lines.count - Self.cap
        let shown = (overflow > 0 && !showAll)
            ? lines.prefix(Self.cap).joined(separator: "\n")
            : text
        VStack(alignment: .leading, spacing: 6) {
            Text(shown.isEmpty ? " " : shown)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Theme.textSecondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            if overflow > 0 {
                Button(showAll ? "Show less" : "Show \(overflow) more line\(overflow == 1 ? "" : "s")") {
                    withAnimation(.easeInOut(duration: 0.15)) { showAll.toggle() }
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 6).fill(Theme.bg))
    }
}

/// One todo row from a `todowrite`/`todoread` tool: status glyph + content,
/// with completed/cancelled items struck through and an optional priority dot.
private struct ToolTodoRow: View {
    let todo: JSONValue

    private var status: String { todo["status"]?.stringValue ?? "pending" }
    private var content: String { todo["content"]?.stringValue ?? "" }
    private var priority: String? { todo["priority"]?.stringValue }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: glyph)
                .font(.system(size: 12))
                .foregroundStyle(glyphColor)
                .accessibilityHidden(true)
            Text(content)
                .font(.system(size: 12))
                .foregroundStyle(isDone ? Theme.textTertiary : Theme.textPrimary)
                .strikethrough(isDone)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let priority, priority != "medium" {
                Text(priority)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(priority == "high" ? Theme.removed : Theme.textTertiary)
            }
        }
    }

    private var isDone: Bool { status == "completed" || status == "cancelled" }

    private var glyph: String {
        switch status {
        case "completed":   return "checkmark.circle.fill"
        case "in_progress": return "circle.lefthalf.filled"
        case "cancelled":   return "xmark.circle"
        default:            return "circle"
        }
    }

    private var glyphColor: Color {
        switch status {
        case "completed":   return Theme.added
        case "in_progress": return Theme.accent
        default:            return Theme.textTertiary
        }
    }
}

/// Collapsible labelled text (used for a subagent task's prompt).
private struct DisclosureText: View {
    let label: String
    let text: String
    @State private var open = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button { withAnimation(.easeInOut(duration: 0.15)) { open.toggle() } } label: {
                HStack(spacing: 4) {
                    Image(systemName: open ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .accessibilityHidden(true)
                    Text(label)
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(Theme.textTertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(label), \(open ? "expanded" : "collapsed")")
            if open {
                Text(text)
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Theme.bg))
            }
        }
    }
}
