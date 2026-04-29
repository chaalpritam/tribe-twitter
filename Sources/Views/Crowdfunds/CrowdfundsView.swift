import SwiftUI

struct CrowdfundsView: View {
    @EnvironmentObject private var app: AppState
    @State private var campaigns: [Crowdfund] = []
    @State private var loading = true
    @State private var error: String?

    var body: some View {
        Group {
            if loading && campaigns.isEmpty {
                List {
                    ForEach(0..<3, id: \.self) { _ in CrowdfundSkeleton() }
                }
                .listStyle(.insetGrouped)
            } else if let error, campaigns.isEmpty {
                EmptyStateView(
                    symbol: "wifi.exclamationmark",
                    title: "Couldn't load crowdfunds",
                    message: error,
                    action: ("Retry", load)
                )
            } else if campaigns.isEmpty {
                EmptyStateView(
                    symbol: "circle.hexagongrid",
                    title: "No crowdfunds yet",
                    message: "Community-funded campaigns. Start one from tribe-app."
                )
            } else {
                List(campaigns) { cf in
                    CrowdfundRow(crowdfund: cf)
                        .listRowInsets(EdgeInsets())
                }
                .listStyle(.insetGrouped)
            }
        }
        .refreshable { await refresh() }
        .task { load() }
    }

    private func load() { Task { await refresh() } }

    @MainActor
    private func refresh() async {
        loading = campaigns.isEmpty
        error = nil
        do { campaigns = try await app.api.fetchCrowdfunds() } catch { self.error = error.localizedDescription }
        loading = false
    }
}

private struct CrowdfundRow: View {
    @EnvironmentObject private var app: AppState
    let crowdfund: Crowdfund

    @State private var presentingPledge = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let url = app.api.resolveMediaURL(crowdfund.imageUrl) {
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
            VStack(alignment: .leading, spacing: 10) {
                Pill(text: "Crowdfund", color: .green)
                Text(crowdfund.title)
                    .font(.headline)
                if let d = crowdfund.description, !d.isEmpty {
                    Text(d)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                ProgressView(value: crowdfund.progress)
                HStack {
                    Text("\(formatted(crowdfund.raisedAmount)) / \(formatted(crowdfund.goalAmount)) \(crowdfund.currency)")
                        .font(.footnote.weight(.semibold))
                    Spacer()
                    Text("by TID #\(crowdfund.creatorTid)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Button {
                    presentingPledge = true
                } label: {
                    Text("Pledge").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .disabled(app.appKey == nil)
            }
            .padding(16)
        }
        .sheet(isPresented: $presentingPledge) {
            PledgeSheet(crowdfund: crowdfund)
                .environmentObject(app)
        }
    }

    private func formatted(_ d: Decimal) -> String {
        let n = NSDecimalNumber(decimal: d).doubleValue
        let f = NumberFormatter()
        f.maximumFractionDigits = 2
        f.numberStyle = .decimal
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }
}

private struct PledgeSheet: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    let crowdfund: Crowdfund

    @State private var amount: String = ""
    @State private var working = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(crowdfund.title)
                        .font(.headline)
                    Text("Goal: \(crowdfund.goalAmount) \(crowdfund.currency)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: { Text("Crowdfund") }

                Section {
                    TextField("0.00", text: $amount)
                        .keyboardType(.decimalPad)
                } header: {
                    Text("Pledge amount (\(crowdfund.currency))")
                } footer: {
                    Text("This is an off-chain pledge envelope. Settling pledges on-chain through the crowdfund Solana program is a separate flow that needs Solana mobile / WalletConnect.")
                }

                if let error {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                }

                Section {
                    Button {
                        Task { await pledge() }
                    } label: {
                        HStack {
                            if working { ProgressView() }
                            Text(working ? "Submitting…" : "Pledge")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .disabled(working || amountDecimal == nil)
                }
            }
            .navigationTitle("Pledge")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var amountDecimal: Decimal? {
        let trimmed = amount.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let d = Decimal(string: trimmed), d > 0 else { return nil }
        return d
    }

    private func pledge() async {
        guard let key = app.appKey, let tid = app.myTID, let value = amountDecimal else { return }
        working = true
        defer { working = false }
        do {
            _ = try await app.api.pledgeCrowdfund(
                crowdfundId: crowdfund.id,
                amount: value,
                currency: crowdfund.currency,
                as: key,
                tid: tid
            )
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private struct CrowdfundSkeleton: View {
    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Color(.tertiarySystemFill)).frame(height: 140)
            VStack(alignment: .leading, spacing: 8) {
                RoundedRectangle(cornerRadius: 4).fill(Color(.tertiarySystemFill)).frame(width: 90, height: 10)
                RoundedRectangle(cornerRadius: 4).fill(Color(.tertiarySystemFill)).frame(maxWidth: .infinity).frame(height: 16)
                RoundedRectangle(cornerRadius: 4).fill(Color(.tertiarySystemFill)).frame(maxWidth: .infinity).frame(height: 6)
            }
            .padding(16)
        }
        .redacted(reason: .placeholder)
    }
}
