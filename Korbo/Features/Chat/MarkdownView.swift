import SwiftUI

// MARK: - Model

/// A parsed block-level markdown element. Inline formatting inside each block
/// (bold/italic/inline-code/links/strikethrough) is handled at render time via
/// `AttributedString(markdown:)`.
enum MarkdownBlock {
    case heading(level: Int, text: String)
    case paragraph(String)
    case bulleted(items: [String])
    case numbered(items: [String])
    case quote(lines: [String])
    case code(language: String?, code: String)
    case table(header: [String], rows: [[String]])
    case rule
}

// MARK: - Parser

/// Minimal, dependency-free block parser. Handles the constructs opencode
/// assistants actually emit: headings, paragraphs, bullet/numbered lists,
/// blockquotes, fenced code blocks, GitHub tables and horizontal rules.
enum MarkdownParser {
    static func parse(_ text: String) -> [MarkdownBlock] {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var blocks: [MarkdownBlock] = []
        var i = 0

        func isRule(_ s: String) -> Bool {
            let t = s.trimmingCharacters(in: .whitespaces)
            guard t.count >= 3 else { return false }
            return Set(t) == ["-"] || Set(t) == ["*"] || Set(t) == ["_"]
        }

        while i < lines.count {
            let raw = lines[i]
            let line = raw.trimmingCharacters(in: .whitespaces)

            // Blank line — skip.
            if line.isEmpty { i += 1; continue }

            // Fenced code block.
            if line.hasPrefix("```") || line.hasPrefix("~~~") {
                let fence = String(line.prefix(3))
                let tag = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var body: [String] = []
                i += 1
                while i < lines.count {
                    let l = lines[i].trimmingCharacters(in: .whitespaces)
                    if l.hasPrefix(fence) { i += 1; break }
                    body.append(lines[i])
                    i += 1
                }
                blocks.append(.code(language: tag.isEmpty ? nil : tag,
                                    code: body.joined(separator: "\n")))
                continue
            }

            // Horizontal rule.
            if isRule(line) { blocks.append(.rule); i += 1; continue }

            // Heading.
            if line.first == "#" {
                let hashes = line.prefix { $0 == "#" }.count
                if hashes <= 6, line.dropFirst(hashes).first == " " {
                    let content = line.dropFirst(hashes).trimmingCharacters(in: .whitespaces)
                    blocks.append(.heading(level: hashes, text: String(content)))
                    i += 1
                    continue
                }
            }

            // Table: a header row with pipes followed by a separator row.
            if line.contains("|"), i + 1 < lines.count, isTableSeparator(lines[i + 1]) {
                let header = splitRow(line)
                var rows: [[String]] = []
                i += 2
                while i < lines.count {
                    let r = lines[i].trimmingCharacters(in: .whitespaces)
                    guard r.contains("|"), !r.isEmpty else { break }
                    rows.append(splitRow(r))
                    i += 1
                }
                blocks.append(.table(header: header, rows: rows))
                continue
            }

            // Blockquote.
            if line.hasPrefix(">") {
                var quoted: [String] = []
                while i < lines.count {
                    let l = lines[i].trimmingCharacters(in: .whitespaces)
                    guard l.hasPrefix(">") else { break }
                    quoted.append(String(l.dropFirst()).trimmingCharacters(in: .whitespaces))
                    i += 1
                }
                blocks.append(.quote(lines: quoted))
                continue
            }

            // Unordered list.
            if isBullet(line) {
                var items: [String] = []
                while i < lines.count, isBullet(lines[i].trimmingCharacters(in: .whitespaces)) {
                    let l = lines[i].trimmingCharacters(in: .whitespaces)
                    items.append(String(l.dropFirst(2)).trimmingCharacters(in: .whitespaces))
                    i += 1
                }
                blocks.append(.bulleted(items: items))
                continue
            }

            // Ordered list.
            if orderedPrefix(line) != nil {
                var items: [String] = []
                while i < lines.count, let p = orderedPrefix(lines[i].trimmingCharacters(in: .whitespaces)) {
                    let l = lines[i].trimmingCharacters(in: .whitespaces)
                    items.append(String(l.dropFirst(p)).trimmingCharacters(in: .whitespaces))
                    i += 1
                }
                blocks.append(.numbered(items: items))
                continue
            }

            // Paragraph: gather consecutive non-blank, non-special lines.
            var para: [String] = []
            while i < lines.count {
                let l = lines[i].trimmingCharacters(in: .whitespaces)
                if l.isEmpty || l.hasPrefix("```") || l.hasPrefix("~~~") || l.hasPrefix("#")
                    || l.hasPrefix(">") || isBullet(l) || orderedPrefix(l) != nil || isRule(l) {
                    break
                }
                para.append(l)
                i += 1
            }
            if !para.isEmpty {
                blocks.append(.paragraph(para.joined(separator: "\n")))
            }
        }
        return blocks
    }

