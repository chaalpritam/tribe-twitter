import SwiftUI

struct EmptyStateView: View {
    let symbol: String
    let title: String
    let body: String?
    var action: (label: String, run: () -> Void)?

    init(
        symbol: String = "tray",
        title: String,
        body: String? = nil,
        action: (label: String, run: () -> Void)? = nil
    ) {
        self.symbol = symbol
        self.title = title
        self.body = body
        self.action = action
    }

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(TribeColor.chipBackground)
                    .frame(width: 64, height: 64)
                Image(systemName: symbol)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(TribeColor.textSecondary)
            }
            Text(title)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(TribeColor.textPrimary)
            if let body {
                Text(body)
                    .font(.system(size: 13))
                    .foregroundStyle(TribeColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            if let action {
                Button(action.label, action: action.run)
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.top, 4)
            }
        }
        .padding(.vertical, 32)
        .frame(maxWidth: .infinity)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(TribeColor.primary)
                    .opacity(configuration.isPressed ? 0.85 : 1)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}
