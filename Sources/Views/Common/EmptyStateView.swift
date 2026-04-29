import SwiftUI

/// Native empty / error state. Wraps `ContentUnavailableView` so every
/// caller gets the standard iOS look (centered SF Symbol, title, body,
/// optional action) with adaptive colors and Dynamic Type for free.
struct EmptyStateView: View {
    let symbol: String
    let title: String
    let message: String?
    var action: (label: String, run: () -> Void)?

    init(
        symbol: String = "tray",
        title: String,
        message: String? = nil,
        action: (label: String, run: () -> Void)? = nil
    ) {
        self.symbol = symbol
        self.title = title
        self.message = message
        self.action = action
    }

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: symbol)
        } description: {
            if let message {
                Text(message)
            }
        } actions: {
            if let action {
                Button(action.label, action: action.run)
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}
