import SwiftUI

/// Explore is the discovery hub. Surfaces a slice of every kind of
/// thing the protocol carries — people, polls, events, tasks,
/// crowdfunds — with a "See all" link on each section that pushes
/// the dedicated list view from the Tribes tab. Search lives in the
/// toolbar.
struct ExploreView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var userAvatars: UserAvatarCache

    @State private var users: [User] = []
    @State private var polls: [Poll] = []
    @State private var events: [Event] = []
    @State private var tasks: [TaskItem] = []
    @State private var crowdfunds: [Crowdfund] = []
    @State private var loading = true
    @State private var error: String?
    /// User pushed via row tap; drives navigationDestination so the
    /// row tap reaches the profile without the disclosure chevron a
    /// NavigationLink-as-row would draw.
    @State private var selectedTID: String?

    var body: some View {
        Group {
            if loading && everythingEmpty {
                loadingState
            } else if let error, everythingEmpty {
                EmptyStateView(
                    symbol: "wifi.exclamationmark",
                    title: "Couldn't load Explore",
                    message: error,
                    action: ("Retry", load)
                )
            } else if everythingEmpty {
                EmptyStateView(
                    symbol: "sparkles",
                    title: "Nothing to explore yet",
                    message: "As people register identities, post polls, host events, and start crowdfunds, they'll show up here."
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 24, pinnedViews: []) {
                        if !users.isEmpty {
                            peopleSection
                        }
                        if !polls.isEmpty {
                            pollsSection
                        }
                        if !events.isEmpty {
                            eventsSection
                        }
                        if !tasks.isEmpty {
                            tasksSection
                        }
                        if !crowdfunds.isEmpty {
                            crowdfundsSection
                        }
                    }
                    .padding(.vertical, 12)
                }
                .scrollIndicators(.hidden)
            }
        }
        .navigationTitle("Explore")
        .navigationDestination(item: $selectedTID) { tid in
            ProfileView(tid: tid)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    SearchView()
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .accessibilityLabel("Search")
            }
        }
        .refreshable { await refresh() }
        .task { load() }
    }

    private var everythingEmpty: Bool {
        users.isEmpty && polls.isEmpty && events.isEmpty
            && tasks.isEmpty && crowdfunds.isEmpty
    }

    // MARK: - Loading state

    private var loadingState: some View {
        ScrollView {
            LazyVStack(spacing: 24) {
                sectionPlaceholder(title: "People to follow")
                sectionPlaceholder(title: "Live polls")
                sectionPlaceholder(title: "Upcoming events")
            }
            .padding(.vertical, 12)
        }
    }

    private func sectionPlaceholder(title: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title3.weight(.bold))
                .padding(.horizontal, 16)
            VStack(spacing: 8) {
                ForEach(0..<2, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(.tertiarySystemFill))
                        .frame(height: 84)
                        .padding(.horizontal, 16)
                }
            }
        }
        .redacted(reason: .placeholder)
    }

    // MARK: - People section

    private var peopleSection: some View {
        SectionContainer(
            title: "People to follow",
            symbol: "person.2.fill",
            tint: TribeColor.brand,
            destination: AnyView(PeopleListDestination(users: users))
        ) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(users.prefix(8)) { user in
                        Button {
                            selectedTID = user.tid
                        } label: {
                            PersonCardView(user: user)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    // MARK: - Polls section

    private var pollsSection: some View {
        SectionContainer(
            title: "Live polls",
            symbol: "chart.bar.fill",
            tint: TribeColor.accentIndigo,
            destination: AnyView(PollsView())
        ) {
            VStack(spacing: 8) {
                ForEach(polls.prefix(3)) { poll in
                    PollCardView(poll: poll)
                        .padding(.horizontal, 16)
                }
            }
        }
    }

    // MARK: - Events section

    private var eventsSection: some View {
        SectionContainer(
            title: "Upcoming events",
            symbol: "calendar",
            tint: TribeColor.accentEmerald,
            destination: AnyView(EventsView())
        ) {
            VStack(spacing: 8) {
                ForEach(events.prefix(3)) { event in
                    EventCardView(event: event)
                        .padding(.horizontal, 16)
                }
            }
        }
    }

    // MARK: - Tasks section

    private var tasksSection: some View {
        SectionContainer(
            title: "Open tasks",
            symbol: "wrench.and.screwdriver.fill",
            tint: TribeColor.accentTeal,
            destination: AnyView(TasksView())
        ) {
            VStack(spacing: 8) {
                ForEach(tasks.prefix(3)) { task in
                    TaskCardView(task: task)
                        .padding(.horizontal, 16)
                }
            }
        }
    }

    // MARK: - Crowdfunds section

    private var crowdfundsSection: some View {
        SectionContainer(
            title: "Active crowdfunds",
            symbol: "circle.hexagongrid.fill",
            tint: TribeColor.accentAmber,
            destination: AnyView(CrowdfundsView())
        ) {
            VStack(spacing: 8) {
                ForEach(crowdfunds.prefix(3)) { cf in
                    CrowdfundCardView(crowdfund: cf)
                        .padding(.horizontal, 16)
                }
            }
        }
    }

    // MARK: - Data loading

    private func load() {
        Task { await refresh() }
    }

    @MainActor
    private func refresh() async {
        loading = everythingEmpty
        error = nil
        async let usersTask = (try? await app.api.fetchUsers(limit: 12)) ?? []
        async let pollsTask = (try? await app.api.fetchPolls()) ?? []
        async let eventsTask = (try? await app.api.fetchEvents(upcomingOnly: true)) ?? []
        async let tasksTask = (try? await app.api.fetchTasks()) ?? []
        async let crowdfundsTask = (try? await app.api.fetchCrowdfunds()) ?? []
        let (u, p, e, t, c) = await (usersTask, pollsTask, eventsTask, tasksTask, crowdfundsTask)
        users = u
        polls = p
        events = e
        tasks = t
        crowdfunds = c
        // Seed avatar cache with whatever pfp the list endpoint did
        // happen to return.
        for user in u {
            if let raw = user.profile?.pfpUrl,
               let url = app.api.resolveMediaURL(raw) {
                userAvatars.record(tid: user.tid, pfpUrl: url)
            }
        }
        loading = false
    }
}

// MARK: - Section chrome

private struct SectionContainer<Content: View>: View {
    let title: String
    let symbol: String
    let tint: Color
    let destination: AnyView
    let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(tint.opacity(0.15))
                    Image(systemName: symbol)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(tint)
                }
                .frame(width: 26, height: 26)

                Text(title)
                    .font(.title3.weight(.bold))

                Spacer()

                NavigationLink {
                    destination
                } label: {
                    HStack(spacing: 2) {
                        Text("See all")
                            .font(.subheadline.weight(.medium))
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(TribeColor.brand)
                }
            }
            .padding(.horizontal, 16)

            content()
        }
    }
}

