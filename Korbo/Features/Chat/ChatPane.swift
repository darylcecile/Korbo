import SwiftUI

struct ChatPane: View {
    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var store: KorboStore
    @State private var draft: String = ""
    @State private var isSending = false

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
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .frame(maxWidth: 760)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 24)
                }
                .onChange(of: store.messages.count) { _, _ in
                    withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                }
            }
        }
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
                    Button { send() } label: {
                        Image(systemName: isSending ? "stop.circle" : "paperplane.fill")
                            .foregroundStyle(canSend && !draft.isEmpty ? Theme.accent : Theme.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSend || draft.trimmingCharacters(in: .whitespaces).isEmpty)
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
        isSending = true
        Task {
            await store.sendPrompt(text)
            isSending = false
        }
    }
}
