import SwiftUI

struct AvatarView: View {
    let initial: String
    var size: CGFloat = 40
    var pfpURL: URL? = nil
    /// Stable seed used to pick the gradient hue. Defaults to
    /// `initial` for back-compat, but callers with a TID / username
    /// should pass that so the same user gets the same color even
    /// when their initial collides with somebody else's.
    var seed: String? = nil

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
        .overlay(
            Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.08), radius: 3, x: 0, y: 1)
    }

    private var fallback: some View {
        ZStack {
            TribeColor.avatarGradient(seed: seed ?? initial)
            Text(initial.prefix(1))
                .font(.system(size: size * 0.42, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .shadow(color: Color.black.opacity(0.18), radius: 1, x: 0, y: 1)
        }
    }
}
