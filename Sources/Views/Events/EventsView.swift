import SwiftUI

struct EventsView: View {
    @EnvironmentObject private var app: AppState
    @State private var events: [Event] = []
    @State private var upcomingOnly = true
    @State private var loading = true
    @State private var error: String?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                Picker("", selection: $upcomingOnly) {
                    Text("Upcoming").tag(true)
                    Text("All").tag(false)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .onChange(of: upcomingOnly) { _, _ in load() }

                if loading {
                    ForEach(0..<3, id: \.self) { _ in EventSkeleton() }
                } else if let error {
                    EmptyStateView(symbol: "wifi.exclamationmark", title: "Couldn't load events", body: error, action: ("Retry", load))
                        .padding(.horizontal, 16)
                } else if events.isEmpty {
                    EmptyStateView(symbol: "calendar", title: upcomingOnly ? "No upcoming events" : "No events", body: "Events show meetups and on-chain happenings. Schedule one from tribe-app.")
                        .padding(.horizontal, 16)
                } else {
                    ForEach(events) { ev in
                        EventCard(event: ev).padding(.horizontal, 16)
                    }
                }
            }
            .padding(.top, 6)
        }
        .background(TribeColor.pageBackground)
        .refreshable { await refresh() }
        .task { load() }
    }

    private func load() { Task { await refresh() } }

    @MainActor
    private func refresh() async {
        loading = events.isEmpty
        error = nil
        do { events = try await app.api.fetchEvents(upcomingOnly: upcomingOnly) } catch { self.error = error.localizedDescription }
        loading = false
    }
}

private struct EventCard: View {
    @EnvironmentObject private var app: AppState
    let event: Event

    var body: some View {
        Card(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                if let url = app.api.resolveMediaURL(event.imageUrl) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let img): img.resizable().scaledToFill()
                        default: Color(white: 0.96)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 160)
                    .clipped()
                }
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Pill(text: dateChip, color: TribeColor.accentIndigo)
                        Spacer()
                        Text("\(event.yesCount) going")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(TribeColor.textSecondary)
                    }
                    Text(event.title)
                        .font(.system(size: 17, weight: .bold))
                        .tracking(-0.2)
                    if let loc = event.locationText, !loc.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "mappin.and.ellipse")
                                .font(.system(size: 11))
                            Text(loc).font(.system(size: 12))
                        }
                        .foregroundStyle(TribeColor.textSecondary)
                    }
                    if let d = event.description, !d.isEmpty {
                        Text(d)
                            .font(.system(size: 13))
                            .foregroundStyle(TribeColor.textSecondary)
                            .lineLimit(3)
                    }
                }
                .padding(18)
            }
        }
    }

    private var dateChip: String {
        let f = DateFormatter()
        f.dateFormat = "MMM d · h:mm a"
        return f.string(from: event.startsAt)
    }
}

private struct EventSkeleton: View {
    var body: some View {
        Card(padding: 0) {
            VStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 0).fill(TribeColor.chipBackground).frame(height: 140)
                VStack(alignment: .leading, spacing: 8) {
                    RoundedRectangle(cornerRadius: 4).fill(TribeColor.chipBackground).frame(width: 110, height: 10)
                    RoundedRectangle(cornerRadius: 4).fill(TribeColor.chipBackground).frame(maxWidth: .infinity).frame(height: 16)
                    RoundedRectangle(cornerRadius: 4).fill(TribeColor.chipBackground).frame(width: 200, height: 10)
                }
                .padding(18)
            }
        }
        .padding(.horizontal, 16)
    }
}
