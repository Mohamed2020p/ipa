import SwiftUI

// MARK: - Color Token Bag
struct AppColors {
    let background: Color
    let surface: Color
    let surfaceElevated: Color
    let surfaceCard: Color
    let surfaceGlass: Color
    let accent: Color
    let accentSoft: Color
    let accentGlow: Color
    let secondary: Color
    let textPrimary: Color
    let textSecondary: Color
    let textMuted: Color
    let error: Color
    let live: Color
    let border: Color
    let borderLight: Color
    let scrim: Color
    let scrimLight: Color

    // Gradients
    var heroGradient: LinearGradient {
        LinearGradient(colors: [accentSoft.opacity(0.6), background], startPoint: .top, endPoint: .bottom)
    }
    var cardGradient: LinearGradient {
        LinearGradient(colors: [Color.clear, scrim.opacity(0.95)], startPoint: .top, endPoint: .bottom)
    }
    var glowGradient: RadialGradient {
        RadialGradient(colors: [accentGlow, Color.clear], center: .center, startRadius: 0, endRadius: 200)
    }
}

// MARK: - Theme Enum
enum AppTheme: String, CaseIterable, Identifiable {
    case midnight, aurora, inferno
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .midnight: return "Midnight"
        case .aurora:   return "Aurora"
        case .inferno:  return "Inferno"
        }
    }
    var icon: String {
        switch self {
        case .midnight: return "moon.stars.fill"
        case .aurora:   return "sparkles"
        case .inferno:  return "flame.fill"
        }
    }
    var accentPreview: Color {
        switch self {
        case .midnight: return Color(hex: "00D4FF")
        case .aurora:   return Color(hex: "C060FF")
        case .inferno:  return Color(hex: "FF6B00")
        }
    }

    var colors: AppColors {
        switch self {
        case .midnight:
            return AppColors(
                background:     Color(hex: "000000"),
                surface:        Color(hex: "080808"),
                surfaceElevated:Color(hex: "111111"),
                surfaceCard:    Color(hex: "161616"),
                surfaceGlass:   Color(hex: "1A1A1A").opacity(0.88),
                accent:         Color(hex: "00D4FF"),
                accentSoft:     Color(hex: "00D4FF").opacity(0.13),
                accentGlow:     Color(hex: "00D4FF").opacity(0.42),
                secondary:      Color(hex: "FF6B00"),
                textPrimary:    Color.white,
                textSecondary:  Color(hex: "A8A8A8"),
                textMuted:      Color(hex: "585858"),
                error:          Color(hex: "FF4444"),
                live:           Color(hex: "00E676"),
                border:         Color(hex: "1C1C1C"),
                borderLight:    Color(hex: "2C2C2C"),
                scrim:          Color.black.opacity(0.78),
                scrimLight:     Color.black.opacity(0.38)
            )
        case .aurora:
            return AppColors(
                background:     Color(hex: "06000E"),
                surface:        Color(hex: "0C0018"),
                surfaceElevated:Color(hex: "150024"),
                surfaceCard:    Color(hex: "1C002E"),
                surfaceGlass:   Color(hex: "24003A").opacity(0.88),
                accent:         Color(hex: "BF5FFF"),
                accentSoft:     Color(hex: "BF5FFF").opacity(0.14),
                accentGlow:     Color(hex: "BF5FFF").opacity(0.42),
                secondary:      Color(hex: "00FFB3"),
                textPrimary:    Color.white,
                textSecondary:  Color(hex: "C4A0DC"),
                textMuted:      Color(hex: "72508A"),
                error:          Color(hex: "FF5252"),
                live:           Color(hex: "00FFB3"),
                border:         Color(hex: "220038"),
                borderLight:    Color(hex: "350058"),
                scrim:          Color.black.opacity(0.78),
                scrimLight:     Color.black.opacity(0.38)
            )
        case .inferno:
            return AppColors(
                background:     Color(hex: "0B0400"),
                surface:        Color(hex: "110700"),
                surfaceElevated:Color(hex: "1C0D00"),
                surfaceCard:    Color(hex: "231200"),
                surfaceGlass:   Color(hex: "2E1600").opacity(0.88),
                accent:         Color(hex: "FF6B00"),
                accentSoft:     Color(hex: "FF6B00").opacity(0.14),
                accentGlow:     Color(hex: "FF6B00").opacity(0.42),
                secondary:      Color(hex: "FFD600"),
                textPrimary:    Color.white,
                textSecondary:  Color(hex: "D4A070"),
                textMuted:      Color(hex: "7A4820"),
                error:          Color(hex: "FF3333"),
                live:           Color(hex: "FFD600"),
                border:         Color(hex: "271100"),
                borderLight:    Color(hex: "3C1C00"),
                scrim:          Color.black.opacity(0.78),
                scrimLight:     Color.black.opacity(0.38)
            )
        }
    }
}

// MARK: - ThemeManager
final class ThemeManager: ObservableObject {
    @Published var theme: AppTheme {
        didSet { UserDefaults.standard.set(theme.rawValue, forKey: "sp_theme") }
    }

    /// Short alias: `tm.c.accent`
    var c: AppColors { theme.colors }

    init() {
        let raw = UserDefaults.standard.string(forKey: "sp_theme") ?? AppTheme.midnight.rawValue
        self.theme = AppTheme(rawValue: raw) ?? .midnight
    }
}

// MARK: - Color hex helper
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8)  & 0xFF) / 255
        let b = Double(int         & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
