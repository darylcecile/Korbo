import SwiftUI

/// Right-hand context panel: git · files · context. M1 wires the **context** tab
/// to live session token/cost data; git and files arrive in later milestones
/// (M3 / M5) and show honest "coming soon" states until then.
struct ContextPane: View {
    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var store: KorboStore
    @State private var previewImage: ContextImagePreview?

    var body: some View {
        VStack(spacing: 0) {
            tabStrip
            Divider().overlay(Theme.border)

            switch app.rightTab {
            case .git:
                GitPane()
            case .files:
                FilesPane()
            case .context:
                contextTab
            }
            Spacer(minLength: 0)
        }
        .background(Theme.panel)
        .sheet(item: $previewImage) { preview in
            ContextImagePreviewSheet(preview: preview)
        }
    }

    private var tabStrip: some View {
        HStack(spacing: 0) {
            ForEach(AppModel.RightTab.allCases) { tab in
                Button { app.rightTab = tab } label: {
                    HStack(spacing: 6) {
                        Image(systemName: tab.systemImage).font(.system(size: 12))
                            .accessibilityHidden(true)
                        Text(tab.title).font(.system(size: 13, weight: .medium))
                    }
                    .foregroundStyle(app.rightTab == tab ? Theme.textPrimary : Theme.textTertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Agent todos

    @ViewBuilder
    private var todoPanel: some View {
        let todos = store.latestTodos
        if todos.isEmpty {
            EmptyView()
        } else {
            let completed = todos.filter { $0["status"]?.stringValue == "completed" }.count
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Agent todos")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Text("\(completed)/\(todos.count)")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                }
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(todos.enumerated()), id: \.offset) { _, todo in
                        ContextTodoRow(todo: todo)
                    }
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 8).fill(Theme.bg)
                )
            }
        }
    }

    // MARK: Context files

    @ViewBuilder
    private var contextFilesPanel: some View {
        let files = store.contextFiles
        if !files.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Context files")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Text("\(files.count)")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                }
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(files) { file in
                        ContextFileRow(file: file) { open(file) }
                    }
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 8).fill(Theme.bg)
                )
            }
        }
    }

    /// Tapping a context file either previews an embedded image attachment or
    /// opens a real file in the viewer.
    private func open(_ file: ContextFile) {
        if file.isImage, let data = file.inlineData {
            previewImage = ContextImagePreview(name: file.name, data: data)
        } else {
            Task { await store.openFile(file.path) }
            app.showFilesCenter()
        }
    }

    // MARK: Context tab (live)

    @ViewBuilder
    private var contextTab: some View {
        if let session = store.selectedSession {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    todoPanel
                    if !store.latestTodos.isEmpty {
                        Divider().overlay(Theme.border)
                    }
                    metricRow("Cost", value: session.cost.map { String(format: "$%.4f", $0) } ?? "—")
                    if let usage = store.latestUsage {
                        usageSection(usage)
                    }
                    Divider().overlay(Theme.border)
                    metricRow("Additions", value: "+\(session.additions)", color: Theme.added)
                    metricRow("Deletions", value: "-\(session.deletions)", color: Theme.removed)
                    if let project = session.projectName {
                        metricRow("Project", value: project)
                    }
                    if let model = session.model?.modelID {
                        metricRow("Model", value: model)
                    }
                    if !store.contextFiles.isEmpty {
                        Divider().overlay(Theme.border)
                        contextFilesPanel
                    }
                }
                .padding(16)
            }
        } else {
            comingSoon(icon: "doc.text.magnifyingglass",
                       title: "No session selected",
                       detail: "Select a session to see its token usage and cost.")
        }
    }

    // MARK: Token usage

    private struct UsageSegment: Identifiable {
        let id = UUID()
        let label: String
        let value: Double
        let color: Color
    }

    private func segments(_ u: OCMessage.Usage) -> [UsageSegment] {
        [
            UsageSegment(label: "Input", value: u.input ?? 0, color: Color(hex: 0x5B8DEF)),
            UsageSegment(label: "Cache", value: u.cacheTotal, color: Theme.textTertiary),
            UsageSegment(label: "Output", value: u.output ?? 0, color: Theme.added),
            UsageSegment(label: "Reasoning", value: u.reasoning ?? 0, color: Color(hex: 0xB07CD8))
        ].filter { $0.value > 0 }
    }

    @ViewBuilder
    private func usageSection(_ usage: OCMessage.Usage) -> some View {
        let total = usage.resolvedTotal
        let segs = segments(usage)
        let limit = store.contextLimit
        let fraction = limit.map { min(total / Double($0), 1) }
        let warn = (fraction ?? 0) >= 0.8

        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Context usage")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                if let limit {
                    Text("\(formatted(total)) / \(formatted(Double(limit)))")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                } else {
                    Text("\(formatted(total)) tokens")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                }
            }

            // Proportional breakdown bar (input / cache / output / reasoning).
            GeometryReader { geo in
                HStack(spacing: 1) {
                    ForEach(segs) { seg in
                        Rectangle()
                            .fill(seg.color)
                            .frame(width: max(2, geo.size.width * (seg.value / max(total, 1))))
                    }
                    if let fraction, fraction < 1 {
                        Rectangle().fill(Theme.panelRaised)
                    }
                }
            }
            .frame(height: 8)
            .clipShape(RoundedRectangle(cornerRadius: 4))

            if let fraction {
                HStack(spacing: 6) {
                    if warn {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.removed)
                            .accessibilityHidden(true)
                    }
                    Text("\(Int((fraction * 100).rounded()))% of context window")
                        .font(.system(size: 11))
                        .foregroundStyle(warn ? Theme.removed : Theme.textSecondary)
                }
            }

            // Legend with per-bucket counts.
            VStack(spacing: 4) {
                ForEach(segs) { seg in
                    HStack(spacing: 8) {
                        Circle().fill(seg.color).frame(width: 8, height: 8)
                            .accessibilityHidden(true)
                        Text(seg.label)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textSecondary)
                        Spacer()
                        Text(formatted(seg.value))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.textPrimary)
                    }
                }
            }
        }
    }

    private func metricRow(_ label: String, value: String, color: Color = Theme.textPrimary) -> some View {
        HStack {
            Text(label).font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
            Spacer()
            Text(value).font(.system(size: 13, weight: .medium)).foregroundStyle(color)
        }
    }

    private func formatted(_ value: Double?) -> String {
        guard let value, value > 0 else { return "0" }
        return NumberFormatter.localizedString(from: NSNumber(value: Int(value)), number: .decimal)
    }

    private func comingSoon(icon: String, title: String, detail: String) -> some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: icon).font(.system(size: 30)).foregroundStyle(Theme.textTertiary)
            Text(title).font(.system(size: 14, weight: .semibold))
            Text(detail)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textTertiary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(24)
    }
}

