import SwiftUI
import MapKit

/// Map of city-anchored content. Pins city channels (kind = 2) and
/// upcoming events that carry lat/lng so the user can wander the
/// network geographically.
///
/// Region defaults to a wide view of whatever pins came back; the user
/// can pinch / drag freely. Tapping a pin opens a card with title +
/// open-channel / open-event hooks.
struct ChannelMapView: View {
    @EnvironmentObject private var app: AppState
    @State private var channels: [Channel] = []
    @State private var events: [Event] = []
    @State private var loading = true
    @State private var error: String?
    @State private var selection: MapPinModel?
    @State private var cameraPosition: MapCameraPosition = .automatic

    private var pins: [MapPinModel] {
        let channelPins: [MapPinModel] = channels.compactMap { ch in
            guard let lat = ch.latitude, let lng = ch.longitude else { return nil }
            return MapPinModel(
                id: "channel:\(ch.id)",
                kind: .channel,
                title: ch.displayName,
                subtitle: ch.description ?? "City channel",
                coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lng),
                channelId: ch.id,
                eventId: nil
            )
        }
        let eventPins: [MapPinModel] = events.compactMap { ev in
            guard let lat = ev.latitude, let lng = ev.longitude else { return nil }
            return MapPinModel(
                id: "event:\(ev.id)",
                kind: .event,
                title: ev.title,
                subtitle: ev.locationText ?? formatStarts(ev.startsAt),
                coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lng),
                channelId: ev.channelId,
                eventId: ev.id
            )
        }
        return channelPins + eventPins
    }

    var body: some View {
        Group {
            if loading && pins.isEmpty {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Loading map…").font(.footnote).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error, pins.isEmpty {
                EmptyStateView(
                    symbol: "wifi.exclamationmark",
                    title: "Couldn't load map",
                    message: error,
                    action: ("Retry", { Task { await refresh() } })
                )
            } else if pins.isEmpty {
                EmptyStateView(
                    symbol: "map",
                    title: "No pinned places yet",
                    message: "Create a city channel or an event with coordinates and it'll show up here."
                )
            } else {
                Map(position: $cameraPosition, selection: Binding(
                    get: { selection?.id },
                    set: { newId in
                        selection = pins.first { $0.id == newId }
                    }
                )) {
                    ForEach(pins) { pin in
                        Marker(pin.title, systemImage: pin.kind.symbol, coordinate: pin.coordinate)
                            .tint(pin.kind.color)
                            .tag(pin.id)
                    }
                }
                .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
                .overlay(alignment: .bottom) {
                    if let selection {
                        PinDetailCard(pin: selection) {
                            self.selection = nil
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 24)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .animation(.easeOut(duration: 0.18), value: selection?.id)
            }
        }
        .task { await refresh() }
        .refreshable { await refresh() }
    }

    @MainActor
    private func refresh() async {
        loading = pins.isEmpty
        defer { loading = false }
        error = nil
        async let chTask = try? app.api.fetchChannels()
        async let evTask = try? app.api.fetchEvents(upcomingOnly: true)
        let chs = await chTask ?? []
        let evs = await evTask ?? []
        self.channels = chs.filter { $0.isCity }
        self.events = evs
        recenter()
    }

    private func recenter() {
        guard !pins.isEmpty else { return }
        let lats = pins.map { $0.coordinate.latitude }
        let lngs = pins.map { $0.coordinate.longitude }
        let center = CLLocationCoordinate2D(
            latitude: (lats.min()! + lats.max()!) / 2,
            longitude: (lngs.min()! + lngs.max()!) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max(0.05, (lats.max()! - lats.min()!) * 1.4),
            longitudeDelta: max(0.05, (lngs.max()! - lngs.min()!) * 1.4)
        )
        cameraPosition = .region(MKCoordinateRegion(center: center, span: span))
    }

    private func formatStarts(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: d)
    }
}

struct MapPinModel: Identifiable, Hashable {
    let id: String
    let kind: Kind
    let title: String
    let subtitle: String
    let coordinate: CLLocationCoordinate2D
    let channelId: String?
    let eventId: String?

    enum Kind: Hashable {
        case channel, event
        var symbol: String {
            switch self {
            case .channel: return "number"
            case .event: return "calendar"
            }
        }
        var color: Color {
            switch self {
            case .channel: return .green
            case .event: return .indigo
            }
        }
        var label: String {
            switch self {
            case .channel: return "City channel"
            case .event: return "Upcoming event"
            }
        }
    }

    static func == (lhs: MapPinModel, rhs: MapPinModel) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

private struct PinDetailCard: View {
    let pin: MapPinModel
    var onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: pin.kind.symbol)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(pin.kind.color)
                Text(pin.kind.label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
            Text(pin.title)
                .font(.headline)
            Text(pin.subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 6)
        )
    }
}
