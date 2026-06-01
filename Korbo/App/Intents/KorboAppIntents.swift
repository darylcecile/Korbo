import AppIntents

// MARK: - New Session Intent

struct NewSessionIntent: AppIntent {
    static var title: LocalizedStringResource = "New Korbo Session"
    static var description = IntentDescription("Creates a new chat session in Korbo.")
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        IntentRouter.shared.enqueue(.newSession)
        return .result()
    }
}

// MARK: - Send Prompt Intent

struct SendPromptIntent: AppIntent {
    static var title: LocalizedStringResource = "Send Korbo Prompt"
    static var description = IntentDescription("Sends a prompt to Korbo and opens the app.")
    static var openAppWhenRun = true

    @Parameter(title: "Prompt", description: "The text to send to Korbo")
    var prompt: String

    static var parameterSummary: some ParameterSummary {
        Summary("Send \(\.$prompt) to Korbo")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        IntentRouter.shared.enqueue(.sendPrompt(prompt))
        return .result()
    }
}

// MARK: - App Shortcuts Provider

struct KorboShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: NewSessionIntent(),
            phrases: [
                "New session in \(.applicationName)",
                "Start a new \(.applicationName) session",
                "Create session in \(.applicationName)"
            ],
            shortTitle: "New Session",
            systemImageName: "plus.bubble"
        )
        AppShortcut(
            intent: SendPromptIntent(),
            phrases: [
                "Send a prompt to \(.applicationName)",
                "Ask \(.applicationName)",
                "Message \(.applicationName)"
            ],
            shortTitle: "Send Prompt",
            systemImageName: "text.bubble"
        )
    }
}
