import SwiftUI

/// Semantic color aliases mapped onto the system palette so the UI
/// adapts to light/dark mode and Dynamic Type colors automatically.
/// Keeping the indirection lets a brand pass change one file.
enum TribeColor {
    static let primary = Color.accentColor
    static let surface = Color(.secondarySystemGroupedBackground)
    static let pageBackground = Color(.systemGroupedBackground)
    static let cardStroke = Color(.separator)
    static let chipBackground = Color(.tertiarySystemFill)
    static let textPrimary = Color(.label)
    static let textSecondary = Color(.secondaryLabel)
    static let textTertiary = Color(.tertiaryLabel)

    static let accentIndigo = Color.indigo
    static let accentAmber = Color.orange
    static let accentEmerald = Color.green
    static let accentRose = Color.pink
}

enum TribeMetrics {
    static let cardCornerRadius: CGFloat = 16
    static let cardPadding: CGFloat = 16
    static let bottomNavReservedHeight: CGFloat = 0
}
