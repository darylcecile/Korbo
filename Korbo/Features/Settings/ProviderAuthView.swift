import SwiftUI

/// Drives a provider OAuth / device flow end-to-end:
/// 1. collect any pre-flight prompts (e.g. Copilot's "GitHub deployment type"),
/// 2. `POST …/oauth/authorize` to get a `url` + `instructions` (device code),
/// 3. for `auto` flows poll `…/oauth/callback` until it succeeds; for `code`
///    flows let the user paste a code back.
///
/// Built against the live opencode shapes (`ProviderAuthMethod` /
/// `ProviderAuthAuthorization`) — verified against `GET /provider/auth` and
/// `POST /provider/github-copilot/oauth/authorize` on server v1.14.46.
struct ProviderOAuthSheet: View {
    let providerID: String
    let providerName: String
    let methodIndex: Int
    let method: ProviderAuthMethod

    @EnvironmentObject private var store: KorboStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    private enum Phase: Equatable {
        case prompts          // collecting pre-flight inputs
        case authorizing      // POST /authorize in flight
        case waitingAuto      // device flow: polling callback
        case waitingCode      // browser flow: awaiting a pasted code
        case success
        case failed(String)
    }

    @State private var phase: Phase = .prompts
    @State private var answers: [String: String] = [:]
    @State private var authorization: ProviderAuthAuthorization?
    @State private var pastedCode: String = ""
    @State private var pollTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .prompts:     promptsView
                case .authorizing: progressView("Starting sign-in…")
                case .waitingAuto: waitingAutoView
                case .waitingCode: waitingCodeView
                case .success:     resultView(success: true, message: "\(providerName) is connected.")
                case .failed(let m): resultView(success: false, message: m)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle(method.label)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { pollTask?.cancel(); dismiss() }
                }
            }
        }
        .onAppear(perform: seedDefaults)
        .onDisappear { pollTask?.cancel() }
    }

    // MARK: Prompts

    /// Prompts whose `when` condition is satisfied by the current answers.
    private var visiblePrompts: [AuthPrompt] {
        (method.prompts ?? []).filter { $0.when?.isSatisfied(by: answers) ?? true }
    }

    @ViewBuilder
    private var promptsView: some View {
        VStack(alignment: .leading, spacing: 18) {
            if visiblePrompts.isEmpty {
                Text("You'll be sent to the provider to authorize Korbo.")
                    .foregroundStyle(Theme.textSecondary)
            }
            ForEach(visiblePrompts) { prompt in
                VStack(alignment: .leading, spacing: 6) {
                    Text(prompt.message ?? prompt.key)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                    if prompt.isSelect {
                        Picker(prompt.message ?? prompt.key,
                               selection: bindingFor(prompt.key)) {
                            ForEach(prompt.options ?? []) { opt in
                                Text(opt.hint.map { "\(opt.label) — \($0)" } ?? opt.label)
                                    .tag(opt.value)
                            }
                        }
                        .pickerStyle(.segmented)
                    } else {
                        TextField(prompt.placeholder ?? "", text: bindingFor(prompt.key))
                            .textFieldStyle(.roundedBorder)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }
                }
            }
            Spacer(minLength: 0)
            Button {
                Task { await authorize() }
            } label: {
                Text("Continue").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .disabled(!promptsSatisfied)
        }
    }

    private var promptsSatisfied: Bool {
        visiblePrompts.allSatisfy { p in
            guard !p.isSelect else { return (answers[p.key] ?? "").isEmpty == false }
            // free-text prompts that are shown are treated as required
            return (answers[p.key] ?? "").trimmingCharacters(in: .whitespaces).isEmpty == false
        }
    }

    // MARK: Waiting (device / auto)

    @ViewBuilder
    private var waitingAutoView: some View {
        VStack(alignment: .leading, spacing: 16) {
            instructionBlock
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Waiting for you to authorize…")
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: Waiting (paste code)

    @ViewBuilder
    private var waitingCodeView: some View {
        VStack(alignment: .leading, spacing: 16) {
            instructionBlock
            TextField("Paste the code from the browser", text: $pastedCode)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            Button {
                Task { await submitCode() }
            } label: {
                Text("Submit code").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .disabled(pastedCode.trimmingCharacters(in: .whitespaces).isEmpty)
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var instructionBlock: some View {
        if let auth = authorization {
            VStack(alignment: .leading, spacing: 12) {
                Text(auth.instructions)
                    .font(.callout)
                    .foregroundStyle(Theme.textPrimary)
                    .textSelection(.enabled)
                Button {
                    if let url = URL(string: auth.url) { openURL(url) }
                } label: {
                    Label(auth.url, systemImage: "safari")
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .tint(Theme.accent)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.panel, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: Result / progress

    private func progressView(_ label: String) -> some View {
        VStack(spacing: 12) {
            ProgressView()
            Text(label).foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func resultView(success: Bool, message: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: success ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 44))
                .foregroundStyle(success ? Theme.added : Theme.removed)
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.textPrimary)
            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Logic

    private func seedDefaults() {
        for prompt in method.prompts ?? [] where prompt.isSelect {
            if answers[prompt.key] == nil, let first = prompt.options?.first {
                answers[prompt.key] = first.value
            }
        }
    }

    private func bindingFor(_ key: String) -> Binding<String> {
        Binding(get: { answers[key] ?? "" }, set: { answers[key] = $0 })
    }

    private func authorize() async {
        phase = .authorizing
        // Only forward inputs for prompts that are actually visible/applicable.
        var inputs: [String: String] = [:]
        for prompt in visiblePrompts {
            if let v = answers[prompt.key], !v.isEmpty { inputs[prompt.key] = v }
        }
        guard let auth = await store.startProviderOAuth(providerID, method: methodIndex, inputs: inputs) else {
            phase = .failed(store.lastError ?? "Could not start sign-in.")
            return
        }
        authorization = auth
        if let url = URL(string: auth.url) { openURL(url) }
        if auth.isAuto {
            phase = .waitingAuto
            startPolling()
        } else {
            phase = .waitingCode
        }
    }

    /// Device flow: poll the callback until it reports success (or the user closes).
    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task {
            // ~3 minutes of polling at 3s intervals.
            for _ in 0..<60 {
                if Task.isCancelled { return }
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                if Task.isCancelled { return }
                let ok = await store.completeProviderOAuth(providerID, method: methodIndex, code: nil)
                if ok { phase = .success; return }
            }
            if !Task.isCancelled {
                phase = .failed("Timed out waiting for authorization. Please try again.")
            }
        }
    }

    private func submitCode() async {
        let code = pastedCode.trimmingCharacters(in: .whitespaces)
        phase = .authorizing
        let ok = await store.completeProviderOAuth(providerID, method: methodIndex, code: code)
        phase = ok ? .success : .failed(store.lastError ?? "That code didn't work. Please try again.")
    }
}
