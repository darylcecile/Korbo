import SwiftUI
import UIKit

/// Renders a single message (user or assistant) and its ordered parts.
struct MessageView: View {
    let item: OCMessageItem
    @EnvironmentObject private var store: KorboStore
    @ObservedObject private var speech = SpeechController.shared
    @State private var showCopyConfirm = false
    @State private var showDeleteConfirm = false

    var body: some View {
        content
            .opacity(store.isMessageReverted(item.id) ? 0.45 : 1)
            .confirmationDialog("Delete this message?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    Task { await store.deleteMessage(item.id) }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This permanently removes the message from the conversation.")
            }
    }

    @ViewBuilder
    private var content: some View {
        if !markerParts.isEmpty && !hasBubbleContent {
            // Structural-only message (e.g. a compaction marker): render as a
            // centered divider rather than an empty chat bubble.
            VStack(alignment: .leading, spacing: 8) {
                ForEach(markerParts) { part in
                    partView(part)
                }
            }
        } else if item.info.role == .user {
            userMessage
        } else {
            assistantMessage
        }
    }

    /// Parts that render as structural dividers rather than bubble content.
    private var markerParts: [OCPart] {
        item.parts.filter { [.compaction, .patch, .snapshot, .subtask].contains($0.type) }
    }

    /// Whether the message carries any user/assistant bubble content (text,
    /// reasoning, files, tools) as opposed to only structural markers.
    private var hasBubbleContent: Bool {
        item.parts.contains { part in
            switch part.type {
            case .compaction, .patch, .snapshot, .subtask, .stepStart, .stepFinish, .retry:
                return false
            default:
                return true
            }
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
                    AttachmentView(part: part)
                }
            }
            .contextMenu { userMessageContextMenu }
        }
    }

    @ViewBuilder
    private var userMessageContextMenu: some View {
        if !userTextContent.isEmpty {
            Button {
                UIPasteboard.general.string = userTextContent
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            ShareLink(item: userTextContent) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
        }
        historyMenuItems
    }

    // MARK: Assistant

    private var assistantMessage: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "sparkle").foregroundStyle(Theme.accent)
                    .accessibilityHidden(true)
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
        .contextMenu { assistantMessageContextMenu }
    }

    @ViewBuilder
    private var assistantMessageContextMenu: some View {
        if !visibleTextContent.isEmpty {
            Button {
                UIPasteboard.general.string = visibleTextContent
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            ShareLink(item: visibleTextContent) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
        }
        historyMenuItems
    }

    @ViewBuilder
    private var historyMenuItems: some View {
        Divider()
        Button {
            Task { await store.forkFromMessage(item.id) }
        } label: {
            Label("Fork from here", systemImage: "arrow.triangle.branch")
        }
        Button(role: .destructive) {
            Task { await store.revert(toMessageID: item.id) }
        } label: {
            Label("Revert to here", systemImage: "arrow.uturn.backward")
        }
        Button(role: .destructive) {
            showDeleteConfirm = true
        } label: {
            Label("Delete message", systemImage: "trash")
        }
    }

    @ViewBuilder
    private func partView(_ part: OCPart) -> some View {
        switch part.type {
        case .text where part.isVisibleText:
            MarkdownView(text: part.text ?? "")
        case .reasoning where !(part.text ?? "").isEmpty:
            ReasoningView(text: part.text ?? "")
        case .file:
            AttachmentView(part: part)
        case .tool:
            ToolPartView(part: part)
        case .compaction:
            PartMarkerView(
                icon: "arrow.triangle.merge",
                text: part.auto == true ? "Context auto-compacted" : "Context compacted")
        case .patch:
            PartMarkerView(icon: "doc.badge.gearshape", text: "Patch applied")
        case .snapshot:
            PartMarkerView(icon: "camera.aperture", text: "Snapshot")
        case .subtask:
            PartMarkerView(icon: "person.2", text: "Subagent task")
        // step-start / step-finish / retry are internal turn boundaries with no
        // user-facing content (token/cost data is surfaced in the footer + usage
        // ring), so they intentionally render nothing.
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var footer: some View {
        HStack(spacing: 16) {
            if let duration = item.info.duration {
                Label(String(format: "%.1fs", duration), systemImage: "timer")
                if let completed = item.info.completedAt {
                    Text(completed, style: .time)
                }
            }
            // TTS read-aloud and copy buttons: only show if there's visible text
            if !visibleTextContent.isEmpty {
                Spacer()
                Button {
                    UIPasteboard.general.string = visibleTextContent
                    showCopyConfirm = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        showCopyConfirm = false
                    }
                } label: {
                    Image(systemName: showCopyConfirm ? "checkmark" : "doc.on.doc")
                        .foregroundStyle(showCopyConfirm ? Theme.accent : Theme.textTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Copy message")
                Button {
                    speech.toggleSpeak(messageID: item.info.id, text: visibleTextContent)
                } label: {
                    Image(systemName: speech.speakingMessageID == item.info.id
                          ? "speaker.wave.2.fill"
                          : "speaker.wave.2")
                        .foregroundStyle(speech.speakingMessageID == item.info.id
                                         ? Theme.accent
                                         : Theme.textTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(speech.speakingMessageID == item.info.id ? "Stop speaking" : "Speak message")
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(Theme.textTertiary)
    }

    // MARK: Helpers

    private var textParts: [OCPart] { item.parts.filter { $0.type == .text && !($0.text ?? "").isEmpty } }
    private var fileParts: [OCPart] { item.parts.filter { $0.type == .file } }

    /// Joined user text parts for copy/share
    private var userTextContent: String {
        textParts.compactMap { $0.text }.joined(separator: "\n")
    }

    /// Joined visible text parts for TTS and copy/share (assistant)
    private var visibleTextContent: String {
        item.parts
            .filter { $0.type == .text && $0.isVisibleText }
            .compactMap { $0.text }
            .joined(separator: "\n")
    }

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
                        .accessibilityHidden(true)
                    Text("Reasoning").font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(Theme.textTertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Reasoning, \(expanded ? "expanded" : "collapsed")")
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

/// A slim centered divider used for structural conversation events (compaction,
/// patch, snapshot, subagent task) so they read as boundaries rather than chat
/// bubbles — mirroring the opencode GUI.
private struct PartMarkerView: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            line
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                    .accessibilityHidden(true)
                Text(text)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(Theme.textTertiary)
            line
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(text)
    }

    private var line: some View {
        Rectangle().fill(Theme.border).frame(height: 1)
    }
}

/// Renders a file part inline: images as a bounded thumbnail, other files as a
/// labelled chip. Supports both `data:` URLs (user-attached, base64) and
/// `http(s)://` URLs (server-served).
struct AttachmentView: View {
    let part: OCPart

    private var isImage: Bool { (part.mime ?? "").hasPrefix("image/") }

    var body: some View {
        if isImage, let image = decodedImage {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 320, maxHeight: 240, alignment: .leading)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border, lineWidth: 1))
        } else if isImage, let url = remoteURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case let .success(image):
                    image.resizable().scaledToFit()
                        .frame(maxWidth: 320, maxHeight: 240, alignment: .leading)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border, lineWidth: 1))
                case .failure:
                    chip
                default:
                    ProgressView().frame(width: 80, height: 60)
                }
            }
        } else {
            chip
        }
    }

    private var chip: some View {
        Label(part.filename ?? "attachment", systemImage: icon)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8).fill(Theme.panel))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 1))
    }

    private var icon: String {
        if isImage { return "photo" }
        let mime = part.mime ?? ""
        if mime.contains("pdf") { return "doc.richtext" }
        if mime.hasPrefix("text/") { return "doc.text" }
        return "paperclip"
    }

    /// Decode a `data:…;base64,…` URL into a UIImage.
    private var decodedImage: UIImage? {
        guard let urlString = part.url, urlString.hasPrefix("data:"),
              let comma = urlString.firstIndex(of: ","),
              urlString[..<comma].contains("base64") else { return nil }
        let b64 = String(urlString[urlString.index(after: comma)...])
        guard let data = Data(base64Encoded: b64) else { return nil }
        return UIImage(data: data)
    }

    private var remoteURL: URL? {
        guard let s = part.url, s.hasPrefix("http") else { return nil }
        return URL(string: s)
    }
}
