import Foundation

/// Routes App Intent actions into the main SwiftUI view tree. Because
/// `AppIntent.perform()` runs outside the view hierarchy, intents enqueue
/// actions here; `KorboApp` observes `pending` and executes them with access
/// to `KorboStore`.
@MainActor
final class IntentRouter: ObservableObject {
    static let shared = IntentRouter()

    enum PendingIntent: Equatable {
        case newSession
        case sendPrompt(String)
    }

    @Published var pending: PendingIntent?

    private init() {}

    func enqueue(_ intent: PendingIntent) {
        pending = intent
    }
}
