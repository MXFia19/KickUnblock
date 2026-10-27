import SwiftUI

/// Chaînes suivies relues sur Kick (accueil et onglet Suivis).
@MainActor
final class FollowsModel: ObservableObject {
    static let shared = FollowsModel()
    @Published private(set) var channels: [KChannel] = []
    @Published private(set) var loading = false

    /// Chaînes suivies, relues 6 par 6 ; celles en direct d'abord.
    func load(_ slugs: [String]) async {
        loading = true
        defer { loading = false }
        var found: [KChannel] = []
        let list = Array(slugs.prefix(100))
        for start in stride(from: 0, to: list.count, by: 6) {
            let chunk = list[start..<min(start + 6, list.count)]
            await withTaskGroup(of: KChannel?.self) { group in
                for slug in chunk {
                    group.addTask { try? await KickAPI.channel(slug) }
                }
                for await channel in group {
                    if let channel { found.append(channel) }
                }
            }
        }
        channels = found.sorted { a, b in
            if a.isLive != b.isLive { return a.isLive }
            return a.name.lowercased() < b.name.lowercased()
        }
    }
}

struct FollowsView: View {
    @ObservedObject private var model = FollowsModel.shared
    @ObservedObject private var follows = Follows.shared

    var body: some View {
        NavigationStack {
            List {
                if follows.slugs.isEmpty {
                    Text(L("No followed channels yet. Tap the heart on a channel page to see it here."))
                        .foregroundStyle(.secondary)
                }
                ForEach(model.channels.filter { follows.isFollowed($0.slug) }, id: \.slug) { channel in
                    NavigationLink(value: channel.isLive ? Route.live(channel.slug) : Route.channel(channel.slug)) {
                        HStack(spacing: 12) {
                            Avatar(url: channel.user?.avatar, size: 44)
                                .overlay {
                                    if channel.isLive { Circle().stroke(Theme.live, lineWidth: 2) }
                                }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(channel.name).font(.body.weight(.semibold))
                                if channel.isLive, let live = channel.livestream {
                                    Text(live.sessionTitle ?? "")
                                        .font(.caption)
                                        .lineLimit(1)
                                        .foregroundStyle(.secondary)
                                    Text([live.categories?.first?.name, L("%@ viewers", Fmt.count(live.viewerCount))]
                                        .compactMap { $0 }.joined(separator: " · "))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text(L("Offline")).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if channel.isLive { LiveBadge() }
                        }
                    }
                    .contextMenu { channelMenu(channel.slug) }
                    .swipeActions {
                        Button(L("Unfollow"), role: .destructive) { follows.toggle(channel.slug) }
                    }
                }
            }
            .overlay {
                if model.loading && model.channels.isEmpty && !follows.slugs.isEmpty { ProgressView() }
            }
            .refreshable { await model.load(follows.slugs) }
            .navigationTitle(L("Following"))
            .kickRoutes()
            .task(id: follows.slugs) { await model.load(follows.slugs) }
        }
    }
}
