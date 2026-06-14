import Foundation

/// Handoff (Continuity) support: lets a user pick up the session they're viewing
/// on one device and continue it on another signed into the same iCloud account.
///
/// We advertise an `NSUserActivity` describing the currently-selected session
/// (server identity + session id) and, on the receiving device, restore it by
/// selecting the matching server, connecting, and opening the session.
///
/// The activity type must also be listed under `NSUserActivityTypes` in the
/// app's Info.plist for the system to route incoming activities to us.
enum Handoff {
    /// Reverse-DNS activity type, matched in Info.plist `NSUserActivityTypes`.
    static let sessionActivityType = "app.korbo.ios.session"

    enum Key {
        static let sessionID = "sessionID"
        static let sessionTitle = "sessionTitle"
        static let serverID = "serverID"
        static let serverURL = "serverURL"
    }
}
