import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var app: AppState
    @State private var user: User?
    @State private var tweets: [Tweet] = []
    @State private var karma: KarmaSummary?
    @State private var erProfile: ERProfile?
    @State private var loading = true
    @State private var showingWallet = false
    @State private var showingSettings = false

    var body: some View {
        Group {
            if let tid = app.myTID {
                List {
                    Section {
                        identityCard(tid: tid)
                            .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }

                    if loading && tweets.isEmpty {
                        Section("Tweets") {
                            ForEach(0..<2, id: \.self) { _ in
                                TweetSkeletonRow()
                            }
                        }
                    } else if tweets.isEmpty {
                        Section("Tweets") {
                            Text("No tweets yet.")
                                .font(.subheadline)
                                .foregroundStyle(.tertiary)
                        }
                    } else {
                        Section("Tweets") {
                            ForEach(tweets) { tweet in
                                TweetCardView(tweet: tweet)
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            } else {
                EmptyStateView(
                    symbol: "person.crop.circle",
                    title: "No TID set",
                    message: "Open Settings and enter your TID to see your profile, karma, and tweets."
                )
            }
        }
        .navigationTitle("Profile")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingWallet = true
                } label: {
                    Image(systemName: "wallet.pass")
                }
                .accessibilityLabel("Wallet")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Settings")
            }
        }
        .refreshable { await refresh() }
        .task { load() }
        .sheet(isPresented: $showingWallet) {
            NavigationStack {
                WalletView()
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { showingWallet = false }
                        }
                    }
            }
            .environmentObject(app)
        }
        .sheet(isPresented: $showingSettings) {
            NavigationStack {
                SettingsView()
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { showingSettings = false }
                        }
                    }
            }
            .environmentObject(app)
        }
    }

    private func identityCard(tid: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                AvatarView(initial: user?.initial ?? String(tid.prefix(1)), size: 64)
                VStack(alignment: .leading, spacing: 2) {
                    Text(user?.displayName ?? "TID #\(tid)")
                        .font(.title2.weight(.semibold))
                    if let address = user?.custodyAddress {
                        Text(short(address))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("TID #\(tid)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }

            HStack(spacing: 22) {
                Stat(label: "Following", value: "\(erProfile?.followingCount ?? user?.followingCount ?? 0)")
                Stat(label: "Followers", value: "\(erProfile?.followersCount ?? user?.followersCount ?? 0)")
                if let k = karma {
                    Stat(label: "Karma · L\(k.level)", value: "\(k.total)")
                }
            }

            if let bio = user?.profile?.bio, !bio.isEmpty {
                Text(bio)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private func short(_ s: String) -> String {
        guard s.count > 10 else { return s }
        return "\(s.prefix(5))…\(s.suffix(5))"
    }

    private func load() {
        Task { await refresh() }
    }

    @MainActor
    private func refresh() async {
        guard let tid = app.myTID else { loading = false; return }
        loading = true
        async let userTask = try? app.api.fetchUser(tid)
        async let tweetsTask = try? app.api.fetchTweets(tid: tid)
        async let karmaTask = try? app.api.fetchKarma(tid)
        async let erTask = try? app.er.profile(tid)
        self.user = await userTask
        self.tweets = (await tweetsTask) ?? []
        self.karma = (await karmaTask) ?? nil
        self.erProfile = (await erTask) ?? nil
        loading = false
    }
}

private struct Stat: View {
    let label: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.title3.weight(.semibold))
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }
}

private struct TweetSkeletonRow: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            RoundedRectangle(cornerRadius: 4).fill(Color(.tertiarySystemFill)).frame(maxWidth: .infinity).frame(height: 12)
            RoundedRectangle(cornerRadius: 4).fill(Color(.tertiarySystemFill)).frame(width: 200, height: 12)
        }
        .padding(.vertical, 4)
        .redacted(reason: .placeholder)
    }
}
