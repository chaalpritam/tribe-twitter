import SwiftUI

/// Compose sheet for a new crowdfund (CROWDFUND_ADD type 23). Stores
/// `goal_amount` + `currency` (free-form). The actual fund transfers
/// happen via tip-registry / crowdfund-registry; the envelope itself
/// is just an off-chain advertisement.
struct CreateCrowdfundSheet: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    var onCreated: (() -> Void)? = nil

    @State private var title: String = ""
    @State private var description: String = ""
    @State private var goalAmount: String = ""
    @State private var currency: String = "USD"
    @State private var hasDeadline: Bool = false
    @State private var deadline: Date = Date().addingTimeInterval(60 * 60 * 24 * 30)
    @State private var channelId: String = ""
    @State private var imageURL: String = ""
    @State private var publishing = false
    @State private var error: String?

    private var goalDouble: Double? {
        Double(goalAmount.trimmingCharacters(in: .whitespaces))
    }

    private var canPublish: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (goalDouble ?? 0) > 0
            && !publishing
            && app.appKey != nil
            && app.myTID != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Pitch") {
                    TextField("Buy a coffee machine for the hub", text: $title)
                    TextField("Description (optional)", text: $description, axis: .vertical)
                        .lineLimit(3...8)
                }

                Section("Goal") {
                    HStack {
                        TextField("Amount", text: $goalAmount)
                            .keyboardType(.decimalPad)
                        TextField("Currency", text: $currency)
                            .frame(width: 70)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                    }
                }

                Section {
                    Toggle("Has deadline", isOn: $hasDeadline)
                    if hasDeadline {
                        DatePicker("Closes", selection: $deadline, in: Date()...)
                    }
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
                            Text(publishing ? "Publishing…" : "Create crowdfund")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .disabled(!canPublish)
                }
            }
            .navigationTitle("New crowdfund")
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
        guard let key = app.appKey, let tid = app.myTID, let goal = goalDouble else { return }
        publishing = true
        defer { publishing = false }
        let id = Slug.make(title)
        do {
            _ = try await app.api.createCrowdfund(
                crowdfundId: id,
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                description: description.trimmingCharacters(in: .whitespacesAndNewlines),
                goalAmount: goal,
                currency: currency.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(),
                deadline: hasDeadline ? deadline : nil,
                imageURL: imageURL.trimmingCharacters(in: .whitespacesAndNewlines),
                channelId: channelId.trimmingCharacters(in: .whitespacesAndNewlines),
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