// MARK: - Cards

private struct PersonCardView: View {
    let user: User

    private var handle: String {
        if let u = user.username { return "@\(u).tribe" }
        return "@tid\(user.tid)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            UserAvatar(
                tid: user.tid,
                initial: user.initial,
                size: 56,
                seed: user.username ?? user.tid
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(user.displayName)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(handle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if let bio = user.profile?.bio, !bio.isEmpty {
                Text(bio)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 4)

            Text("\(user.followersCount) followers")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.tertiary)
                .monospacedDigit()
        }
        .padding(14)
        .frame(width: 200, height: 196, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(TribeColor.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(TribeColor.cardStroke.opacity(0.4), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
    }
}

private struct PollCardView: View {
    let poll: Poll

    private var deadlineLabel: String? {
        guard let expires = poll.expiresAt else { return nil }
        if expires < Date() { return "Closed" }
        return "Closes \(RelativeTime.short(expires))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(poll.question)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                metaChip(
                    "\(poll.options.count) options",
                    symbol: "list.bullet",
                    tint: TribeColor.accentIndigo
                )
                if let n = poll.totalVotes, n > 0 {
                    metaChip("\(n) votes", symbol: "person.2.fill", tint: TribeColor.accentTeal)
                }
                if let label = deadlineLabel {
                    metaChip(label, symbol: "clock", tint: .secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tribeCard(cornerRadius: 16, padding: 14)
    }
}

private struct EventCardView: View {
    let event: Event

    private var dateLabel: String {
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d · h:mm a"
        return f.string(from: event.startsAt)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(event.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Text(dateLabel)
                .font(.caption.weight(.medium))
                .foregroundStyle(TribeColor.accentEmerald)

            HStack(spacing: 10) {
                if let loc = event.locationText, !loc.isEmpty {
                    metaChip(loc, symbol: "mappin.and.ellipse", tint: TribeColor.accentTeal)
                }
                if event.yesCount > 0 {
                    metaChip("\(event.yesCount) going", symbol: "checkmark.circle.fill", tint: TribeColor.accentEmerald)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tribeCard(cornerRadius: 16, padding: 14)
    }
}

private struct TaskCardView: View {
    let task: TaskItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(task.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            if let description = task.description, !description.isEmpty {
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                metaChip(
                    task.status.capitalized,
                    symbol: "circle.fill",
                    tint: statusTint
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tribeCard(cornerRadius: 16, padding: 14)
    }

    private var statusTint: Color {
        switch task.status.lowercased() {
        case "open": return TribeColor.accentEmerald
        case "claimed", "in_progress": return TribeColor.accentAmber
        case "complete", "completed": return TribeColor.accentTeal
        default: return .secondary
        }
    }
}

private struct CrowdfundCardView: View {
    let crowdfund: Crowdfund

    private var raisedText: String {
        let pledged = crowdfund.pledgedAmount ?? crowdfund.raisedAmount
        return "\(format(pledged)) / \(format(crowdfund.goalAmount)) \(crowdfund.currency)"
    }

    private var deadlineLabel: String? {
        guard let deadline = crowdfund.deadlineAt else { return nil }
        if deadline < Date() { return "Ended" }
        return "Ends \(RelativeTime.short(deadline))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(crowdfund.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            ProgressView(value: crowdfund.progress)
                .tint(TribeColor.accentAmber)

            HStack(spacing: 10) {
                Text(raisedText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(TribeColor.accentAmber)
                    .monospacedDigit()
                Spacer(minLength: 8)
                if let label = deadlineLabel {
                    Text(label)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tribeCard(cornerRadius: 16, padding: 14)
    }

    private func format(_ d: Decimal) -> String {
        let n = NSDecimalNumber(decimal: d).doubleValue
        return String(format: "%g", n)
    }
}

// MARK: - Shared chip

private func metaChip(_ text: String, symbol: String, tint: Color) -> some View {
    HStack(spacing: 4) {
        Image(systemName: symbol)
            .font(.caption2.weight(.semibold))
        Text(text)
            .font(.caption2.weight(.medium))
            .lineLimit(1)
    }
    .foregroundStyle(tint)
    .padding(.horizontal, 8)
    .padding(.vertical, 3)
    .background(Capsule().fill(tint.opacity(0.12)))
}

// MARK: - People "See all" destination

private struct PeopleListDestination: View {
    @EnvironmentObject private var app: AppState
    let users: [User]
    @State private var selectedTID: String?

    var body: some View {
        List {
            ForEach(users) { user in
                PeopleListRow(user: user)
                    .contentShape(Rectangle())
                    .onTapGesture { selectedTID = user.tid }
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .navigationTitle("People")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $selectedTID) { tid in
            ProfileView(tid: tid)
        }
    }
}

private struct PeopleListRow: View {
    let user: User

    private var handle: String {
        if let u = user.username { return "@\(u).tribe" }
        return "@tid\(user.tid)"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            UserAvatar(
                tid: user.tid,
                initial: user.initial,
                size: 48,
                seed: user.username ?? user.tid
            )
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(user.displayName)
                            .font(.subheadline.weight(.bold))
                            .lineLimit(1)
                        Text(handle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    FollowButton(targetTID: user.tid)
                }
                if let bio = user.profile?.bio, !bio.isEmpty {
                    Text(bio)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(TribeColor.cardStroke.opacity(0.4))
                .frame(height: 0.5)
        }
    }
}
