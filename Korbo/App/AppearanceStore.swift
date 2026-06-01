import SwiftUI

/// Persisted appearance settings. Singleton accessed via `AppearanceStore.shared`.
/// Theme.swift reads from this store so all `Theme.accent`, `Theme.bg`, etc.
/// remain valid call-sites while becoming reactive.
final class AppearanceStore: ObservableObject {
    static let shared = AppearanceStore()

    // MARK: - Setting Enums

    enum Accent: String, CaseIterable, Identifiable {
        case amber, blue, green, purple, pink, graphite

        var id: String { rawValue }

        var color: Color {
            switch self {
            case .amber:    return Color(hex: 0xE8783C)
            case .blue:     return Color(hex: 0x4F8DF5)
            case .green:    return Color(hex: 0x4CAF7D)
            case .purple:   return Color(hex: 0xB07CD8)
            case .pink:     return Color(hex: 0xE0719E)
            case .graphite: return Color(hex: 0x8A8A92)
            }
        }

        var label: String { rawValue.capitalized }
    }

    enum ThemeVariant: String, CaseIterable, Identifiable {
        case dark, midnight

        var id: String { rawValue }
        var label: String { rawValue.capitalized }

        var bg: Color {
            switch self {
            case .dark:     return Color(hex: 0x0E0E10)
            case .midnight: return Color(hex: 0x000000)
            }
        }

        var panel: Color {
            switch self {
            case .dark:     return Color(hex: 0x141417)
            case .midnight: return Color(hex: 0x0B0B0D)
            }
        }

        var panelRaised: Color {
            switch self {
            case .dark:     return Color(hex: 0x1B1B1F)
            case .midnight: return Color(hex: 0x141417)
            }
        }

        var border: Color {
            switch self {
            case .dark:     return Color(hex: 0x2A2A30)
            case .midnight: return Color(hex: 0x242428)
            }
        }
    }

    enum TextSize: String, CaseIterable, Identifiable {
        case small, standard, large, xlarge

        var id: String { rawValue }

        var label: String {
            switch self {
            case .small:    return "Small"
            case .standard: return "Standard"
            case .large:    return "Large"
            case .xlarge:   return "X-Large"
            }
        }

        var dynamicTypeSize: DynamicTypeSize {
            switch self {
            case .small:    return .small
            case .standard: return .large
            case .large:    return .xLarge
            case .xlarge:   return .xxLarge
            }
        }
    }

    enum Density: String, CaseIterable, Identifiable {
        case comfortable, compact

        var id: String { rawValue }
        var label: String { rawValue.capitalized }
    }

    // MARK: - UserDefaults Keys

    private enum Keys {
        static let accent   = "korbo.appearance.accent"
        static let theme    = "korbo.appearance.theme"
        static let textSize = "korbo.appearance.textSize"
        static let density  = "korbo.appearance.density"
    }

    // MARK: - Published Settings

    @Published var accent: Accent {
        didSet { UserDefaults.standard.set(accent.rawValue, forKey: Keys.accent) }
    }

    @Published var theme: ThemeVariant {
        didSet { UserDefaults.standard.set(theme.rawValue, forKey: Keys.theme) }
    }

    @Published var textSize: TextSize {
        didSet { UserDefaults.standard.set(textSize.rawValue, forKey: Keys.textSize) }
    }

    @Published var density: Density {
        didSet { UserDefaults.standard.set(density.rawValue, forKey: Keys.density) }
    }

    // MARK: - Computed Convenience

    var accentColor: Color { accent.color }
    var bg: Color { theme.bg }
    var panel: Color { theme.panel }
    var panelRaised: Color { theme.panelRaised }
    var border: Color { theme.border }

    /// Combines text size preference with density. Compact nudges down one step.
    var effectiveDynamicTypeSize: DynamicTypeSize {
        let base = textSize.dynamicTypeSize
        guard density == .compact else { return base }
        // Nudge down one step for compact density
        switch base {
        case .xxLarge:          return .xLarge
        case .xLarge:           return .large
        case .large:            return .medium
        case .medium:           return .small
        case .small:            return .xSmall
        default:                return base
        }
    }

    // MARK: - Init (load from UserDefaults)

    private init() {
        let defaults = UserDefaults.standard

        if let raw = defaults.string(forKey: Keys.accent),
           let value = Accent(rawValue: raw) {
            self.accent = value
        } else {
            self.accent = .amber
        }

        if let raw = defaults.string(forKey: Keys.theme),
           let value = ThemeVariant(rawValue: raw) {
            self.theme = value
        } else {
            self.theme = .dark
        }

        if let raw = defaults.string(forKey: Keys.textSize),
           let value = TextSize(rawValue: raw) {
            self.textSize = value
        } else {
            self.textSize = .standard
        }

        if let raw = defaults.string(forKey: Keys.density),
           let value = Density(rawValue: raw) {
            self.density = value
        } else {
            self.density = .comfortable
        }
    }
}
