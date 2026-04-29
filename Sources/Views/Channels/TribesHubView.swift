import SwiftUI

/// Tribes tab from the bottom nav. Five sub-tabs: Channels, Polls,
/// Events, Tasks, Crowdfunds — each backed by the corresponding read
/// endpoint. Mirrors how tribeapp.wtf surfaces these as the
/// "community" content types.
struct TribesHubView: View {
    @State private var section: Section = .channels

    enum Section: String, CaseIterable {
        case channels, polls, events, tasks, crowdfunds
        var label: String {
            switch self {
            case .channels: return "Channels"
            case .polls: return "Polls"
            case .events: return "Events"
            case .tasks: return "Tasks"
            case .crowdfunds: return "Crowdfunds"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            PageHeader("Tribes", subtitle: "Community channels and activity")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Section.allCases, id: \.self) { s in
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) { section = s }
                        } label: {
                            Text(s.label)
                                .font(.system(size: 13, weight: .bold))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule().fill(section == s ? TribeColor.primary : TribeColor.chipBackground)
                                )
                                .foregroundStyle(section == s ? Color.white : TribeColor.textSecondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }

            Divider().padding(.top, 8).opacity(0.6)

            Group {
                switch section {
                case .channels: ChannelsView()
                case .polls: PollsView()
                case .events: EventsView()
                case .tasks: TasksView()
                case .crowdfunds: CrowdfundsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(TribeColor.pageBackground)
    }
}

/// Replaces the Tribes placeholder with the real hub view.
struct TribesView: View {
    var body: some View { TribesHubView() }
}
