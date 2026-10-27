import SwiftUI

/// Réseau social de la page « À propos ».
struct SocialLink: Identifiable {
    let id: String
    let label: String
    let value: String?
}

/// Tri des clips d'une chaîne (paramètres `sort` et `time` de Kick).
enum ClipSort: Int, CaseIterable, Identifiable {
    case allTime, month, week, today, recent

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .allTime: return L("Top · all time")
        case .month: return L("Top · this month")
        case .week: return L("Top · this week")
        case .today: return L("Top · today")
        case .recent: return L("Most recent")
        }
    }

    var sort: String { self == .recent ? "date" : "view" }

    var time: String {
        switch self {
        case .allTime, .recent: return "all"
        case .month: return "month"
        case .week: return "week"
        case .today: return "day"
        }
    }
}

@MainActor
final class ChannelModel: ObservableObject {
    @Published private(set) var channel: KChannel?
    @Published private(set) var vods: [KVod] = []
    @Published private(set) var clips: [KClip] = []
    @Published private(set) var error: String?
    @Published private(set) var loadingClips = false
    @Published var clipSort = ClipSort.allTime
    private var clipsCursor: String?
    let slug: String

    init(slug: String) {
        self.slug = slug
    }

    func load() async {
        do {
            channel = try await KickAPI.channel(slug)
            error = nil
        } catch {
            self.error = KickAPI.message(error)
            return
        }
        vods = (try? await KickAPI.vods(slug)) ?? []
        await reloadClips()
    }

    func reloadClips() async {
        clipsCursor = nil
        loadingClips = true
        defer { loadingClips = false }
        if let page = try? await KickAPI.clips(slug, sort: clipSort.sort, time: clipSort.time, cursor: nil) {
            clips = page.clips
            clipsCursor = page.nextCursor
        } else {
            clips = []
        }
    }

    func moreClips() async {
        guard let cursor = clipsCursor, !loadingClips else { return }
        loadingClips = true
        defer { loadingClips = false }
        guard let page = try? await KickAPI.clips(slug, sort: clipSort.sort, time: clipSort.time, cursor: cursor) else { return }
        let known = Set(clips.map(\.id))
        clips += page.clips.filter { !known.contains($0.id) }
        clipsCursor = page.nextCursor
    }
}

struct ChannelView: View {
    let slug: String
    @StateObject private var model: ChannelModel
    @ObservedObject private var follows = Follows.shared
    @ObservedObject private var multi = MultiView.shared
    @State private var tab = 0

