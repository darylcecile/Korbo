import SwiftUI

/// Renders a single message (user or assistant) and its ordered parts.
struct MessageView: View {
    let item: OCMessageItem

    var body: some View {
        if item.info.role == .user {
            userMessage
        } else {
            assistantMessage
        }
    }

    // MARK: User

    private var userMessage: some View {
        HStack {
            Spacer(minLength: 60)
            VStack(alignment: .trailing, spacing: 8) {
                ForEach(textParts) { part in
                    Text(part.text ?? "")
                        .font(.system(size: 14))
                        .textSelection(.enabled)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.panelRaised))
                }
                ForEach(fileParts) { part in
                    Label(part.filename ?? "attachment", systemImage: "paperclip")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
    }

    // MARK: Assistant

    private var assistantMessage: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "sparkle").foregroundStyle(Theme.accent)
                if let model = item.info.modelLabel {
                    Text(model).font(.system(size: 13, weight: .semibold))
                }
                if let agent = item.info.agent {
                    badge(agent, Theme.added)
                }
            }

            ForEach(item.parts) { part in
                partView(part)
            }

            if let error = item.info.error?.message {
                Text(error)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.removed)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Theme.removed.opacity(0.12)))
            }

            footer
        }
    }

    @ViewBuilder
    private func partView(_ part: OCPart) -> some View {
        switch part.type {
        case .text where part.isVisibleText:
            Text(part.text ?? "")
                .font(.system(size: 14))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        case .reasoning where !(part.text ?? "").isEmpty:
            ReasoningView(text: part.text ?? "")
        case .tool:
            ToolPartView(part: part)
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var footer: some View {
        if let duration = item.info.duration {
            HStack(spacing: 16) {
                Label(String(format: "%.1fs", duration), systemImage: "timer")
                if let completed = item.info.completedAt {
                    Text(completed, style: .time)
                }
            }
            .font(.system(size: 11))
            .foregroundStyle(Theme.textTertiary)
        }
    }

    // MARK: Helpers

    private var textParts: [OCPart] { item.parts.filter { $0.type == .text && !($0.text ?? "").isEmpty } }
    private var fileParts: [OCPart] { item.parts.filter { $0.type == .file } }

    private func badge(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 5).fill(color.opacity(0.18)))
            .foregroundStyle(color)
    }
}

/// Collapsible reasoning block (dimmed, expandable).
private struct ReasoningView: View {
    let text: String
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button { expanded.toggle() } label: {
                HStack(spacing: 6) {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                    Text("Reasoning").font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(Theme.textTertiary)
            }
            .buttonStyle(.plain)
            if expanded {
                Text(text)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                    .textSelection(.enabled)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.panel))
    }
}

/// Renders a tool invocation with its status and output.
private struct ToolPartView: View {
    let part: OCPart
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button { expanded.toggle() } label: {
                HStack(spacing: 8) {
                    statusIcon
                    Text(part.tool ?? "tool")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    if let title = part.state?.title {
                        Text(title)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textTertiary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            .buttonStyle(.plain)

            if expanded {
                if let output = part.state?.output, !output.isEmpty {
                    Text(output)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Theme.textSecondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if let error = part.state?.error, !error.isEmpty {
                    Text(error)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Theme.removed)
                        .textSelection(.enabled)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.panel))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 1))
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch part.state?.status ?? .unknown {
        case .completed:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.added)
        case .error:
            Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.removed)
        case .running:
            ProgressView().scaleEffect(0.6).frame(width: 14, height: 14)
        case .pending, .unknown:
            Image(systemName: "circle.dashed").foregroundStyle(Theme.textTertiary)
        }
    }
}
