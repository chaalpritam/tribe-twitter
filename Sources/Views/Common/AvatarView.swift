import SwiftUI

struct AvatarView: View {
    let initial: String
    var size: CGFloat = 40
    var pfpURL: URL? = nil

    var body: some View {
        ZStack {
            if let url = pfpURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().scaledToFill()
                    default:
                        fallback
                    }
                }
            } else {
                fallback
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(TribeColor.cardStroke, lineWidth: 0.5))
    }

    private var fallback: some View {
        ZStack {
            Circle().fill(TribeColor.chipBackground)
            Text(initial.prefix(1))
                .font(.system(size: size * 0.42, weight: .semibold, design: .rounded))
                .foregroundStyle(TribeColor.textPrimary)
        }
    }
}