    init(slug: String) {
        self.slug = slug
        _model = StateObject(wrappedValue: ChannelModel(slug: slug))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let channel = model.channel {
                    if let banner = channel.bannerImage?.best {
                        Thumb(url: banner).aspectRatio(3, contentMode: .fit)
                    }
                    header(channel)
                    Picker("", selection: $tab) {
                        Text(L("VODs")).tag(0)
                        Text(L("Clips")).tag(1)
                        Text(L("About")).tag(2)
                    }
                    .pickerStyle(.segmented)
                    switch tab {
                    case 0: vodsList(channel)
                    case 1: clipsList
                    default: about(channel)
                    }
                } else if let error = model.error {
                    ErrorView(message: error) { Task { await model.load() } }
                } else {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                }
            }
            .padding()
            .padding(.bottom, 60)
        }
        .navigationTitle(model.channel?.name ?? slug)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    channelMenu(slug)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .task {
            if model.channel == nil { await model.load() }
        }
        .onChange(of: model.clipSort) { _ in
            Task { await model.reloadClips() }
        }
    }

    private func header(_ channel: KChannel) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Avatar(url: channel.user?.avatar, size: 64)
                VStack(alignment: .leading, spacing: 4) {
                    Text(channel.name).font(.title3.weight(.bold))
                    if let followers = channel.followersCount {
                        Text(L("%@ followers", Fmt.count(followers.value)))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if !channel.isLive {
                        Text(L("Offline")).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button {
                    follows.toggle(channel.slug)
                } label: {
                    Image(systemName: follows.isFollowed(channel.slug) ? "heart.fill" : "heart")
                        .font(.title3)
                }
                .accessibilityLabel(follows.isFollowed(channel.slug) ? L("Unfollow") : L("Follow"))
            }
            if channel.isLive, let live = channel.livestream {
                NavigationLink(value: Route.live(channel.slug)) {
                    VStack(alignment: .leading, spacing: 6) {
                        Thumb(url: live.thumbnail?.best)
                            .aspectRatio(16 / 9, contentMode: .fit)
                            .overlay {
                                Image(systemName: "play.circle.fill")
                                    .font(.system(size: 48))
                                    .foregroundColor(.white.opacity(0.9))
                            }
                            .overlay(alignment: .topLeading) { LiveBadge().padding(8) }
                        Text(live.sessionTitle ?? "")
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(2)
                        Text([live.categories?.first?.name, L("%@ viewers", Fmt.count(live.viewerCount))]
                            .compactMap { $0 }.joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func vodsList(_ channel: KChannel) -> some View {
        if model.vods.isEmpty {
            Text(L("No VODs.")).foregroundStyle(.secondary).padding(.top, 8)
        }
        ForEach(model.vods) { vod in
            NavigationLink(value: Route.vod(vod, channel.ref)) {
                HStack(alignment: .top, spacing: 10) {
                    Thumb(url: vod.thumbnail?.best)
                        .aspectRatio(16 / 9, contentMode: .fit)
                        .frame(width: 150)
                        .overlay(alignment: .bottomTrailing) {
                            if let ms = vod.duration, ms > 0 {
                                Text(Fmt.clock(ms / 1000))
                                    .font(.caption2.weight(.semibold))
                                    .padding(.horizontal, 4)
                                    .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 3))
                                    .padding(4)
                            }
                        }
                        .overlay(alignment: .bottom) {
                            progressBar(vod)
                        }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(vod.sessionTitle ?? "VOD")
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(3)
                        Text([Fmt.relative(KDate.parse(vod.startTime)), vod.video?.views.map { L("%@ views", Fmt.count($0)) }]
                            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let category = vod.categories?.first?.name {
                            Text(category).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.plain)
        }
    }

    /// Avancement d'une VOD déjà commencée.
    @ViewBuilder
    private func progressBar(_ vod: KVod) -> some View {
        if let seconds = VodProgress.get(vod.id), let ms = vod.duration, ms > 0 {
            GeometryReader { geo in
                Rectangle()
                    .fill(Theme.accent)
                    .frame(width: geo.size.width * min(1, seconds / (Double(ms) / 1000)), height: 3)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
    }

    @ViewBuilder
    private var clipsList: some View {
        Picker(L("Sort"), selection: $model.clipSort) {
            ForEach(ClipSort.allCases) { sort in
                Text(sort.title).tag(sort)
            }
        }
        .pickerStyle(.menu)
        if model.clips.isEmpty && !model.loadingClips {
            Text(L("No clips.")).foregroundStyle(.secondary).padding(.top, 8)
        }
        ForEach(model.clips) { clip in
            NavigationLink(value: Route.clip(clip)) {
                HStack(alignment: .top, spacing: 10) {
                    Thumb(url: clip.thumbnailUrl.flatMap(URL.init(string:)))
                        .aspectRatio(16 / 9, contentMode: .fit)
                        .frame(width: 150)
                        .overlay(alignment: .bottomTrailing) {
                            if let seconds = clip.duration, seconds > 0 {
                                Text(Fmt.clock(seconds))
                                    .font(.caption2.weight(.semibold))
                                    .padding(.horizontal, 4)
                                    .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 3))
                                    .padding(4)
                            }
                        }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(clip.title ?? "Clip")
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(3)
                        Text([clip.views.map { L("%@ views", Fmt.count($0)) }, Fmt.relative(KDate.parse(clip.createdAt))]
                            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let category = clip.category?.name {
                            Text(category).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.plain)
            .onAppear {
                if clip.id == model.clips.last?.id { Task { await model.moreClips() } }
            }
        }
        if model.loadingClips {
            ProgressView().frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private func about(_ channel: KChannel) -> some View {
        let bio = channel.user?.bio?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        Text(bio.isEmpty ? L("No description.") : bio)
            .font(.subheadline)
            .foregroundColor(bio.isEmpty ? .secondary : .primary)
        let socials = [
            SocialLink(id: "twitter", label: "X", value: channel.user?.twitter),
            SocialLink(id: "instagram", label: "Instagram", value: channel.user?.instagram),
            SocialLink(id: "youtube", label: "YouTube", value: channel.user?.youtube),
            SocialLink(id: "tiktok", label: "TikTok", value: channel.user?.tiktok),
            SocialLink(id: "discord", label: "Discord", value: channel.user?.discord),
            SocialLink(id: "facebook", label: "Facebook", value: channel.user?.facebook),
        ]
        ForEach(socials) { item in
            if let url = Social.url(item.id, item.value) {
                Link(destination: url) {
                    HStack {
                        Text(item.label).font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(item.value ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        Image(systemName: "arrow.up.right.square").font(.caption)
                    }
                    .padding(.vertical, 6)
                }
            }
        }
        let recent = channel.recentCategories?.items ?? []
        if !recent.isEmpty {
            SectionTitle(text: L("Recent categories"))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(recent) { category in
                        NavigationLink(value: Route.category(category)) {
                            CategoryTile(category: category).frame(width: 100)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}
