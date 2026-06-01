import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct ChatPane: View {
    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var store: KorboStore
    @State private var attachments: [ComposerAttachment] = []
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var showPhotoPicker = false
    @State private var showFileImporter = false
    @State private var isPinnedToBottom = true
    @State private var isExpandedComposer = false
    @FocusState private var composerFocused: Bool

    // Snippets library
    @StateObject private var snippetStore = SnippetStore.shared
    @State private var showSnippetsSheet = false

    // PencilKit sketch
    @State private var showScribbleSheet = false

    // Voice dictation
    @ObservedObject private var speech = SpeechController.shared

    // Starter chips shown when composer is empty and no messages exist.
    private let starters = [
        "Explain this codebase",
        "Find and fix a bug",
        "Write unit tests",
        "Review my recent changes",
        "Refactor for readability",
        "Add documentation"
    ]

    // Composer autocomplete (`@` files/agents, `/` commands).
    @State private var suggestions: [ComposerSuggestion] = []
    @State private var activeSuggestion = 0
    @State private var mentionToken = ""
    @State private var fileSearchTask: Task<Void, Never>?

    private var session: OCSession? { store.selectedSession }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.border)
            messages
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    composer
                }
        }
        .background(Theme.bg)
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            if app.layoutMode.isCompact {
                Button { app.toggleSessionsDrawer() } label: {
                    Image(systemName: "sidebar.left")
                }
                .buttonStyle(.plain)
            }

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

    // MARK: Model & agent pickers

    private var modelMenu: some View {
        Menu {
            Button {
                store.selectModel(nil)
            } label: {
                Label("Auto", systemImage: store.selectedModelOverride == nil ? "checkmark" : "sparkles")
            }
            ForEach(store.connectedProviders) { provider in
                Section(provider.name ?? provider.id) {
                    ForEach(models(of: provider), id: \.id) { model in
                        Button {
                            store.selectModel(OCModelRef(providerID: provider.id, modelID: model.id))
                        } label: {
                            if isActiveModel(provider.id, model.id) {
                                Label(model.name ?? model.id, systemImage: "checkmark")
                            } else {
                                Text(model.name ?? model.id)
                            }
                        }
                    }
                }
            }
        } label: {
            chip(icon: "sparkles", text: store.effectiveModelLabel)
        }
        .menuStyle(.borderlessButton)
        .disabled(!store.status.isConnected || store.connectedProviders.isEmpty)
    }

    @ViewBuilder
    private var agentMenu: some View {
        if !store.selectableAgents.isEmpty {
            Menu {
                ForEach(store.selectableAgents) { agent in
                    Button {
                        store.selectAgent(agent.name)
                    } label: {
                        if store.resolveAgent() == agent.name {
                            Label(agent.name, systemImage: "checkmark")
                        } else {
                            Text(agent.name)
                        }
                    }
                }
            } label: {
                chip(icon: "person.fill", text: store.resolveAgent() ?? "Agent")
            }
            .menuStyle(.borderlessButton)
            .disabled(!store.status.isConnected)
        }
    }

    private func chip(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 12))
            Text(text).font(.system(size: 13)).lineLimit(1)
            Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
        }
        .foregroundStyle(Theme.textSecondary)
        .padding(.horizontal, 10).padding(.vertical, 7)
        .contentShape(RoundedRectangle(cornerRadius: 8))
    }

    private func models(of provider: OCProvider) -> [OCModel] {
        (provider.models ?? [:]).values
            .sorted { ($0.name ?? $0.id).localizedCaseInsensitiveCompare($1.name ?? $1.id) == .orderedAscending }
    }

    private func isActiveModel(_ providerID: String, _ modelID: String) -> Bool {
        guard let ref = store.resolveModel() else { return false }
        return ref.providerID == providerID && ref.modelID == modelID
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
            GeometryReader { outer in
                ScrollViewReader { proxy in
                    ZStack(alignment: .bottomTrailing) {
                        ScrollView {
                            VStack(spacing: 0) {
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
                                }
                                // Kept OUTSIDE the LazyVStack so it stays
                                // instantiated when scrolled away from the bottom;
                                // a lazy sentinel would de-render and freeze its
                                // reported offset, hiding the scroll-to-bottom button.
                                Color.clear.frame(height: 1).id("bottom")
                                    .background(GeometryReader { g in
                                        Color.clear.preference(
                                            key: BottomOffsetKey.self,
                                            value: g.frame(in: .named("chatScroll")).maxY)
                                    })
                            }
                            .frame(maxWidth: 760)
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 24)
                        }
                        .coordinateSpace(name: "chatScroll")
                        .onPreferenceChange(BottomOffsetKey.self) { maxY in
                            // Pinned when the bottom sentinel sits within the
                            // visible viewport (plus a little slack).
                            isPinnedToBottom = maxY <= outer.size.height + 80
                        }
                        .onChange(of: streamSignature) { _, _ in
                            guard isPinnedToBottom else { return }
                            withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                        }

                        if !isPinnedToBottom {
                            Button {
                                withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                            } label: {
                                Image(systemName: "arrow.down")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(Theme.textPrimary)
                                    .padding(12)
                                    .background(Circle().fill(Theme.panelRaised))
                                    .overlay(Circle().stroke(Theme.border, lineWidth: 1))
                                    .shadow(color: .black.opacity(0.3), radius: 6, y: 2)
                            }
                            .buttonStyle(.plain)
                            .padding(.trailing, 20)
                            .padding(.bottom, 16)
                            .transition(.opacity.combined(with: .scale))
                            .accessibilityLabel("Scroll to bottom")
                        }
                    }
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

    /// Show starter chips only when draft is empty AND no messages in the current session.
    private var shouldShowStarters: Bool {
        app.composerDraft.trimmingCharacters(in: .whitespaces).isEmpty && store.messages.isEmpty && canSend
    }

    private var starterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(starters, id: \.self) { starter in
                    Button {
                        app.composerDraft = starter
                        composerFocused = true
                    } label: {
                        Text(starter)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.textSecondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(RoundedRectangle(cornerRadius: 16).fill(Theme.panel))
                            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.border, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var composer: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                if !suggestions.isEmpty {
                    suggestionList
                }
                if shouldShowStarters {
                    starterChips
                }
                if !attachments.isEmpty {
                    attachmentStrip
                }
                TextField("@ for files/agents;  / for commands;  ! for shell", text: $app.composerDraft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .lineLimit(1...10)
                    .disabled(!canSend)
                    .focused($composerFocused)
                    .onKeyPress(.return, phases: .down) { keyPress in
                        // Shift+Enter inserts newline (default behavior); plain Enter sends.
                        if keyPress.modifiers.contains(.shift) {
                            return .ignored
                        }
                        if canSubmit { send() }
                        return .handled
                    }
                    .onChange(of: app.composerDraft) { _, text in
                        updateSuggestions(for: text)
                    }
                    .onChange(of: composerFocused) { _, focused in
                        if !focused { clearSuggestions() }
                    }
                HStack(spacing: 14) {
                    // Consolidated "add content" menu
                    Menu {
                        Button { showPhotoPicker = true } label: {
                            Label("Photo", systemImage: "photo")
                        }
                        Button { showFileImporter = true } label: {
                            Label("File", systemImage: "paperclip")
                        }
                        Button { showScribbleSheet = true } label: {
                            Label("Draw", systemImage: "pencil.tip.crop.circle")
                        }
                        Button { showSnippetsSheet = true } label: {
                            Label("Snippets", systemImage: "bookmark")
                        }
                        Button { toggleDictation() } label: {
                            Label(speech.isDictating ? "Stop dictation" : "Dictate",
                                  systemImage: speech.isDictating ? "mic.fill" : "mic")
                        }
                    } label: {
                        Image(systemName: speech.isDictating ? "mic.fill" : "plus")
                            .foregroundStyle(speech.isDictating ? Theme.removed : Theme.textSecondary)
                            .frame(width: 30, height: 30)
                            .contentShape(Rectangle())
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .disabled(!canSend)
                    .accessibilityLabel("Add attachment")
                    .padding(.leading, -4)

                    Button { isExpandedComposer = true } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .frame(width: 30, height: 30)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSend)
                    .accessibilityLabel("Expand composer")
                    Spacer()
                    modelMenu
                    agentMenu
                    if store.isGenerating {
                        Button { Task { await store.abort() } } label: {
                            Image(systemName: "stop.fill").foregroundStyle(Theme.removed)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Button { send() } label: {
                            Image(systemName: "paperplane.fill")
                                .foregroundStyle(canSubmit ? Theme.accent : Theme.textTertiary)
                        }
                        .buttonStyle(.plain)
                        .disabled(!canSubmit)
                        .keyboardShortcut(.return, modifiers: .command)
                    }
                }
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 10)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Theme.border.opacity(0.5), lineWidth: 0.5)
                    .allowsHitTesting(false)
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
            .padding(.top, 8)
        }
        .onChange(of: photoItems) { _, items in
            guard !items.isEmpty else { return }
            Task { await loadPhotos(items) }
        }
        .onChange(of: app.focusComposerToken) { _, _ in
            if canSend { composerFocused = true }
        }
        .onChange(of: speech.partialTranscript) { _, transcript in
            // Live update composer draft with dictation transcript
            if speech.isDictating {
                app.composerDraft = transcript
            }
        }
        .fileImporter(isPresented: $showFileImporter,
                      allowedContentTypes: [.item],
                      allowsMultipleSelection: true) { result in
            if case let .success(urls) = result { loadFiles(urls) }
        }
        .sheet(isPresented: $isExpandedComposer) {
            ExpandedComposerSheet(
                draft: $app.composerDraft,
                canSubmit: canSubmit,
                onSend: {
                    send()
                    isExpandedComposer = false
                },
                onDismiss: { isExpandedComposer = false }
            )
        }
        .sheet(isPresented: $showSnippetsSheet) {
            SnippetsSheet(store: snippetStore) { snippet in
                insertSnippet(snippet)
            }
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $photoItems,
                      maxSelectionCount: 4, matching: .images)
        .sheet(isPresented: $showScribbleSheet) {
            ScribbleSheet { image in
                attachSketch(image)
            }
        }
    }

    private var attachmentStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(attachments) { attachment in
                    AttachmentChip(attachment: attachment) {
                        attachments.removeAll { $0.id == attachment.id }
                    }
                }
            }
        }
    }

    // MARK: Autocomplete

    private var suggestionList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, item in
                Button {
                    select(item)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: item.icon)
                            .font(.system(size: 13))
                            .foregroundStyle(item.tint)
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.title)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Theme.textPrimary)
                                .lineLimit(1)
                            if let subtitle = item.subtitle, !subtitle.isEmpty {
                                Text(subtitle)
                                    .font(.system(size: 11))
                                    .foregroundStyle(Theme.textTertiary)
                                    .lineLimit(1)
                            }
                        }
                        Spacer(minLength: 4)
                        Text(item.kindLabel)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 7)
                            .fill(index == activeSuggestion ? Theme.panel : .clear)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.bg))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border, lineWidth: 1))
        .frame(maxHeight: 240)
    }

    private func clearSuggestions() {
        fileSearchTask?.cancel()
        suggestions = []
        activeSuggestion = 0
        mentionToken = ""
    }

    /// Inspect the trailing token of the draft and surface `@` (files/agents) or
    /// `/` (commands) suggestions. SwiftUI gives no cursor position, so we treat
    /// the last whitespace-delimited token as the active one (cursor-at-end).
    private func updateSuggestions(for text: String) {
        guard canSend else { clearSuggestions(); return }
        let token: Substring
        let isFirstToken: Bool
        if let space = text.lastIndex(where: { $0 == " " || $0 == "\n" }) {
            token = text[text.index(after: space)...]
            isFirstToken = false
        } else {
            token = text[...]
            isFirstToken = true
        }

        if token.hasPrefix("/"), isFirstToken {
            let query = String(token.dropFirst()).lowercased()
            let matches = store.commands
                .filter { query.isEmpty || $0.name.lowercased().contains(query) }
                .prefix(8)
                .map { ComposerSuggestion(kind: .command, value: $0.name,
                                          title: "/\($0.name)", subtitle: $0.description) }
            suggestions = Array(matches)
            activeSuggestion = 0
            mentionToken = ""
        } else if token.hasPrefix("@") {
            let query = String(token.dropFirst())
            mentionToken = query
            let agentMatches = store.selectableAgents
                .filter { query.isEmpty || $0.name.lowercased().contains(query.lowercased()) }
                .prefix(4)
                .map { ComposerSuggestion(kind: .agent, value: $0.name,
                                          title: "@\($0.name)", subtitle: $0.description) }
            suggestions = Array(agentMatches)
            activeSuggestion = 0
            scheduleFileSuggestions(query: query, agents: Array(agentMatches))
        } else {
            clearSuggestions()
        }
    }

    private func scheduleFileSuggestions(query: String, agents: [ComposerSuggestion]) {
        fileSearchTask?.cancel()
        guard !query.isEmpty else { return }
        fileSearchTask = Task {
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard !Task.isCancelled else { return }
            let paths = await store.findFiles(query)
            guard !Task.isCancelled, mentionToken == query else { return }
            let fileMatches = paths.prefix(8).map { path in
                ComposerSuggestion(kind: .file, value: path,
                                   title: (path as NSString).lastPathComponent, subtitle: path)
            }
            suggestions = agents + fileMatches
        }
    }

    private func select(_ item: ComposerSuggestion) {
        let prefix = draftPrefixBeforeTrailingToken(app.composerDraft)
        switch item.kind {
        case .command:
            app.composerDraft = "/\(item.value) "
        case .agent:
            store.selectAgent(item.value)
            app.composerDraft = prefix
        case .file:
            let path = item.value
            app.composerDraft = prefix
            Task {
                if let attachment = await store.fileMentionAttachment(path: path) {
                    if !attachments.contains(where: { $0.filename == attachment.filename }) {
                        attachments.append(attachment)
                    }
                } else {
                    // Binary/unreadable: fall back to a plain-text path reference.
                    app.composerDraft = prefix + "@\(path) "
                }
            }
        }
        clearSuggestions()
        composerFocused = true
    }

    /// Everything in the draft up to and including the whitespace before the
    /// trailing token (empty when the token is the whole draft).
    private func draftPrefixBeforeTrailingToken(_ text: String) -> String {
        if let space = text.lastIndex(where: { $0 == " " || $0 == "\n" }) {
            return String(text[...space])
        }
        return ""
    }

    private var canSend: Bool {
        store.status.isConnected && store.selectedSessionID != nil
    }

    private var canSubmit: Bool {
        canSend && (!app.composerDraft.trimmingCharacters(in: .whitespaces).isEmpty || !attachments.isEmpty)
    }

    private func send() {
        let text = app.composerDraft
        let toSend = attachments
        guard canSubmit else { return }
        clearSuggestions()
        app.composerDraft = ""
        attachments = []
        // Route a bare `/command` invocation to the command endpoint; otherwise
        // send a normal prompt.
        if toSend.isEmpty, let cmd = store.parseCommand(text) {
            Task { await store.runCommand(cmd.name, arguments: cmd.arguments) }
        } else {
            Task { await store.sendPrompt(text, attachments: toSend) }
        }
    }

    // MARK: Attachment loading

    @MainActor
    private func loadPhotos(_ items: [PhotosPickerItem]) async {
        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
            // Re-encode to a known mime so the server always gets a valid image.
            let (bytes, mime, ext): (Data, String, String)
            if let image = UIImage(data: data), let jpeg = image.jpegData(compressionQuality: 0.85) {
                (bytes, mime, ext) = (jpeg, "image/jpeg", "jpg")
            } else {
                (bytes, mime, ext) = (data, "image/png", "png")
            }
            let name = "image-\(attachments.count + 1).\(ext)"
            attachments.append(ComposerAttachment(
                filename: name, mime: mime,
                dataURL: "data:\(mime);base64,\(bytes.base64EncodedString())"))
        }
        photoItems = []
    }

    private func loadFiles(_ urls: [URL]) {
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else { continue }
            let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType
                ?? "application/octet-stream"
            attachments.append(ComposerAttachment(
                filename: url.lastPathComponent, mime: mime,
                dataURL: "data:\(mime);base64,\(data.base64EncodedString())"))
        }
    }

    // MARK: Snippets

    private func insertSnippet(_ snippet: Snippet) {
        if app.composerDraft.trimmingCharacters(in: .whitespaces).isEmpty {
            app.composerDraft = snippet.text
        } else {
            app.composerDraft += "\n\n" + snippet.text
        }
        composerFocused = true
    }

    // MARK: Sketch attachment

    @State private var sketchIndex = 0

    private func attachSketch(_ image: UIImage) {
        guard let jpeg = image.jpegData(compressionQuality: 0.85) else { return }
        sketchIndex += 1
        let filename = "sketch-\(sketchIndex).jpg"
        let dataURL = "data:image/jpeg;base64,\(jpeg.base64EncodedString())"
        attachments.append(ComposerAttachment(filename: filename, mime: "image/jpeg", dataURL: dataURL))
    }

    // MARK: Dictation

    private func toggleDictation() {
        if speech.isDictating {
            speech.stopDictation()
        } else {
            speech.startDictation()
        }
    }
}

