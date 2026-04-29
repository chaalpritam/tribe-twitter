import SwiftUI

struct EventsView: View {
    @EnvironmentObject private var app: AppState
    @State private var events: [Event] = []
    @State private var upcomingOnly = true
    @State private var loading = true
    @State private var error: String?

    var body: some View {
        VStack(spacing: 0) {
            Picker("Time", selection: $upcomingOnly) {
                Text("Upcoming").tag(true)
                Text("All").tag(false)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .onChange(of: upcomingOnly) { _, _ in load() }

            Group {
                if loading && events.isEmpty {
                    List {
                        ForEach(0..<3, id: \.self) { _ in EventSkeleton() }
                    }
                    .listStyle(.insetGrouped)
                } else if let error, events.isEmpty {
                    EmptyStateView(
                        symbol: "wifi.exclamationmark",
                        title: "Couldn't load events",
                        message: error,
                        action: ("Retry", load)
                    )
                } else if events.isEmpty {
                    EmptyStateView(
                        symbol: "calendar",
                        title: upcomingOnly ? "No upcoming events" : "No events",
                        message: "Events show meetups and on-chain happenings. Schedule one from tribe-app."
                    )
                } else {
                    List(events) { event in
                        EventRow(event: event)
                            .listRowInsets(EdgeInsets())
                    }
                    .listStyle(.insetGrouped)
                }
            }
        }
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

private struct EventRow: View {
    @EnvironmentObject private var app: AppState
    let event: Event

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let url = app.api.resolveMediaURL(event.imageUrl) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img): img.resizable().scaledToFill()
                    default: Color(.tertiarySystemFill)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 160)
                .clipped()
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Pill(text: dateChip, color: .indigo)
                    Spacer()
                    Text("\(event.yesCount) going")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Text(event.title)
                    .font(.headline)
                if let loc = event.locationText, !loc.isEmpty {
                    Label(loc, systemImage: "mappin.and.ellipse")
                        .labelStyle(.titleAndIcon)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if let d = event.description, !d.isEmpty {
                    Text(d)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            }
            .padding(16)
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
        VStack(spacing: 0) {
            Rectangle().fill(Color(.tertiarySystemFill)).frame(height: 140)
            VStack(alignment: .leading, spacing: 8) {
                RoundedRectangle(cornerRadius: 4).fill(Color(.tertiarySystemFill)).frame(width: 110, height: 10)
                RoundedRectangle(cornerRadius: 4).fill(Color(.tertiarySystemFill)).frame(maxWidth: .infinity).frame(height: 16)
                RoundedRectangle(cornerRadius: 4).fill(Color(.tertiarySystemFill)).frame(width: 200, height: 10)
            }
            .padding(16)
        }
        .redacted(reason: .placeholder)
    }
}
