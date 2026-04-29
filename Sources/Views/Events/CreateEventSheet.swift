import SwiftUI

/// Compose sheet for a new event (EVENT_ADD type 18). starts_at /
/// ends_at are unix seconds; an optional location text + lat/lng make
/// the event findable on the map and from city channels.
struct CreateEventSheet: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    var onCreated: (() -> Void)? = nil

    @State private var title: String = ""
    @State private var description: String = ""
    @State private var startsAt: Date = Date().addingTimeInterval(60 * 60 * 24)
    @State private var hasEndDate: Bool = false
    @State private var endsAt: Date = Date().addingTimeInterval(60 * 60 * 24 + 60 * 60 * 2)
    @State private var locationText: String = ""
    @State private var attachLocation: Bool = false
    @State private var channelId: String = ""
    @State private var imageURL: String = ""
    @State private var publishing = false
    @State private var error: String?
    @StateObject private var location = LocationProvider()

    private var canPublish: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !publishing
            && app.appKey != nil
            && app.myTID != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Title") {
                    TextField("Solana Bangalore meetup", text: $title)
                    TextField("Description (optional)", text: $description, axis: .vertical)
                        .lineLimit(2...6)
                }

                Section("When") {
                    DatePicker("Starts", selection: $startsAt)
                    Toggle("Has end time", isOn: $hasEndDate)
                    if hasEndDate {
                        DatePicker("Ends", selection: $endsAt, in: startsAt...)
                    }
                }

                Section {
                    TextField("Location (optional)", text: $locationText)
                    Toggle("Attach my coordinates", isOn: $attachLocation)
                        .onChange(of: attachLocation) { _, on in
                            if on { location.request() }
                        }
                    if attachLocation {
                        if let coord = location.coordinate {
                            LabeledContent("Lat", value: String(format: "%.5f", coord.latitude)).font(.footnote)
                            LabeledContent("Lng", value: String(format: "%.5f", coord.longitude)).font(.footnote)
                        } else if let err = location.error {
                            Text(err).font(.footnote).foregroundStyle(.red)
                        } else {
                            HStack {
                                ProgressView()
                                Text("Resolving GPS…").font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Where")
                } footer: {
                    Text("Coordinates surface on the Map tab and let nearby city channels pick the event up.")
                }

                Section {
                    TextField("Channel id (optional)", text: $channelId)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Image URL (optional)", text: $imageURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Optional")
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
                            Text(publishing ? "Publishing…" : "Create event")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .disabled(!canPublish)
                }
            }
            .navigationTitle("New event")
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
        let id = Slug.make(title)
        let lat = attachLocation ? location.coordinate?.latitude : nil
        let lng = attachLocation ? location.coordinate?.longitude : nil
        do {
            _ = try await app.api.createEvent(
                eventId: id,
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                description: description.trimmingCharacters(in: .whitespacesAndNewlines),
                startsAt: startsAt,
                endsAt: hasEndDate ? endsAt : nil,
                locationText: locationText.trimmingCharacters(in: .whitespacesAndNewlines),
                latitude: lat,
                longitude: lng,
                channelId: channelId.trimmingCharacters(in: .whitespacesAndNewlines),
                imageURL: imageURL.trimmingCharacters(in: .whitespacesAndNewlines),
                as: key,
                tid: tid
            )
            onCreated?()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