    private static func isBullet(_ s: String) -> Bool {
        guard s.count >= 2 else { return false }
        let first = s.first!
        return (first == "-" || first == "*" || first == "+") && s[s.index(after: s.startIndex)] == " "
    }

    /// Returns the length of the ordered-list marker (e.g. "12. " → 4), or nil.
    private static func orderedPrefix(_ s: String) -> Int? {
        var digits = 0
        for ch in s { if ch.isNumber { digits += 1 } else { break } }
        guard digits > 0 else { return nil }
        let rest = s.dropFirst(digits)
        guard let dot = rest.first, dot == "." || dot == ")",
              rest.dropFirst().first == " " else { return nil }
        return digits + 2
    }

    private static func isTableSeparator(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespaces)
        guard t.contains("|"), t.contains("-") else { return false }
        let allowed = Set("|-: ")
        return t.allSatisfy { allowed.contains($0) }
    }

    private static func splitRow(_ s: String) -> [String] {
        var t = s.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("|") { t.removeFirst() }
        if t.hasSuffix("|") { t.removeLast() }
        return t.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }
}

// MARK: - Inline rendering

enum MarkdownInline {
    /// Render inline markdown (bold/italic/inline-code/links/strikethrough) into
    /// an `AttributedString`, applying explicit fonts so styling is reliable.
    static func attributed(_ raw: String, baseSize: CGFloat = 14) -> AttributedString {
        var options = AttributedString.MarkdownParsingOptions()
        options.interpretedSyntax = .inlineOnlyPreservingWhitespace
        options.failurePolicy = .returnPartiallyParsedIfPossible

        guard var attr = try? AttributedString(markdown: raw, options: options) else {
            return AttributedString(raw)
        }

        for run in attr.runs {
            let range = run.range
            let intent = run.inlinePresentationIntent ?? []
            let bold = intent.contains(.stronglyEmphasized)
            let italic = intent.contains(.emphasized)
            let code = intent.contains(.code)

            if code {
                attr[range].font = .system(size: baseSize - 1, design: .monospaced)
                attr[range].foregroundColor = Color(hex: 0xCE9178)
                attr[range].backgroundColor = Theme.panel
            } else {
                var font = Font.system(size: baseSize)
                if bold && italic { font = .system(size: baseSize, weight: .bold).italic() }
                else if bold { font = .system(size: baseSize, weight: .bold) }
                else if italic { font = .system(size: baseSize).italic() }
                attr[range].font = font
            }

            if intent.contains(.strikethrough) {
                attr[range].strikethroughStyle = .single
            }
            if run.link != nil {
                attr[range].foregroundColor = Theme.accent
                attr[range].underlineStyle = .single
            }
        }
        return attr
    }
}

// MARK: - View

/// Renders a markdown string as a stack of styled blocks. Used for assistant
/// message text parts so model output (lists, tables, code, links) renders
/// richly instead of as a flat string.
struct MarkdownView: View {
    let text: String
    var baseSize: CGFloat = 14

