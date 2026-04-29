import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var app: AppState
    @State private var user: User?
    @State private var tweets: [Tweet] = []
    @State private var karma: KarmaSummary?
    @State private var loading = true
    @State private var showingWallet = false
    @State private var showingSettings = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let tid = app.myTID {
                    profileBody(tid: tid)
                } else {
                    EmptyStateView(
                        symbol: "person.crop.circle",
                        title: "No TID set",
                        message: "Open Settings and enter your TID to see your profile, karma, and tweets."
                    )
                    .padding(.top, 60)
                }
            }
        }
        .background(TribeColor.pageBackground)
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

    @ViewBuilder
    private func profileBody(tid: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Card {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 14) {
                        AvatarView(initial: user?.initial ?? String(tid.prefix(1)), size: 60)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(user?.displayName ?? "TID #\(tid)")
                                .font(.title2.weight(.semibold))
                            if let address = user?.custodyAddress {
                                Text(short(address))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                    }

                    HStack(spacing: 22) {
                        Stat(label: "Following", value: "\(user?.followingCount ?? 0)")
                        Stat(label: "Followers", value: "\(user?.followersCount ?? 0)")
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
            }
            .padding(.horizontal, 16)

            HStack {
                Text("Tweets")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Spacer()
            }
            .padding(.horizontal, 22)
            .padding(.top, 6)

            if loading {
                ForEach(0..<2, id: \.self) { _ in
                    Card {
                        VStack(alignment: .leading, spacing: 8) {
                            RoundedRectangle(cornerRadius: 4).fill(TribeColor.chipBackground).frame(maxWidth: .infinity).frame(height: 12)
                            RoundedRectangle(cornerRadius: 4).fill(TribeColor.chipBackground).frame(width: 200, height: 12)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            } else if tweets.isEmpty {
                Text("No tweets yet.")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else {
                VStack(spacing: 12) {
                    ForEach(tweets) { tweet in
                        TweetCardView(tweet: tweet).padding(.horizontal, 16)
                    }
                }
            }
        }
        .padding(.vertical, 8)
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
        self.user = await userTask
        self.tweets = (await tweetsTask) ?? []
        self.karma = (await karmaTask) ?? nil
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
