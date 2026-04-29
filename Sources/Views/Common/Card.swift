import SwiftUI

/// White rounded card matching the tribeapp.wtf 32px radius look.
struct Card<Content: View>: View {
    var padding: CGFloat = TribeMetrics.cardPadding
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: TribeMetrics.cardCornerRadius, style: .continuous)
                    .fill(TribeColor.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: TribeMetrics.cardCornerRadius, style: .continuous)
                    .stroke(TribeColor.cardStroke, lineWidth: 1)
            )
    }
}
