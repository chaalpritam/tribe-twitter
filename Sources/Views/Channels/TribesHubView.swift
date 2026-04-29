import SwiftUI

/// Tribes tab. Five sub-sections (Channels, Polls, Events, Tasks,
/// Crowdfunds) selected via a segmented Picker in the toolbar so the
/// section switch reads as a system control.
struct TribesHubView: View {
    @State private var section: Section = .channels

    enum Section: String, CaseIterable, Identifiable {
        case channels, polls, events, tasks, crowdfunds
        var id: String { rawValue }
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
            Picker("Section", selection: $section) {
                ForEach(Section.allCases) { s in
                    Text(s.label).tag(s)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            Divider()

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
        .navigationTitle("Tribes")
    }
}

/// Public alias used as the Tribes tab root.
struct TribesView: View {
    var body: some View { TribesHubView() }
}
