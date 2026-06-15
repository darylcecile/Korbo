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
    /// The session id whose transcript we've already jumped to the bottom for.
    /// Drives a one-time scroll-to-end when a session's backlog first appears, so
    /// reopening an existing long session lands on the latest message instead of
    /// stranded at the very top.
    @State private var initialScrollDoneFor: String?
    @State private var isExpandedComposer = false
    @State private var isDropTargeted = false
    @FocusState private var composerFocused: Bool

    /// iPhone gets a larger, more touch-friendly composer (bigger font, taller
    /// default input, larger toolbar controls). iPad is left as-is because we
    /// expect a hardware keyboard/trackpad there.
    private var isPhone: Bool {
        UIDevice.current.userInterfaceIdiom == .phone
    }

    /// Corner radius for the composer's glass container. On iPhone the bar is
    /// inset only ~16pt from the display edge, so a rounder corner sits roughly
    /// concentric with the device's own (much rounder) screen corners; on iPad
    /// the subtler 18pt corner is kept.
    private var composerCornerRadius: CGFloat {
        isPhone ? 34 : 18
    }

    // Find-in-conversation (local to this view; no app-level state).
    @State private var isSearching = false
    @State private var searchQuery = ""
    @State private var searchMatchIDs: [String] = []
    @State private var currentMatchIndex = 0
    @State private var searchScrollTick = 0
    @FocusState private var searchFocused: Bool

    // Snippets library
    @StateObject private var snippetStore = SnippetStore.shared
    @State private var showSnippetsSheet = false

    // PencilKit sketch
    @State private var showScribbleSheet = false
    // Image attachment currently being marked up (drives the markup sheet).
    @State private var markupTarget: ComposerAttachment?

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
            searchBar
            messages
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    composer
                }
        }
        .background(Theme.bg)
        .onAppear { app.bindDraft(to: store.selectedSessionID) }
        .onChange(of: store.selectedSessionID) { _, id in
            app.bindDraft(to: id)
            closeSearch()
        }
        .onChange(of: searchQuery) { _, _ in recomputeMatches() }
        .onChange(of: store.messages) { _, _ in
            if isSearching { recomputeMatches() }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            if app.layoutMode.isCompact {
                Button { app.toggleSessionsDrawer() } label: {
                    Image(systemName: "sidebar.left")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Toggle sessions sidebar")
            }

            contextRing

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

            if store.selectedSessionID != nil && !store.messages.isEmpty {
                Button {
                    toggleSearch()
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .buttonStyle(.plain)
                .help("Find in conversation")
                .accessibilityLabel("Find in conversation")

                Button {
                    Task { await store.summarize() }
                } label: {
                    if store.isSummarizing {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "rectangle.compress.vertical")
                    }
                }
                .buttonStyle(.plain)
                .disabled(store.isSummarizing)
                .help("Summarize conversation")
                .accessibilityLabel("Summarize conversation")
            }

            Button { app.showRightSidebar.toggle() } label: {
                Image(systemName: "sidebar.right")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Toggle context sidebar")
        }
        .font(.system(size: 14))
        .foregroundStyle(Theme.textSecondary)
        .padding(.horizontal, 18).padding(.vertical, 12)
    }

    // MARK: Find-in-conversation

    @ViewBuilder
    private var searchBar: some View {
        if isSearching {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textTertiary)
                    .accessibilityHidden(true)

                TextField("Find in conversation", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.textPrimary)
                    .focused($searchFocused)
                    .submitLabel(.search)
                    .onSubmit { goToMatch(1) }
                    .accessibilityLabel("Search text")

                if !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty {
                    Text(matchCountLabel)
                        .font(.system(size: 12))
                        .monospacedDigit()
                        .foregroundStyle(Theme.textTertiary)
                        .accessibilityLabel(matchCountLabel)
                }

                Button { goToMatch(-1) } label: {
                    Image(systemName: "chevron.up")
                }
                .buttonStyle(.plain)
                .disabled(searchMatchIDs.isEmpty)
                .accessibilityLabel("Previous match")

                Button { goToMatch(1) } label: {
                    Image(systemName: "chevron.down")
                }
                .buttonStyle(.plain)
                .disabled(searchMatchIDs.isEmpty)
                .accessibilityLabel("Next match")

                Button { closeSearch() } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close search")
            }
            .font(.system(size: 14))
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 18).padding(.vertical, 8)
            .background(Theme.panel)
            .overlay(Divider().overlay(Theme.border), alignment: .bottom)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private var matchCountLabel: String {
        searchMatchIDs.isEmpty ? "No results"
            : "\(currentMatchIndex + 1)/\(searchMatchIDs.count)"
    }

    /// The message id of the currently selected match, if any.
    private var currentMatchID: String? {
        guard isSearching, searchMatchIDs.indices.contains(currentMatchIndex) else { return nil }
        return searchMatchIDs[currentMatchIndex]
    }

    /// Flattened, searchable text for a message (visible text/reasoning plus
    /// tool titles and outputs already loaded in the store).
    private func searchableText(_ item: OCMessageItem) -> String {
        var pieces: [String] = []
        for part in item.parts {
            if let text = part.text, !text.isEmpty { pieces.append(text) }
            if let title = part.state?.title, !title.isEmpty { pieces.append(title) }
            if let output = part.state?.output, !output.isEmpty { pieces.append(output) }
        }
        return pieces.joined(separator: "\n")
    }

    private func recomputeMatches() {
        let query = searchQuery.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else {
            searchMatchIDs = []
            currentMatchIndex = 0
            return
        }
        let ids = store.messages
            .filter { searchableText($0).range(of: query, options: .caseInsensitive) != nil }
            .map(\.id)
        searchMatchIDs = ids
        currentMatchIndex = 0
        if !ids.isEmpty { searchScrollTick &+= 1 }
    }

    private func goToMatch(_ delta: Int) {
        guard !searchMatchIDs.isEmpty else { return }
        currentMatchIndex = (currentMatchIndex + delta + searchMatchIDs.count) % searchMatchIDs.count
        searchScrollTick &+= 1
    }

    private func toggleSearch() {
        if isSearching {
            closeSearch()
        } else {
            withAnimation(.easeInOut(duration: 0.2)) { isSearching = true }
            DispatchQueue.main.async { searchFocused = true }
        }
    }

    private func closeSearch() {
        withAnimation(.easeInOut(duration: 0.2)) { isSearching = false }
        searchQuery = ""
        searchMatchIDs = []
        currentMatchIndex = 0
        searchFocused = false
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
                .accessibilityHidden(true)
            Text(text).font(.system(size: 13)).lineLimit(1)
            Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
                .accessibilityHidden(true)
        }
        .foregroundStyle(Theme.textSecondary)
        .padding(.horizontal, 10).padding(.vertical, 7)
        .contentShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: Reasoning-effort selector

    @ViewBuilder
    private var reasoningMenu: some View {
        if let model = store.effectiveModelObject(), model.supportsReasoning {
            Menu {
                ForEach(model.variantNames, id: \.self) { name in
                    Button {
                        store.selectReasoningVariant(name)
                    } label: {
                        if store.resolveVariant() == name {
                            Label(variantLabel(name), systemImage: "checkmark")
                        } else {
                            Text(variantLabel(name))
                        }
                    }
                }
            } label: {
                chip(icon: "brain", text: variantLabel(store.resolveVariant() ?? "Medium"))
            }
            .menuStyle(.borderlessButton)
            .disabled(!store.status.isConnected)
        }
    }

    private func variantLabel(_ variant: String) -> String {
        switch variant.lowercased() {
        case "none": return "None"
        case "low": return "Low"
        case "medium": return "Medium"
        case "high": return "High"
        case "xhigh": return "X-High"
        default: return variant.capitalized
        }
    }

    // MARK: Context-usage ring

    @ViewBuilder
    private var contextRing: some View {
        if let usage = store.latestUsage,
           let limit = store.contextLimit, limit > 0 {
            let fraction = min(usage.resolvedTotal / Double(limit), 1.0)
            Button {
                app.showRightSidebar = true
            } label: {
                ZStack {
                    Circle()
                        .stroke(Theme.border, lineWidth: 3)
                    Circle()
                        .trim(from: 0, to: fraction)
                        .stroke(usageColor(fraction), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("\(Int(fraction * 100))")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                }
                .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Context usage \(Int(fraction * 100)) percent")
        }
    }

    private func usageColor(_ fraction: Double) -> Color {
        if fraction < 0.6 { return Theme.added }
        if fraction < 0.85 { return Theme.accent }
        return Theme.removed
    }

    private func models(of provider: OCProvider) -> [OCModel] {
        (provider.models ?? [:]).values
            .sorted { ($0.name ?? $0.id).localizedCaseInsensitiveCompare($1.name ?? $1.id) == .orderedAscending }
    }

    private func isActiveModel(_ providerID: String, _ modelID: String) -> Bool {
        guard let ref = store.resolveModel() else { return false }
        return ref.providerID == providerID && ref.modelID == modelID
    }

    // MARK: Reverted banner

    private var revertedBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.uturn.backward.circle")
                .foregroundStyle(Theme.removed)
            Text(revertedBannerText)
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            Button("Undo") {
                Task { await store.unrevert() }
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Theme.accent)
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.panelRaised))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border, lineWidth: 1))
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var revertedBannerText: String {
        let count = store.revertedMessageCount
        if count > 0 {
            return "Reverted — \(count) message\(count == 1 ? "" : "s") hidden"
        }
        return "Conversation reverted"
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
                                    ForEach(Array(store.messages.enumerated()), id: \.element.id) { index, item in
                                        MessageView(
                                            item: item,
                                            showHeader: showsHeader(at: index),
                                            showFooter: showsFooter(at: index)
                                        )
                                            .id(item.id)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 12)
                                                    .stroke(Theme.accent, lineWidth: 2)
                                                    .padding(-6)
                                                    .opacity(item.id == currentMatchID ? 1 : 0)
                                                    .animation(.easeInOut(duration: 0.2), value: currentMatchID)
                                                    .allowsHitTesting(false)
                                            )
                                    }
                                    ForEach(sessionPermissions) { permission in
                                        PermissionCard(permission: permission) { response in
                                            Task { await store.replyPermission(permission, response: response) }
                                        }
                                    }
                                    ForEach(sessionQuestions) { question in
                                        QuestionCard(question: question)
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
                        .overlay(alignment: .top) {
                            if store.isReverted {
                                revertedBanner
                                    .transition(.move(edge: .top).combined(with: .opacity))
                            }
                        }
                        .onPreferenceChange(BottomOffsetKey.self) { maxY in
                            // Pinned when the bottom sentinel sits within the
                            // visible viewport (plus a little slack).
                            isPinnedToBottom = maxY <= outer.size.height + 80
                        }
                        .onChange(of: streamSignature) { _, _ in
                            // A freshly-opened session: jump straight to the end
                            // once before falling back to the pinned-scroll path.
                            if scrollToBottomOnOpen(proxy) { return }
                            guard isPinnedToBottom else { return }
                            withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                        }
                        .onChange(of: store.selectedSessionID) { _, _ in
                            // Re-arm the one-time scroll for the next session.
                            initialScrollDoneFor = nil
                        }
                        .onAppear {
                            // When the transcript appears with a backlog already
                            // loaded (app relaunch, or switching to a cached
                            // session) no streamSignature change fires, so do the
                            // initial scroll-to-end here too.
                            scrollToBottomOnOpen(proxy)
                        }
                        .onChange(of: searchScrollTick) { _, _ in
                            guard let target = currentMatchID else { return }
                            withAnimation { proxy.scrollTo(target, anchor: .center) }
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

    // MARK: Message grouping

    /// Two assistant messages belong to the same response group when both are
    /// from the assistant using the same model + agent. opencode emits one
    /// message per agent step (text → tool → tool → text …), so a single user
    /// turn becomes many consecutive assistant messages; grouping them lets us
    /// show the model header once and the token footer once per response.
    private func sameAssistantGroup(_ a: OCMessageItem, _ b: OCMessageItem) -> Bool {
        a.info.role == .assistant && b.info.role == .assistant
            && a.info.modelLabel == b.info.modelLabel
            && a.info.agent == b.info.agent
    }

    /// Show the model/agent header only at the start of an assistant group
    /// (and always for user messages).
    private func showsHeader(at index: Int) -> Bool {
        let msgs = store.messages
        guard msgs[index].info.role == .assistant else { return true }
        guard index > 0 else { return true }
        return !sameAssistantGroup(msgs[index - 1], msgs[index])
    }

    /// Show the duration/token/cost footer only at the end of an assistant
    /// group (and always for user messages, which have no footer anyway).
    private func showsFooter(at index: Int) -> Bool {
        let msgs = store.messages
        guard msgs[index].info.role == .assistant else { return true }
        guard index < msgs.count - 1 else { return true }
        return !sameAssistantGroup(msgs[index], msgs[index + 1])
    }

    /// Question requests scoped to the selected session.
    private var sessionQuestions: [OCQuestion] {
        store.pendingQuestions.filter { $0.sessionID == store.selectedSessionID }
    }

    /// Changes whenever messages are added or streamed text grows, so the list
    /// auto-scrolls during live token streaming (not just on new messages).
    private var streamSignature: String {
        let chars = store.messages.last?.parts.reduce(0) { $0 + ($1.text?.count ?? 0) } ?? 0
        return "\(store.messages.count)-\(chars)-\(store.isGenerating)"
    }

    /// Jump to the latest message the first time a session's backlog is shown.
    ///
    /// The live auto-scroll is gated on `isPinnedToBottom`, which is `false` for a
    /// long conversation that loads scrolled to the top — so without this an
    /// existing session reopens stranded at its very first message. Runs at most
    /// once per session (tracked by `initialScrollDoneFor`); the async second pass
    /// corrects any underscroll once the lazy rows above the sentinel are measured.
    /// Returns whether it performed the initial scroll.
    @discardableResult
    private func scrollToBottomOnOpen(_ proxy: ScrollViewProxy) -> Bool {
        guard initialScrollDoneFor != store.selectedSessionID, !store.messages.isEmpty else { return false }
        initialScrollDoneFor = store.selectedSessionID
        isPinnedToBottom = true
        proxy.scrollTo("bottom", anchor: .bottom)
        DispatchQueue.main.async { proxy.scrollTo("bottom", anchor: .bottom) }
        return true
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
                    .font(.system(size: isPhone ? 17 : 14))
                    .lineLimit(isPhone ? 3...12 : 1...10)
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
                        if canPasteFromClipboard {
                            Button { pasteFromClipboard() } label: {
                                Label("Paste", systemImage: "doc.on.clipboard")
                            }
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
                    reasoningMenu
                    if store.isGenerating {
                        Button { Task { await store.abort() } } label: {
                            Image(systemName: "stop.fill").foregroundStyle(Theme.removed)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Stop generation")
                    } else {
                        Button { send() } label: {
                            Image(systemName: "paperplane.fill")
                                .foregroundStyle(canSubmit ? Theme.accent : Theme.textTertiary)
                        }
                        .buttonStyle(.plain)
                        .disabled(!canSubmit)
                        .keyboardShortcut(.return, modifiers: .command)
                        .accessibilityLabel("Send message")
                    }
                }
                .font(.system(size: isPhone ? 15 : 13))
                .foregroundStyle(Theme.textSecondary)
            }
            .padding(.horizontal, 16)
            .padding(.top, isPhone ? 14 : 12)
            .padding(.bottom, isPhone ? 12 : 10)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: composerCornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: composerCornerRadius, style: .continuous)
                    .stroke(isDropTargeted ? Theme.accent : Theme.border.opacity(0.5),
                            lineWidth: isDropTargeted ? 1.5 : 0.5)
                    .allowsHitTesting(false)
            )
            .onDrop(of: [.image, .fileURL, .item], isTargeted: $isDropTargeted) { providers in
                handleDrop(providers)
            }
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
        .sheet(item: $markupTarget) { target in
            if let base = target.decodedImage {
                ScribbleSheet(backgroundImage: base) { annotated in
                    replaceWithMarkup(target, annotated: annotated)
                }
            }
        }
    }

    private var attachmentStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(attachments) { attachment in
                    AttachmentChip(attachment: attachment,
                                   onMarkup: attachment.isImage ? { markupTarget = attachment } : nil) {
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
        app.clearDraft(for: store.selectedSessionID)
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
            attachImageData(data)
        }
        photoItems = []
    }

    /// Re-encode arbitrary image bytes to a known mime so the server always gets a
    /// valid image, then append as an attachment.
    @MainActor
    private func attachImageData(_ data: Data) {
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

    @MainActor
    private func attachImage(_ image: UIImage) {
        guard let jpeg = image.jpegData(compressionQuality: 0.85) else { return }
        attachImageData(jpeg)
    }

    @MainActor
    private func attachFileData(_ data: Data, filename: String, mime: String) {
        attachments.append(ComposerAttachment(
            filename: filename, mime: mime,
            dataURL: "data:\(mime);base64,\(data.base64EncodedString())"))
    }

    private func loadFiles(_ urls: [URL]) {
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else { continue }
            let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType
                ?? "application/octet-stream"
            attachFileData(data, filename: url.lastPathComponent, mime: mime)
        }
    }

    // MARK: Paste & drag-and-drop

    private var canPasteFromClipboard: Bool {
        let pb = UIPasteboard.general
        return pb.hasImages || pb.hasStrings || pb.hasURLs
    }

    /// Pull image(s) or text out of the system pasteboard. Images become
    /// attachments; text is appended to the draft.
    private func pasteFromClipboard() {
        let pb = UIPasteboard.general
        if pb.hasImages {
            for case let image as UIImage in pb.images ?? [] {
                attachImage(image)
            }
        } else if pb.hasStrings, let text = pb.string {
            if app.composerDraft.trimmingCharacters(in: .whitespaces).isEmpty {
                app.composerDraft = text
            } else {
                app.composerDraft += text
            }
            composerFocused = true
        }
    }

    /// Accept images and files dragged onto the composer from Photos, Files, or
    /// other apps. Returns true when at least one provider is consumable.
    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var handled = false
        for provider in providers {
            if provider.canLoadObject(ofClass: UIImage.self) {
                handled = true
                provider.loadObject(ofClass: UIImage.self) { object, _ in
                    guard let image = object as? UIImage else { return }
                    Task { @MainActor in attachImage(image) }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                handled = true
                provider.loadFileRepresentation(forTypeIdentifier: UTType.item.identifier) { url, _ in
                    guard let url, let data = try? Data(contentsOf: url) else { return }
                    let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType
                        ?? "application/octet-stream"
                    let name = url.lastPathComponent
                    Task { @MainActor in attachFileData(data, filename: name, mime: mime) }
                }
            }
        }
        return handled
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

    /// Replace an existing image attachment with its marked-up version, in place.
    private func replaceWithMarkup(_ original: ComposerAttachment, annotated: UIImage) {
        guard let jpeg = annotated.jpegData(compressionQuality: 0.85),
              let index = attachments.firstIndex(where: { $0.id == original.id }) else { return }
        let dataURL = "data:image/jpeg;base64,\(jpeg.base64EncodedString())"
        let base = (original.filename as NSString).deletingPathExtension
        let name = base.hasSuffix("-markup") ? original.filename : "\(base)-markup.jpg"
        attachments[index] = ComposerAttachment(filename: name, mime: "image/jpeg", dataURL: dataURL)
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
    var onMarkup: (() -> Void)?
    let onRemove: () -> Void

    private var thumbnail: UIImage? { attachment.decodedImage }

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
            if let onMarkup, attachment.isImage {
                Button(action: onMarkup) {
                    Image(systemName: "pencil.tip.crop.circle")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.accent)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Mark up \(attachment.filename)")
            }
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.textTertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(attachment.filename)")
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.panel))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 1))
    }
}

