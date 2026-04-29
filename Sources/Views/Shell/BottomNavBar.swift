import SwiftUI

enum Tab: String, CaseIterable, Identifiable {
    case home, explore, map, tribes, chat, profile
    var id: String { rawValue }

    var icon: String {
        switch self {
        case .home: return "house"
        case .explore: return "safari"
        case .map: return "map"
        case .tribes: return "person.3"
        case .chat: return "bubble.left"
        case .profile: return "person.crop.circle"
        }
    }
}

/// Mirrors the rounded-pill bottom bar from tribeapp.wtf:
/// black capsule, white pill highlight on the active tab,
/// floating "+" in the middle that opens the Create sheet.
struct BottomNavBar: View {
    @Binding var selected: Tab
    var onCreateTap: () -> Void

    private let leftTabs: [Tab] = [.home, .explore, .map]
    private let rightTabs: [Tab] = [.tribes, .chat, .profile]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(leftTabs) { tab in
                tabButton(tab)
            }

            Button(action: onCreateTap) {
                Image(systemName: "plus")
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.black)
                    )
                    .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 2)

            ForEach(rightTabs) { tab in
                tabButton(tab)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(Color.black)
                .overlay(
                    RoundedRectangle(cornerRadius: 32, style: .continuous)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
        )
    }

    @ViewBuilder
    private func tabButton(_ tab: Tab) -> some View {
        let isActive = selected == tab
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                selected = tab
            }
        } label: {
            Image(systemName: tab.icon)
                .font(.system(size: 18, weight: isActive ? .bold : .regular))
                .foregroundStyle(isActive ? Color.black : Color.white.opacity(0.6))
                .frame(width: 44, height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(isActive ? Color.white : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.rawValue.capitalized)
    }
}

#Preview {
    @Previewable @State var tab: Tab = .home
    return BottomNavBar(selected: $tab, onCreateTap: {})
        .padding()
        .background(Color.gray.opacity(0.1))
}
