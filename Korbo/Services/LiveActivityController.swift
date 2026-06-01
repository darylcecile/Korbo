import Foundation
import ActivityKit

/// Drives the Korbo run Live Activity from the app side: starts one when a run
/// begins, updates its status/token count as the run progresses, and ends it
/// when the run finishes or fails.
///
/// Only a single activity is tracked at a time (the most recent run). If Live
/// Activities are disabled by the user or unavailable on the device, every call
/// is a safe no-op.
@MainActor
final class LiveActivityController {
    static let shared = LiveActivityController()
    private init() {}

    private var activity: Activity<KorboRunAttributes>?

    /// How long an activity may sit without an update before the system renders
    /// it as stale. Guards against a "Working…" card getting stuck on the lock
    /// screen if the app is suspended before it can process the run's `idle`
    /// event (iOS has no server push to wake us).
    private let staleAfter: TimeInterval = 5 * 60

    private var enabled: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    /// End every existing Korbo activity. Called on launch to clear orphans left
    /// behind by a previous app run that was suspended mid-run.
    func endStaleOnLaunch() {
        Task {
            for act in Activity<KorboRunAttributes>.activities {
                await act.end(nil, dismissalPolicy: .immediate)
            }
            activity = nil
        }
    }

    /// Begin a Live Activity for a freshly-started run. Ends any stale one first.
    func start(sessionTitle: String, model: String) {
        guard enabled else { return }
        // Replace any leftover activity from a previous run.
        if activity != nil { end(status: "Finished") }

        let attributes = KorboRunAttributes(
            sessionTitle: sessionTitle,
            model: model,
            startedAt: Date())
        let initial = KorboRunAttributes.ContentState(status: "Working…", tokens: nil, isActive: true)
        do {
            activity = try Activity.request(
                attributes: attributes,
                content: .init(state: initial, staleDate: Date().addingTimeInterval(staleAfter)))
        } catch {
            activity = nil
        }
    }

    /// Update the running activity's status and/or token count. Passing `nil`
    /// for `tokens` leaves the previously-shown figure untouched.
    func update(status: String, tokens: Int?, isActive: Bool) {
        guard let activity else { return }
        let previous = activity.content.state
        let next = KorboRunAttributes.ContentState(
            status: status,
            tokens: tokens ?? previous.tokens,
            isActive: isActive)
        Task { await activity.update(.init(state: next, staleDate: Date().addingTimeInterval(staleAfter))) }
    }

    /// End the activity with a terminal status, dismissing it shortly after.
    func end(status: String) {
        guard let activity else { return }
        let final = KorboRunAttributes.ContentState(
            status: status,
            tokens: activity.content.state.tokens,
            isActive: false)
        let ending = activity
        self.activity = nil
        Task {
            await ending.end(.init(state: final, staleDate: nil), dismissalPolicy: .default)
        }
    }
}
