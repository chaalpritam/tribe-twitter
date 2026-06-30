import SwiftUI
import TribeCore
import CoreLocation

/// Compose sheet for a new channel. Mirrors what tribe-twitter-app's New
/// Channel form does: pick INTEREST or CITY, fill name / description,
/// and (for CITY) attach the device's current coordinates so the
/// channel surfaces on the city map.
struct CreateChannelSheet: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    var onCreated: ((String) -> Void)? = nil

    @State private var kind: ChannelKindKind = .interest
    @State private var name: String = ""
    @State private var description: String = ""
    @State private var attachLocation: Bool = false
    @State private var publishing = false
    @State private var error: String?
    @StateObject private var location = LocationProvider()

    enum ChannelKindKind: Int, CaseIterable, Identifiable {
        case interest = 3
        case city = 2
        var id: Int { rawValue }
        var label: String { self == .interest ? "Interest" : "City" }
    }

    private var canPublish: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !publishing
            && app.appKey != nil
            && app.myTID != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Type", selection: $kind) {
                        ForEach(ChannelKindKind.allCases) { k in
                            Text(k.label).tag(k)
                        }
                    }
                    .pickerStyle(.segmented)
                } footer: {
                    Text(kind == .city
                         ? "City channels are anchored to a location and surface on the Map. Optional but recommended: attach this device's coordinates."
                         : "Interest channels group tweets by topic — anyone can join.")
                }

                Section("Name") {
                    TextField("crypto-policy", text: $name)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Short description (optional)", text: $description, axis: .vertical)
                        .lineLimit(2...4)
                }

                if kind == .city {
                    Section {
                        Toggle("Attach my current location", isOn: $attachLocation)
                            .onChange(of: attachLocation) { _, on in
                                if on { location.request() }
                            }
                        if let coord = location.coordinate, attachLocation {
                            LabeledContent("Latitude", value: String(format: "%.5f", coord.latitude))
                                .font(.footnote)
                            LabeledContent("Longitude", value: String(format: "%.5f", coord.longitude))
                                .font(.footnote)
                        } else if attachLocation {
                            HStack {
                                ProgressView()
                                Text("Resolving GPS…")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } footer: {
                        if let err = location.error {
                            Text(err).foregroundStyle(.red).font(.footnote)
                        }
                    }
                }

                if let error {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red).font(.footnote)
                    }
                }

                Section {
                    Button {
                        Task { await publish() }
                    } label: {
                        HStack {
                            if publishing { ProgressView() }
                            Text(publishing ? "Publishing…" : "Create channel")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .disabled(!canPublish)
                }
            }
            .navigationTitle("New channel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    @MainActor
    private func publish() async {
        guard let key = app.appKey, let tid = app.myTID else { return }
        publishing = true
        defer { publishing = false }
        let id = Slug.make(name)
        let lat = (kind == .city && attachLocation) ? location.coordinate?.latitude : nil
        let lng = (kind == .city && attachLocation) ? location.coordinate?.longitude : nil
        do {
            _ = try await app.api.createChannel(
                channelId: id,
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                description: description.trimmingCharacters(in: .whitespacesAndNewlines),
                kind: kind.rawValue,
                latitude: lat,
                longitude: lng,
                as: key,
                tid: tid
            )
            onCreated?(id)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

@MainActor
final class LocationProvider: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var coordinate: CLLocationCoordinate2D?
    @Published var error: String?
    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func request() {
        let status = manager.authorizationStatus
        switch status {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            manager.requestLocation()
        case .denied, .restricted:
            error = "Location access is denied. Enable it in Settings → Privacy → Location."
        @unknown default:
            error = "Location service unavailable."
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        if status == .authorizedAlways || status == .authorizedWhenInUse {
            manager.requestLocation()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let coord = locations.last?.coordinate else { return }
        Task { @MainActor in
            self.coordinate = coord
            self.error = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError err: Error) {
        Task { @MainActor in
            self.error = err.localizedDescription
        }
    }
}
