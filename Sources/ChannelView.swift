import SwiftUI

@MainActor
final class ChannelModel: ObservableObject {
    @Published private(set) var channel: KChannel?
    @Published private(set) var vods: [KVod] = []
    @Published private(set) var clips: [KClip] = []
    @Published private(set) var error: String?
    @Published private(set) var loadingClips = false
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
        if let page = try? await KickAPI.clips(slug, cursor: nil) {
            clips = page.clips
            clipsCursor = page.nextCursor
        }
    }

    func moreClips() async {
        guard let cursor = clipsCursor, !loadingClips else { return }
        loadingClips = true
        defer { loadingClips = false }
        guard let page = try? await KickAPI.clips(slug, cursor: cursor) else { return }
        let known = Set(clips.map(\.id))
        clips += page.clips.filter { !known.contains($0.id) }
        clipsCursor = page.nextCursor
    }
}

struct ChannelView: View {
    let slug: String
    @StateObject private var model: ChannelModel
    @ObservedObject private var follows = Follows.shared
    @State private var tab = 0

    init(slug: String) {
        self.slug = slug
        _model = StateObject(wrappedValue: ChannelModel(slug: slug))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let channel = model.channel {
                    header(channel)
                    Picker("", selection: $tab) {
                        Text("VODs").tag(0)
                        Text("Clips").tag(1)
                    }
                    .pickerStyle(.segmented)
                    if tab == 0 { vodsList(channel) } else { clipsList }
                } else if let error = model.error {
                    ErrorView(message: error) { Task { await model.load() } }
                } else {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                }
            }
            .padding()
        }
        .navigationTitle(model.channel?.name ?? slug)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if model.channel == nil { await model.load() }
        }
    }

    private func header(_ channel: KChannel) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Avatar(url: channel.user?.avatar, size: 64)
                VStack(alignment: .leading, spacing: 4) {
                    Text(channel.name).font(.title3.weight(.bold))
                    if let followers = channel.followersCount {
                        Text("\(Fmt.count(followers.value)) abonnés")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button {
                    follows.toggle(channel.slug)
                } label: {
                    Image(systemName: follows.isFollowed(channel.slug) ? "heart.fill" : "heart")
                        .font(.title3)
                }
                .accessibilityLabel(follows.isFollowed(channel.slug) ? "Ne plus suivre" : "Suivre")
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
                        Text([live.categories?.first?.name, "\(Fmt.count(live.viewerCount)) spectateurs"]
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
            Text("Aucune VOD.").foregroundStyle(.secondary).padding(.top, 8)
        }
        ForEach(model.vods) { vod in
            NavigationLink(value: Route.vod(vod, channel.name)) {
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
                    VStack(alignment: .leading, spacing: 4) {
                        Text(vod.sessionTitle ?? "VOD")
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(3)
                        Text([Fmt.relative(KDate.parse(vod.startTime)), vod.video?.views.map { "\(Fmt.count($0)) vues" }]
                            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var clipsList: some View {
        if model.clips.isEmpty {
            Text("Aucun clip.").foregroundStyle(.secondary).padding(.top, 8)
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
                        Text([clip.views.map { "\(Fmt.count($0)) vues" }, Fmt.relative(KDate.parse(clip.createdAt))]
                            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
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
}
