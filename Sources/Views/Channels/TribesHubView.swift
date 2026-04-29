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
        case channels, map, polls, events, tasks, crowdfunds
        var id: String { rawValue }
        var label: String {
            switch self {
            case .channels: return "Channels"
            case .map: return "Map"
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
                case .map: ChannelMapView().id(refreshTick)
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
                if section != .map {
                    Button {
                        showingCreate = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("New \(section.label.lowercased())")
                }
            }
        }
        .sheet(isPresented: $showingCreate) {
            createSheet
        }
    }

    @ViewBuilder
    private var createSheet: some View {
        switch section {
        case .channels:
            CreateChannelSheet(onCreated: { _ in refreshTick += 1 })
        case .polls:
            CreatePollSheet(onCreated: { refreshTick += 1 })
        case .events:
            CreateEventSheet(onCreated: { refreshTick += 1 })
        case .tasks:
            CreateTaskSheet(onCreated: { refreshTick += 1 })
        case .crowdfunds:
            CreateCrowdfundSheet(onCreated: { refreshTick += 1 })
        case .map:
            EmptyView()
        }
    }
}

/// Public alias used as the Tribes tab root.
struct TribesView: View {
    var body: some View { TribesHubView() }
}
