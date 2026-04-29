import SwiftUI

/// Tribes tab. Six sub-sections (Channels, Map, Polls, Events, Tasks,
/// Crowdfunds) selected via a segmented Picker. The toolbar carries a
/// "+" button whose sheet adapts to the active section so creating a
/// new poll / event / task / channel / crowdfund only takes one tap.
struct TribesHubView: View {
    @State private var section: Section = .channels
    @State private var showingCreate = false
    @State private var refreshTick = 0

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
                case .channels: ChannelsView().id(refreshTick)
                case .polls: PollsView().id(refreshTick)
                case .events: EventsView().id(refreshTick)
                case .tasks: TasksView().id(refreshTick)
                case .crowdfunds: CrowdfundsView().id(refreshTick)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(TribeColor.pageBackground)
        .navigationTitle("Tribes")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingCreate = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("New \(section.label.lowercased())")
            }
        }
        .sheet(isPresented: $showingCreate) {
            createSheet
        }
    }

    @ViewBuilder
    private var createSheet: some View {
        let bumpRefresh = { refreshTick += 1 }
        switch section {
        case .channels:
            CreateChannelSheet(onCreated: { _ in bumpRefresh() })
        case .polls:
            CreatePollSheet(onCreated: bumpRefresh)
        case .events:
            CreateEventSheet(onCreated: bumpRefresh)
        case .tasks:
            CreateTaskSheet(onCreated: bumpRefresh)
        case .crowdfunds:
            CreateCrowdfundSheet(onCreated: bumpRefresh)
        }
    }
}

/// Public alias used as the Tribes tab root.
struct TribesView: View {
    var body: some View { TribesHubView() }
}
