import SwiftUI
import Foundation

// MARK: - Stride Colour Palette

extension Color {
    enum stride {
        // Primary lavender family
        static let lavender       = Color(hex: "#DAC3E8")
        static let lavenderDeep   = Color(hex: "#B89FCC")
        static let lavenderLight  = Color(hex: "#EDE0F5")
        static let lavenderGlow   = Color(hex: "#F3ECFA")

        // Workout type accents
        static let violet         = Color(hex: "#9B59B6")
        static let mint           = Color(hex: "#6FCF97")
        static let sage           = Color(hex: "#C8D5B9")
        static let warmOrange     = Color(hex: "#F2994A") // kept for legacy; prefer .sage
        static let coral          = Color(hex: "#EB5757")
        static let sky            = Color(hex: "#56CCF2")

        // Dark mode background
        static let darkBase       = Color(hex: "#1E1A2E")
        static let darkDeep       = Color(hex: "#0F0F1A")
    }
}

extension Color {
    /// Initialise from a hex string like "#DAC3E8" or "DAC3E8"
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: .alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&int)
        let r, g, b, a: UInt64
        switch cleaned.count {
        case 6:
            (r, g, b, a) = ((int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF, 255)
        case 8:
            (r, g, b, a) = ((int >> 24) & 0xFF, (int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default:
            (r, g, b, a) = (0, 0, 0, 255)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Workout Type Colours

extension WorkoutType {
    var accentColor: Color {
        switch self {
        case .easyRun:      return Color.stride.mint
        case .longRun:      return Color.stride.violet
        case .tempoRun:     return Color.stride.sage
        case .intervalRun:  return Color.stride.coral
        case .recoveryRun:  return Color(hex: "#27AE60")
        case .strengthDay:  return Color.stride.sky
        case .restDay:      return Color(.systemGray3)
        }
    }

    var accentFill: Color { accentColor.opacity(0.15) }
}

// MARK: - Background Gradients

extension LinearGradient {
    /// Main app background — soft lavender to white
    static var strideBackground: LinearGradient {
        LinearGradient(
            colors: [Color.stride.lavenderLight, Color.white],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// Dark mode background
    static var strideDarkBackground: LinearGradient {
        LinearGradient(
            colors: [Color.stride.darkBase, Color.stride.darkDeep],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// Glass card overlay gradient
    static var glassOverlay: LinearGradient {
        LinearGradient(
            colors: [Color.white.opacity(0.6), Color.stride.lavenderGlow.opacity(0.4)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - Typography

extension Font {
    enum stride {
        static let displayLarge  = Font.largeTitle.bold()
        static let displayMedium = Font.title.bold()
        static let headingMedium = Font.title2.weight(.semibold)
        static let headingSmall  = Font.title3.weight(.semibold)
        static let bodyLarge     = Font.body
        static let bodyMedium    = Font.subheadline
        static let caption       = Font.caption
        static let label         = Font.caption2.weight(.semibold)
    }
}

// MARK: - Spacing

extension CGFloat {
    static let strideXS: CGFloat  = 4
    static let strideSM: CGFloat  = 8
    static let strideMD: CGFloat  = 16
    static let strideLG: CGFloat  = 24
    static let strideXL: CGFloat  = 32
    static let strideXXL: CGFloat = 48
}

// MARK: - Corner Radii

extension CGFloat {
    static let strideRadiusSM: CGFloat   = 8
    static let strideRadiusMD: CGFloat   = 14
    static let strideRadiusLG: CGFloat   = 20
    static let strideRadiusHero: CGFloat = 24
}
