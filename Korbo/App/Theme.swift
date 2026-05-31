import SwiftUI

/// Central design tokens for Korbo. Mirrors the dark, low-chroma aesthetic of
/// the openchamber opencode client so panels feel cohesive.
enum Theme {
    static let accent = Color(hex: 0xE8783C)        // warm amber (active session / send)
    static let bg = Color(hex: 0x0E0E10)            // app background
    static let panel = Color(hex: 0x141417)         // panel background
    static let panelRaised = Color(hex: 0x1B1B1F)   // cards / composer
    static let border = Color(hex: 0x2A2A30)
    static let textPrimary = Color(hex: 0xEDEDEF)
    static let textSecondary = Color(hex: 0x9A9AA2)
    static let textTertiary = Color(hex: 0x6A6A72)
    static let added = Color(hex: 0x4CAF7D)
    static let removed = Color(hex: 0xD15B5B)
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}
