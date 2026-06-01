import Foundation
import ActivityKit

/// Shared Live Activity contract between the Korbo app (which starts/updates/ends
/// the activity via ActivityKit) and the KorboWidgets extension (which renders
/// it on the lock screen, and on the Dynamic Island when running on an iPhone —
/// iPads have no Dynamic Island, so there the activity is lock-screen only).
///
/// `ContentState` is the mutable, frequently-updated slice; the static
/// attributes (`sessionTitle`, `model`, `startedAt`) are fixed for the life of
/// the activity.
struct KorboRunAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        /// Short human-readable status, e.g. "Working…", "Needs permission",
        /// "Has a question", "Finished", "Failed".
        var status: String
        /// Cumulative tokens for the run, when known. `nil` hides the figure.
        var tokens: Int?
        /// Whether the run is still in progress (drives the spinner vs. result UI).
        var isActive: Bool
    }

    /// The session this run belongs to.
    var sessionTitle: String
    /// Model id driving the run (may be empty if unknown).
    var model: String
    /// When the run started — used for the live-updating elapsed timer.
    var startedAt: Date
}
