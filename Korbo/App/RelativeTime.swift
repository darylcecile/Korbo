import Foundation

enum RelativeTime {
    private static let formatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    /// Short relative string like "1h", "3m", "just now".
    static func short(_ date: Date?) -> String {
        guard let date else { return "" }
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "now" }
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
