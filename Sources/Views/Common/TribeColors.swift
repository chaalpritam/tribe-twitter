import SwiftUI

/// Mirrors the tribeapp.wtf palette: black primary, white surfaces,
/// neutral grays, plus three muted semantic accents. Centralized so a
/// theme tweak doesn't have to touch every view.
enum TribeColor {
    static let primary = Color.black
    static let surface = Color.white
    static let pageBackground = Color(white: 0.98)
    static let cardStroke = Color(white: 0.94)
    static let chipBackground = Color(white: 0.96)
    static let textPrimary = Color.black
    static let textSecondary = Color(white: 0.45)
    static let textTertiary = Color(white: 0.6)

    static let accentIndigo = Color(red: 0.39, green: 0.40, blue: 0.95)
    static let accentAmber = Color(red: 0.96, green: 0.62, blue: 0.05)
    static let accentEmerald = Color(red: 0.06, green: 0.59, blue: 0.45)
    static let accentRose = Color(red: 0.86, green: 0.18, blue: 0.30)
}

/// Shared layout constants — keeps the rounded-card style consistent
/// across feed cards, sheets, and standalone screens.
enum TribeMetrics {
    static let cardCornerRadius: CGFloat = 28
    static let cardPadding: CGFloat = 18
    static let bottomNavReservedHeight: CGFloat = 110
}
