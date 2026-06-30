import SwiftUI
import TribeCore

/// Karma breakdown sheet pushed from the profile stats row. Renders
/// the existing KarmaSummary payload (already fetched by ProfileView)
/// as a level header plus per-source contributions, with each source
/// showing its raw count and weighted score.
struct KarmaSheet: View {
    let karma: KarmaSummary

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                levelHero
                breakdownCard
                weightsCard
                Text("Karma is recomputed from your on-chain activity. Tweets, reactions received, followers, tips received, and tasks completed each contribute weighted points toward your level.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 16)
            }
            .padding(.top, 12)
        }
        .background(TribeColor.pageBackground)
        .navigationTitle("Karma")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var levelHero: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(TribeColor.accentAmber.opacity(0.15))
                    .frame(width: 96, height: 96)
                Text("L\(karma.level)")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(TribeColor.accentAmber)
                    .monospacedDigit()
            }
            Text("\(karma.total)")
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .monospacedDigit()
            Text("Total karma")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(TribeColor.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(TribeColor.cardStroke.opacity(0.4), lineWidth: 0.5)
        )
        .padding(.horizontal, 16)
    }

    private var breakdownCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("Breakdown")
            breakdownRow(
                icon: "text.bubble.fill",
                tint: TribeColor.brand,
                label: "Tweets",
                count: karma.breakdown.tweets,
                weight: karma.weights.tweet
            )
            divider
            breakdownRow(
                icon: "heart.fill",
                tint: TribeColor.accentRose,
                label: "Reactions received",
                count: karma.breakdown.reactionsReceived,
                weight: karma.weights.reactionReceived
            )
            divider
            breakdownRow(
                icon: "person.2.fill",
                tint: TribeColor.accentTeal,
                label: "Followers",
                count: karma.breakdown.followers,
                weight: karma.weights.follower
            )
            divider
            breakdownRow(
                icon: "dollarsign.circle.fill",
                tint: TribeColor.accentAmber,
                label: "Tips received",
                count: karma.breakdown.tipsReceived,
                weight: karma.weights.tipReceived
            )
            divider
            breakdownRow(
                icon: "checkmark.seal.fill",
                tint: TribeColor.accentEmerald,
                label: "Tasks completed",
                count: karma.breakdown.tasksCompleted,
                weight: karma.weights.taskCompleted
            )
        }
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(TribeColor.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(TribeColor.cardStroke.opacity(0.4), lineWidth: 0.5)
        )
        .padding(.horizontal, 16)
    }

    private var weightsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Weights per action")
            VStack(spacing: 6) {
                weightLine(label: "Tweet", weight: karma.weights.tweet)
                weightLine(label: "Reaction received", weight: karma.weights.reactionReceived)
                weightLine(label: "Follower", weight: karma.weights.follower)
                weightLine(label: "Tip received", weight: karma.weights.tipReceived)
                weightLine(label: "Task completed", weight: karma.weights.taskCompleted)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
        }
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(TribeColor.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(TribeColor.cardStroke.opacity(0.4), lineWidth: 0.5)
        )
        .padding(.horizontal, 16)
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 8)
    }

    private func breakdownRow(
        icon: String,
        tint: Color,
        label: String,
        count: Int,
        weight: Int
    ) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(tint.opacity(0.15))
                Image(systemName: icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tint)
            }
            .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.subheadline.weight(.medium))
                Text("\(count) × \(weight) pts")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Spacer()

            Text("\(count * weight)")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.primary)
                .monospacedDigit()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func weightLine(label: String, weight: Int) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.primary)
            Spacer()
            Text("\(weight) pts")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(TribeColor.cardStroke.opacity(0.3))
            .frame(height: 0.5)
            .padding(.leading, 58)
    }
}