    private var blocks: [MarkdownBlock] { MarkdownParser.parse(text) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownBlock) -> some View {
        switch block {
        case let .heading(level, text):
            Text(MarkdownInline.attributed(text, baseSize: headingSize(level)))
                .font(.system(size: headingSize(level), weight: .bold))
                .foregroundStyle(Theme.textPrimary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

        case let .paragraph(text):
            Text(MarkdownInline.attributed(text, baseSize: baseSize))
                .foregroundStyle(Theme.textPrimary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

        case let .bulleted(items):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    listRow(marker: "•", text: item)
                }
            }

        case let .numbered(items):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                    listRow(marker: "\(idx + 1).", text: item)
                }
            }

        case let .quote(lines):
            HStack(spacing: 0) {
                Rectangle().fill(Theme.accent.opacity(0.6)).frame(width: 3)
                Text(MarkdownInline.attributed(lines.joined(separator: "\n"), baseSize: baseSize))
                    .foregroundStyle(Theme.textSecondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 10)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        case let .code(language, code):
            CodeBlockView(language: language, code: code)

        case let .table(header, rows):
            MarkdownTableView(header: header, rows: rows, baseSize: baseSize)

        case .rule:
            Rectangle().fill(Theme.border).frame(height: 1).padding(.vertical, 2)
        }
    }

    private func listRow(marker: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(marker)
                .font(.system(size: baseSize))
                .foregroundStyle(Theme.textTertiary)
                .frame(minWidth: 16, alignment: .trailing)
            Text(MarkdownInline.attributed(text, baseSize: baseSize))
                .foregroundStyle(Theme.textPrimary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func headingSize(_ level: Int) -> CGFloat {
        switch level {
        case 1: return baseSize + 6
        case 2: return baseSize + 4
        case 3: return baseSize + 2
        default: return baseSize + 1
        }
    }
}

// MARK: - Code block

/// A fenced code block: syntax-highlighted body, language label and copy button.
private struct CodeBlockView: View {
    let language: String?
    let code: String
    @State private var copied = false

    private var lines: [[CodeRun]] {
        SyntaxHighlighter.highlight(code, language: language.flatMap { SyntaxHighlighter.language(forFenceTag: $0) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(language?.isEmpty == false ? language! : "code")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
                Spacer()
                Button {
                    UIPasteboard.general.string = code
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { copied = false }
                } label: {
                    Label(copied ? "Copied" : "Copy",
                          systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(copied ? Theme.added : Theme.textSecondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(Theme.panelRaised)

            ScrollView(.horizontal, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, runs in
                        Text(attributed(runs))
                            .font(.system(size: 12.5, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
                .padding(12)
            }
        }
        .background(Theme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border, lineWidth: 1))
    }

    private func attributed(_ runs: [CodeRun]) -> AttributedString {
        guard !runs.isEmpty else { return AttributedString(" ") }
        var s = AttributedString()
        for run in runs {
            var piece = AttributedString(run.text)
            piece.foregroundColor = run.kind.color
            s += piece
        }
        return s
    }
}

// MARK: - Table

private struct MarkdownTableView: View {
    let header: [String]
    let rows: [[String]]
    let baseSize: CGFloat

    private var columnCount: Int {
        max(header.count, rows.map(\.count).max() ?? 0)
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                row(header, isHeader: true)
                ForEach(Array(rows.enumerated()), id: \.offset) { _, r in
                    Divider().overlay(Theme.border)
                    row(r, isHeader: false)
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 1))
        }
    }

    private func row(_ cells: [String], isHeader: Bool) -> some View {
        HStack(spacing: 0) {
            ForEach(0..<columnCount, id: \.self) { c in
                Text(MarkdownInline.attributed(c < cells.count ? cells[c] : "", baseSize: baseSize - 1))
                    .font(.system(size: baseSize - 1, weight: isHeader ? .semibold : .regular))
                    .foregroundStyle(isHeader ? Theme.textPrimary : Theme.textSecondary)
                    .frame(minWidth: 90, alignment: .leading)
                    .padding(.horizontal, 10).padding(.vertical, 7)
                if c < columnCount - 1 {
                    Rectangle().fill(Theme.border).frame(width: 1)
                }
            }
        }
        .background(isHeader ? Theme.panelRaised : Color.clear)
    }
}