extension ComposerAttachment {
    var isImage: Bool { mime.hasPrefix("image/") }

    /// Decode the base64 data URL back into a `UIImage` (image attachments only).
    var decodedImage: UIImage? {
        guard isImage,
              let comma = dataURL.firstIndex(of: ","),
              let data = Data(base64Encoded: String(dataURL[dataURL.index(after: comma)...]))
        else { return nil }
        return UIImage(data: data)
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

/// Inline card for an agent question (single or multi-question, single or multi-select).
private struct QuestionCard: View {
    let question: OCQuestion
    @EnvironmentObject private var store: KorboStore

    @State private var selections: [Set<String>] = []
    @State private var customTexts: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header row
            HStack(spacing: 8) {
                Image(systemName: "questionmark.bubble").foregroundStyle(Theme.accent)
                Text("Question")
                    .font(.system(size: 14, weight: .semibold))
            }

            // Render each question info
            ForEach(Array(question.questions.enumerated()), id: \.offset) { idx, info in
                questionSection(info: info, index: idx)
            }

            // Action buttons
            HStack(spacing: 10) {
                Button {
                    Task { await submitAnswers() }
                } label: {
                    Text("Submit")
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.accent.opacity(0.18)))
                        .foregroundStyle(Theme.accent)
                }
                .buttonStyle(.plain)
                .disabled(!canSubmit)
                .opacity(canSubmit ? 1 : 0.5)

                Button {
                    Task { await store.rejectQuestion(question) }
                } label: {
                    Text("Dismiss")
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.removed.opacity(0.18)))
                        .foregroundStyle(Theme.removed)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.panelRaised))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border, lineWidth: 1))
        .onAppear { initializeState() }
    }

    private func initializeState() {
        if selections.isEmpty {
            selections = Array(repeating: Set<String>(), count: question.questions.count)
        }
        if customTexts.isEmpty {
            customTexts = Array(repeating: "", count: question.questions.count)
        }
    }

    @ViewBuilder
    private func questionSection(info: OCQuestionInfo, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header (uppercase caption)
            if !info.header.isEmpty {
                Text(info.header.uppercased())
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
                    .tracking(0.5)
            }

            // Question text
            Text(info.question)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)

            // Option chips
            FlowLayout(spacing: 8) {
                ForEach(info.options, id: \.label) { option in
                    optionChip(option: option, index: index, isMultiple: info.multiple ?? false)
                }
            }

            // Custom text field if allowed
            if info.custom == true {
                TextField("Other...", text: binding(for: index))
                    .font(.system(size: 13))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Theme.panel))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 1))
            }
        }
    }

    private func optionChip(option: OCQuestionOption, index: Int, isMultiple: Bool) -> some View {
        let isSelected = selections.indices.contains(index) && selections[index].contains(option.label)
        return Button {
            toggleSelection(label: option.label, index: index, isMultiple: isMultiple)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(option.label)
                    .font(.system(size: 12, weight: .medium))
                if !option.description.isEmpty {
                    Text(option.description)
                        .font(.system(size: 10))
                        .foregroundStyle(isSelected ? Theme.accent.opacity(0.8) : Theme.textTertiary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Theme.accent.opacity(0.18) : Theme.panel)
            )
            .foregroundStyle(isSelected ? Theme.accent : Theme.textSecondary)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Theme.accent.opacity(0.4) : Theme.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func toggleSelection(label: String, index: Int, isMultiple: Bool) {
        guard selections.indices.contains(index) else { return }
        if isMultiple {
            if selections[index].contains(label) {
                selections[index].remove(label)
            } else {
                selections[index].insert(label)
            }
        } else {
            // Single select: replace
            selections[index] = [label]
        }
    }

    private func binding(for index: Int) -> Binding<String> {
        Binding(
            get: { customTexts.indices.contains(index) ? customTexts[index] : "" },
            set: { if customTexts.indices.contains(index) { customTexts[index] = $0 } }
        )
    }

    private var canSubmit: Bool {
        guard selections.count == question.questions.count,
              customTexts.count == question.questions.count else { return false }
        for (idx, info) in question.questions.enumerated() {
            let hasSelection = !selections[idx].isEmpty
            let hasCustom = (info.custom == true) && !customTexts[idx].trimmingCharacters(in: .whitespaces).isEmpty
            if !hasSelection && !hasCustom { return false }
        }
        return true
    }

    private func submitAnswers() async {
        var answers: [[String]] = []
        for (idx, info) in question.questions.enumerated() {
            var answerSet = Array(selections[idx])
            if info.custom == true {
                let trimmed = customTexts[idx].trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty { answerSet.append(trimmed) }
            }
            answers.append(answerSet)
        }
        await store.replyQuestion(question, answers: answers)
    }
}

/// Simple flow layout for wrapping chips.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            positions.append(CGPoint(x: currentX, y: currentY))
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
        }

        let totalHeight = currentY + lineHeight
        return (CGSize(width: maxWidth, height: totalHeight), positions)
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
                    .accessibilityLabel("Send message")
                }
            }
            .toolbarBackground(Theme.panelRaised, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .onAppear { isFocused = true }
    }
}
