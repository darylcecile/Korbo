import SwiftUI

struct ChatPane: View {
    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var store: KorboStore
    @State private var draft: String = ""

    private var session: OCSession? { store.selectedSession }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.border)
            messages
            composer
        }
        .background(Theme.bg)
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles").font(.system(size: 12))
                Text(modelLabel).font(.system(size: 13)).lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
            }
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 8).fill(Theme.panelRaised))

            VStack(alignment: .leading, spacing: 2) {
                Text(session?.title ?? "New session")
                    .font(.system(size: 15, weight: .semibold)).lineLimit(1)
                HStack(spacing: 6) {
                    if let project = session?.projectName {
                        Text(project)
                    }
                    if let session, session.additions > 0 || session.deletions > 0 {
                        Text("+\(session.additions)").foregroundStyle(Theme.added)
                        Text("-\(session.deletions)").foregroundStyle(Theme.removed)
                    }
                }
                .font(.system(size: 11))
                .foregroundStyle(Theme.textTertiary)
            }
            Spacer()

            Button { app.showRightSidebar.toggle() } label: {
                Image(systemName: "sidebar.right")
            }
            .buttonStyle(.plain)
        }
        .font(.system(size: 14))
        .foregroundStyle(Theme.textSecondary)
        .padding(.horizontal, 18).padding(.vertical, 12)
    }

    private var modelLabel: String {
        session?.model?.modelID ?? store.resolveModel()?.modelID ?? "Auto-discover"
    }

    // MARK: Messages

    @ViewBuilder
    private var messages: some View {
        if !store.status.isConnected {
            centeredHint(icon: "wifi.slash",
                         title: "Not connected",
                         subtitle: "Configure a connection to load conversations.")
        } else if store.selectedSessionID == nil {
            centeredHint(icon: "bubble.left.and.bubble.right",
                         title: "No session selected",
                         subtitle: "Pick a session on the left or start a new one.")
        } else if store.isLoadingMessages && store.messages.isEmpty {
            VStack { Spacer(); ProgressView(); Spacer() }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if store.messages.isEmpty {
            centeredHint(icon: "text.bubble",
                         title: "No messages yet",
                         subtitle: "Send a prompt to get started.")
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 20) {
                        ForEach(store.messages) { item in
                            MessageView(item: item)
                                .id(item.id)
                        }
                        ForEach(sessionPermissions) { permission in
                            PermissionCard(permission: permission) { response in
                                Task { await store.replyPermission(permission, response: response) }
                            }
                        }
                        if store.isGenerating {
                            TypingIndicator().id("typing")
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .frame(maxWidth: 760)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 24)
                }
                .onChange(of: streamSignature) { _, _ in
                    withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                }
            }
        }
    }

    /// Permission requests scoped to the selected session.
    private var sessionPermissions: [OCPermission] {
        store.pendingPermissions.filter { $0.sessionID == store.selectedSessionID }
    }

    /// Changes whenever messages are added or streamed text grows, so the list
    /// auto-scrolls during live token streaming (not just on new messages).
    private var streamSignature: String {
        let chars = store.messages.last?.parts.reduce(0) { $0 + ($1.text?.count ?? 0) } ?? 0
        return "\(store.messages.count)-\(chars)-\(store.isGenerating)"
    }

    private func centeredHint(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 30)).foregroundStyle(Theme.textTertiary)
            Text(title).font(.system(size: 15, weight: .semibold))
            Text(subtitle).font(.system(size: 13)).foregroundStyle(Theme.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    // MARK: Composer

    private var composer: some View {
        VStack(spacing: 0) {
            Divider().overlay(Theme.border)
            VStack(alignment: .leading, spacing: 10) {
                TextField("@ for files/agents;  / for commands;  ! for shell", text: $draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .lineLimit(1...6)
                    .disabled(!canSend)
                HStack(spacing: 14) {
                    Image(systemName: "plus.circle")
                    Image(systemName: "paperclip")
                    Spacer()
                    Text(modelLabel).foregroundStyle(Theme.textSecondary).lineLimit(1)
                    if store.isGenerating {
                        Button { Task { await store.abort() } } label: {
                            Image(systemName: "stop.fill").foregroundStyle(Theme.removed)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Button { send() } label: {
                            Image(systemName: "paperplane.fill")
                                .foregroundStyle(canSend && !draft.isEmpty ? Theme.accent : Theme.textTertiary)
                        }
                        .buttonStyle(.plain)
                        .disabled(!canSend || draft.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
            }
            .padding(16)
            .background(Theme.panelRaised)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .padding(16)
        }
    }

    private var canSend: Bool {
        store.status.isConnected && store.selectedSessionID != nil
    }

    private func send() {
        let text = draft
        guard canSend, !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        draft = ""
        Task { await store.sendPrompt(text) }
    }
}

/// Animated three-dot "assistant is generating" row shown while a run is active.
private struct TypingIndicator: View {
    @State private var phase = 0.0
    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3) { i in
                Circle()
                    .fill(Theme.textTertiary)
                    .frame(width: 7, height: 7)
                    .opacity(phase == Double(i) ? 1 : 0.3)
            }
        }
        .padding(.vertical, 6)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: false)) {
                phase = 2
            }
            Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { _ in
                phase = (phase + 1).truncatingRemainder(dividingBy: 3)
            }
        }
        .accessibilityLabel("Assistant is responding")
    }
}

/// Inline card for a tool permission request (allow once / always / reject).
private struct PermissionCard: View {
    let permission: OCPermission
    let onReply: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "lock.shield").foregroundStyle(Theme.accent)
                Text(permission.title ?? "Permission required")
                    .font(.system(size: 14, weight: .semibold))
            }
            if let pattern = permission.pattern ?? permission.type {
                Text(pattern)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(3)
            }
            HStack(spacing: 10) {
                permissionButton("Allow once", "once", Theme.accent)
                permissionButton("Always", "always", Theme.added)
                permissionButton("Reject", "reject", Theme.removed)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.panelRaised))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border, lineWidth: 1))
    }

    private func permissionButton(_ label: String, _ response: String, _ tint: Color) -> some View {
        Button { onReply(response) } label: {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 8).fill(tint.opacity(0.18)))
                .foregroundStyle(tint)
        }
        .buttonStyle(.plain)
    }
}
