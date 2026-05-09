import SwiftUI

/// Tribes tab. Six sub-sections (Channels, Map, Polls, Events, Tasks,
/// Crowdfunds) selected via a horizontally-scrollable tab bar with
/// an animated underline indicator. The body is a paged TabView so
/// the user can swipe left / right between sections in addition to
/// tapping a tab. The toolbar "+" adapts to the active section so
/// creating a new poll / event / task / channel / crowdfund stays a
/// one-tap action.
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
            sectionTabBar

            TabView(selection: $section) {
                ChannelsView().id(refreshTick).tag(Section.channels)
                ChannelMapView().id(refreshTick).tag(Section.map)
                PollsView().id(refreshTick).tag(Section.polls)
                EventsView().id(refreshTick).tag(Section.events)
                TasksView().id(refreshTick).tag(Section.tasks)
                CrowdfundsView().id(refreshTick).tag(Section.crowdfunds)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .background(TribeColor.pageBackground)
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

    private var sectionTabBar: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(Section.allCases) { s in
                        sectionTab(s)
                    }
                }
                .padding(.horizontal, 8)
            }
            .background(Color(.systemBackground))
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(TribeColor.cardStroke.opacity(0.4))
                    .frame(height: 0.5)
            }
            .onChange(of: section) { _, new in
                withAnimation(.easeInOut(duration: 0.2)) {
                    proxy.scrollTo(new, anchor: .center)
                }
            }
        }
    }

    private func sectionTab(_ s: Section) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { section = s }
        } label: {
            VStack(spacing: 8) {
                Text(s.label)
                    .font(.subheadline.weight(section == s ? .bold : .medium))
                    .foregroundStyle(section == s ? .primary : .secondary)
                Rectangle()
                    .fill(section == s ? TribeColor.brand : Color.clear)
                    .frame(height: 3)
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .id(s)
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
