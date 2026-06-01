import SwiftUI

/// Central design tokens for Korbo. Mirrors the dark, low-chroma aesthetic of
/// the openchamber opencode client so panels feel cohesive.
/// Dynamic tokens (accent, bg, panel, panelRaised, border) read from AppearanceStore.
enum Theme {
    // Dynamic tokens — read from AppearanceStore.shared
    static var accent: Color { AppearanceStore.shared.accentColor }
    static var bg: Color { AppearanceStore.shared.bg }
    static var panel: Color { AppearanceStore.shared.panel }
    static var panelRaised: Color { AppearanceStore.shared.panelRaised }
    static var border: Color { AppearanceStore.shared.border }

    // Static tokens — unchanged
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
