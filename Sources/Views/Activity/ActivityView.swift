import SwiftUI

/// Mirrors tribe-app's /activity page. Shows every signed envelope
/// the user has produced (tweets, reactions, bookmarks, DMs, tips)
/// plus every ER follow / unfollow op, with filter chips for
/// on-chain vs off-chain and Solana explorer links for any row that
/// settled with a tx signature.
struct ActivityView: View {
    @EnvironmentObject private var app: AppState
    @State private var rows: [ActivityRow] = []
    @State private var filter: Filter = .all
    @State private var loading = true
    @State private var error: String?

    enum Filter: String, CaseIterable, Identifiable {
        case all, onchain, offchain
        var id: String { rawValue }
        var label: String {
            switch self {
            case .all: return "All"
            case .onchain: return "Onchain"
            case .offchain: return "Signed offchain"
            }
        }
    }

    private var filtered: [ActivityRow] {
        switch filter {
        case .all: return rows
        case .onchain: return rows.filter { $0.type.isOnChain }
        case .offchain: return rows.filter { !$0.type.isOnChain }
        }
    }

    private var onChainCount: Int {
        rows.filter { $0.type.isOnChain }.count
    }

    var body: some View {
        Group {
            if app.myTID == nil {
                EmptyStateView(
                    symbol: "person.crop.circle.badge.exclamationmark",
                    title: "Sign in required",
                    message: "Set your TID in Settings to see your account's activity log."
                )
            } else if loading && rows.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error {
                EmptyStateView(
                    symbol: "wifi.exclamationmark",
                    title: "Couldn't load activity",
                    message: error,
                    action: ("Retry", load)
                )
            } else {
                List {
                    Section {
                        Picker("Filter", selection: $filter) {
                            ForEach(Filter.allCases) { f in
                                Text(f.label).tag(f)
                            }
                        }
                        .pickerStyle(.segmented)

                        Text("\(onChainCount) onchain · \(rows.count) total")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)

                    if filtered.isEmpty {
                        Section {
                            Text(emptyMessage)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 24)
                        }
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    } else {
                        ForEach(filtered) { row in
                            ActivityRowView(row: row)
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .background(TribeColor.pageBackground)
        .navigationTitle("Activity")
        .refreshable { await refresh() }
        .task { load() }
    }

    private var emptyMessage: String {
        switch filter {
        case .onchain:
            return "No onchain activity yet — follow someone or send a tip to start your onchain history."
        case .offchain:
            return "No signed envelopes yet — post a tweet, like something, or send a DM."
        case .all:
            return "No activity yet."
        }
    }

    private func load() {
        Task { await refresh() }
    }

    @MainActor
    private func refresh() async {
        guard let tid = app.myTID else { loading = false; return }
        loading = rows.isEmpty
        error = nil
        do {
            rows = try await app.api.fetchActivity(tid)
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }
}

private struct ActivityRowView: View {
    let row: ActivityRow

    private var explorerURL: URL? {
        guard let sig = row.txSignature else { return nil }
        // Devnet matches MessageSigner.network = 2 (DEVNET) — the
        // hub's tip-registry / tid-registry both deploy to devnet
        // for this build. Mainnet deploys would need this rebuilt.
        return URL(string: "https://explorer.solana.com/tx/\(sig)?cluster=devnet")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(row.type.isOnChain ? "ONCHAIN" : "SIGNED")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule().fill(row.type.isOnChain
                                       ? Color(red: 0.16, green: 0.65, blue: 0.42)
                                       : Color(.darkGray))
                    )
                Text(row.type.verb)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(RelativeTime.short(row.timestamp))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            if row.peerTid != nil || (row.preview?.isEmpty == false) {
                HStack(spacing: 6) {
                    if let peer = row.peerTid {
                        NavigationLink {
                            ProfileView(tid: peer)
                        } label: {
                            Text("TID #\(peer)")
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(.primary)
                        }
                        .buttonStyle(.plain)
                    }
                    if row.peerTid != nil, row.preview?.isEmpty == false {
                        Text("·").foregroundStyle(.tertiary)
                    }
                    if let preview = row.preview, !preview.isEmpty {
                        Text(preview)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }

            if let url = explorerURL {
                Link(destination: url) {
                    Label("Solana tx", systemImage: "arrow.up.right.square")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color(red: 0.16, green: 0.55, blue: 0.36))
                }
            }
        }
        .padding(.vertical, 6)
    }
}
