import SwiftUI

struct CrowdfundsView: View {
    @EnvironmentObject private var app: AppState
    @State private var campaigns: [Crowdfund] = []
    @State private var loading = true
    @State private var error: String?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if loading {
                    ForEach(0..<3, id: \.self) { _ in CrowdfundSkeleton() }
                } else if let error {
                    EmptyStateView(symbol: "wifi.exclamationmark", title: "Couldn't load crowdfunds", message: error, action: ("Retry", load))
                        .padding(.horizontal, 16)
                } else if campaigns.isEmpty {
                    EmptyStateView(symbol: "circle.hexagongrid", title: "No crowdfunds yet", message: "Community-funded campaigns. Start one from tribe-app.")
                        .padding(.horizontal, 16)
                } else {
                    ForEach(campaigns) { cf in CrowdfundCard(crowdfund: cf).padding(.horizontal, 16) }
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
        loading = campaigns.isEmpty
        error = nil
        do { campaigns = try await app.api.fetchCrowdfunds() } catch { self.error = error.localizedDescription }
        loading = false
    }
}

private struct CrowdfundCard: View {
    @EnvironmentObject private var app: AppState
    let crowdfund: Crowdfund

    var body: some View {
        Card(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                if let url = app.api.resolveMediaURL(crowdfund.imageUrl) {
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
                VStack(alignment: .leading, spacing: 10) {
                    Pill(text: "Crowdfund", color: TribeColor.accentEmerald)
                    Text(crowdfund.title)
                        .font(.system(size: 17, weight: .bold))
                    if let d = crowdfund.description, !d.isEmpty {
                        Text(d)
                            .font(.system(size: 13))
                            .foregroundStyle(TribeColor.textSecondary)
                            .lineLimit(2)
                    }
                    ProgressBar(progress: crowdfund.progress)
                    HStack {
                        Text("\(formatted(crowdfund.raisedAmount)) / \(formatted(crowdfund.goalAmount)) \(crowdfund.currency)")
                            .font(.system(size: 12, weight: .semibold))
                        Spacer()
                        Text("by TID #\(crowdfund.creatorTid)")
                            .font(.system(size: 11))
                            .foregroundStyle(TribeColor.textTertiary)
                    }
                }
                .padding(18)
            }
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

private struct ProgressBar: View {
    let progress: Double
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(TribeColor.chipBackground)
                Capsule().fill(TribeColor.primary).frame(width: geo.size.width * progress)
            }
        }
        .frame(height: 6)
    }
}

private struct CrowdfundSkeleton: View {
    var body: some View {
        Card(padding: 0) {
            VStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 0).fill(TribeColor.chipBackground).frame(height: 140)
                VStack(alignment: .leading, spacing: 8) {
                    RoundedRectangle(cornerRadius: 4).fill(TribeColor.chipBackground).frame(width: 90, height: 10)
                    RoundedRectangle(cornerRadius: 4).fill(TribeColor.chipBackground).frame(maxWidth: .infinity).frame(height: 16)
                    RoundedRectangle(cornerRadius: 4).fill(TribeColor.chipBackground).frame(maxWidth: .infinity).frame(height: 6)
                }
                .padding(18)
            }
        }
        .padding(.horizontal, 16)
    }
}