/// A removable chip for a staged composer attachment (image thumbnail or file icon).
private struct AttachmentChip: View {
    let attachment: ComposerAttachment
    let onRemove: () -> Void

    private var thumbnail: UIImage? {
        guard attachment.mime.hasPrefix("image/"),
              let comma = attachment.dataURL.firstIndex(of: ","),
              let data = Data(base64Encoded: String(attachment.dataURL[attachment.dataURL.index(after: comma)...]))
        else { return nil }
        return UIImage(data: data)
    }

    var body: some View {
        HStack(spacing: 8) {
            if let thumbnail {
                Image(uiImage: thumbnail)
                    .resizable().scaledToFill()
                    .frame(width: 28, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                Image(systemName: "doc")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 28, height: 28)
            }
            Text(attachment.filename)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.panel))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 1))
    }
}

/// Preference key reporting the bottom sentinel's position so the chat can tell
/// whether the user is scrolled to the bottom.
private struct BottomOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// A composer autocomplete suggestion (`@` file/agent or `/` command).
struct ComposerSuggestion: Identifiable {
    enum Kind { case file, agent, command }
    let kind: Kind
    let value: String
    let title: String
    var subtitle: String?
    var id: String { "\(kindLabel):\(value)" }

    var icon: String {
        switch kind {
        case .file:    return "doc.text"
        case .agent:   return "person.fill"
        case .command: return "terminal"
        }
    }
    var tint: Color {
        switch kind {
        case .file:    return Theme.textSecondary
        case .agent:   return Theme.accent
        case .command: return Theme.added
        }
    }
    var kindLabel: String {
        switch kind {
        case .file:    return "file"
        case .agent:   return "agent"
        case .command: return "command"
        }
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

/// Full-screen focus editor for composing long prompts.
private struct ExpandedComposerSheet: View {
    @Binding var draft: String
    let canSubmit: Bool
    let onSend: () -> Void
    let onDismiss: () -> Void
    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()
                VStack(spacing: 0) {
                    TextEditor(text: $draft)
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.textPrimary)
                        .scrollContentBackground(.hidden)
                        .padding(16)
                        .focused($isFocused)
                }
            }
            .navigationTitle("Compose")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { onDismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        onSend()
                    } label: {
                        Image(systemName: "paperplane.fill")
                            .foregroundStyle(canSubmit ? Theme.accent : Theme.textTertiary)
                    }
                    .disabled(!canSubmit)
                }
            }
            .toolbarBackground(Theme.panelRaised, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .onAppear { isFocused = true }
    }
}