// MARK: - ContextTodoRow

private struct ContextTodoRow: View {
    let todo: JSONValue

    private var status: String { todo["status"]?.stringValue ?? "pending" }
    private var content: String { todo["content"]?.stringValue ?? "" }
    private var priority: String? { todo["priority"]?.stringValue }

    private var isDone: Bool { status == "completed" || status == "cancelled" }

    private var glyph: String {
        switch status {
        case "completed": return "checkmark.circle.fill"
        case "in_progress": return "circle.lefthalf.filled"
        case "cancelled": return "xmark.circle"
        default: return "circle"
        }
    }

    private var glyphColor: Color {
        switch status {
        case "completed": return Theme.added
        case "in_progress": return Theme.accent
        default: return Theme.textTertiary
        }
    }

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

            Spacer(minLength: 0)

            if let priority, priority != "medium" {
                Text(priority.uppercased())
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(priority == "high" ? Theme.removed : Theme.textTertiary)
            }
        }
    }
}

// MARK: - ContextFileRow

private struct ContextFileRow: View {
    let file: ContextFile
    let onTap: () -> Void

    private var glyph: String {
        guard let mime = file.mime?.lowercased() else { return "doc" }
        if mime.hasPrefix("image/") { return "photo" }
        if mime.contains("pdf") { return "doc.richtext" }
        if mime.hasPrefix("text/") || mime.contains("json") || mime.contains("xml") { return "doc.text" }
        return "doc"
    }

    /// Image attachments carry their bytes inline (data URL); real files open in
    /// the viewer. Either way the row is actionable, so show a hint chevron.
    private var canOpen: Bool { file.isImage ? file.inlineData != nil : true }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                Image(systemName: glyph)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textTertiary)
                    .frame(width: 16)
                    .accessibilityHidden(true)
                Text(file.name)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
                if canOpen {
                    Image(systemName: file.isImage ? "eye" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.textTertiary)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!canOpen)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Context file \(file.name)")
        .accessibilityHint(canOpen ? (file.isImage ? "Preview image" : "Open file") : "")
    }
}

// MARK: - Image preview

struct ContextImagePreview: Identifiable {
    let id = UUID()
    let name: String
    let data: Data
}

private struct ContextImagePreviewSheet: View {
    let preview: ContextImagePreview
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if let image = UIImage(data: preview.data) {
                    ScrollView([.horizontal, .vertical]) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity)
                            .padding()
                    }
                } else {
                    Text("Unable to preview this attachment.")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.bg)
            .navigationTitle(preview.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
