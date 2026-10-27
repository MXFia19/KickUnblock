import AVKit
import SwiftUI

/// Ce que lit le lecteur.
enum WatchSource: Hashable {
    case live(String)               // pseudo de la chaîne
    case vod(KVod, ChannelRef)
    case clip(KClip)
}

/// Garde le lecteur pendant l'image dans l'image, même après avoir quitté
/// son écran ; la vidéo s'arrête quand le PiP se ferme hors de l'écran.
final class PiPKeeper: NSObject, AVPlayerViewControllerDelegate {
    static let shared = PiPKeeper()
    private(set) var active = false
    private var kept: AVPlayerViewController?

    func playerViewControllerWillStartPictureInPicture(_ playerViewController: AVPlayerViewController) {
        active = true
        kept = playerViewController
    }

    func playerViewControllerDidStopPictureInPicture(_ playerViewController: AVPlayerViewController) {
        active = false
        if playerViewController.view.window == nil { playerViewController.player?.pause() }
        kept = nil
    }

    func playerViewController(
        _ playerViewController: AVPlayerViewController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
    ) {
        completionHandler(playerViewController.view.window != nil)
    }
}

/// Lecteur d'iOS (plein écran, image dans l'image, AirPlay, vitesse des VODs).
/// Sans commandes : tuiles du multi-live.
struct VideoPlayerView: UIViewControllerRepresentable {
    let player: AVPlayer
    var controls = true

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.videoGravity = .resizeAspect
        controller.showsPlaybackControls = controls
        controller.allowsPictureInPicturePlayback = controls
        controller.canStartPictureInPictureAutomaticallyFromInline = controls
        if controls { controller.delegate = PiPKeeper.shared }
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        if controller.player !== player { controller.player = player }
    }
}

/// Lecteur avec la qualité maximale des réglages.
func makePlayer(_ url: URL, maxHeight: Int = Settings.shared.maxQuality) -> AVPlayer {
    let item = AVPlayerItem(url: url)
    if maxHeight > 0 {
        item.preferredMaximumResolution = CGSize(width: Double(maxHeight) * 16 / 9, height: Double(maxHeight))
        let rates: [Int: Double] = [1080: 8_000_000, 720: 4_500_000, 480: 2_000_000, 360: 1_000_000, 160: 400_000]
        item.preferredPeakBitRate = rates[maxHeight] ?? 0
    }
    return AVPlayer(playerItem: item)
}

@MainActor
final class WatchModel: ObservableObject {
    @Published private(set) var player: AVPlayer?
    @Published private(set) var channel: KChannel?
    @Published private(set) var error: String?
    @Published private(set) var ended = false
    @Published private(set) var sleepAt: Date?
    @Published private(set) var resumedAt: Double?
    private var refreshTask: Task<Void, Never>?
    private var sleepTask: Task<Void, Never>?
    private var timeObserver: Any?

    /// Flux du direct (adresse relue à chaque ouverture : son jeton expire),
    /// de la VOD (reprise où elle s'était arrêtée) ou du clip.
    func start(_ source: WatchSource) async {
        guard player == nil, error == nil else { return }
        switch source {
        case .live(let slug):
            do {
                let c = try await KickAPI.channel(slug)
                channel = c
                History.shared.add(c.ref)
                guard c.isLive, let text = c.playbackUrl, let url = URL(string: text) else {
                    error = L("This channel is not live.")
                    return
                }
                let p = makePlayer(url)
                player = p
                p.play()
                refresh(slug)
            } catch {
                self.error = KickAPI.message(error)
            }
        case .vod(let vod, let ref):
            History.shared.add(ref)
            guard let text = vod.source, let url = URL(string: text) else {
                error = L("This VOD has no playable video.")
                return
            }
            let p = makePlayer(url)
            if Settings.shared.resumeVods, let saved = VodProgress.get(vod.id), saved > 30 {
                let total = Double(vod.duration ?? 0) / 1000
                if total == 0 || saved < total - 30 {
                    _ = await p.seek(to: CMTime(seconds: saved, preferredTimescale: 1))
                    resumedAt = saved
                    Task { [weak self] in
                        try? await Task.sleep(nanoseconds: 8_000_000_000)
                        self?.resumedAt = nil
                    }
                }
            }
            let vodId = vod.id
            timeObserver = p.addPeriodicTimeObserver(forInterval: CMTime(seconds: 10, preferredTimescale: 1), queue: .main) { time in
                let seconds = time.seconds
                if seconds.isFinite, seconds > 5 { VodProgress.set(vodId, seconds) }
            }
            player = p
            p.play()
        case .clip(let clip):
            if let slug = clip.channel?.slug {
                History.shared.add(ChannelRef(slug: slug, name: clip.channel?.username ?? slug, avatar: clip.channel?.profilePicture))
            }
            guard let text = clip.videoUrl ?? clip.clipUrl, let url = URL(string: text) else {
                error = L("This clip has no playable video.")
                return
            }
            let p = makePlayer(url)
            player = p
            p.play()
        }
    }

    /// Spectateurs et titre relus chaque minute ; direct fini : lecteur arrêté.
    private func refresh(_ slug: String) {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                guard !Task.isCancelled, let c = try? await KickAPI.channel(slug) else { continue }
                self?.channel = c
                if !c.isLive {
                    self?.ended = true
                    self?.player?.pause()
                    return
                }
            }
        }
    }

    func setSleep(minutes: Int?) {
        sleepTask?.cancel()
        sleepTask = nil
        guard let minutes else {
            sleepAt = nil
            return
        }
        sleepAt = Date().addingTimeInterval(Double(minutes) * 60)
        sleepTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(minutes) * 60_000_000_000)
            guard !Task.isCancelled else { return }
            self?.player?.pause()
            self?.sleepAt = nil
        }
    }

    func restart() {
        player?.seek(to: .zero)
        resumedAt = nil
    }

    func stop() {
        refreshTask?.cancel()
        refreshTask = nil
        sleepTask?.cancel()
        sleepTask = nil
        sleepAt = nil
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }
        player?.pause()
        player = nil
    }
}

struct WatchView: View {
    let source: WatchSource
    @StateObject private var model = WatchModel()
    @StateObject private var chat = ChatModel()
    @ObservedObject private var settings = Settings.shared
    @ObservedObject private var multi = MultiView.shared

    private var isLive: Bool {
        if case .live = source { return true }
        return false
    }

    private var showChat: Bool { isLive && settings.chatVisible }

    private var slug: String? {
        switch source {
        case .live(let s): return s
        case .vod(_, let ref): return ref.slug
        case .clip(let clip): return clip.channel?.slug
        }
    }

    var body: some View {
        GeometryReader { geo in
            if geo.size.width > geo.size.height {
                // Paysage : la vidéo en grand, le chat sur le côté.
                HStack(spacing: 0) {
                    video
                    if showChat {
                        Divider()
                        ChatView(model: chat).frame(width: min(340, geo.size.width * 0.34))
                    }
                }
            } else {
                VStack(spacing: 0) {
                    video.aspectRatio(16 / 9, contentMode: .fit)
                    info
                        .padding(.horizontal)
                        .padding(.vertical, 10)
                    if showChat {
                        Divider()
                        ChatView(model: chat)
                    } else {
                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar }
        .task {
            await model.start(source)
            if isLive, let id = model.channel?.id { chat.start(channelId: id) }
        }
        .onDisappear {
            chat.stop()
            if !PiPKeeper.shared.active { model.stop() }
        }
    }

    private var title: String {
        switch source {
        case .live(let slug): return model.channel?.name ?? slug
        case .vod(_, let ref): return ref.name
        case .clip(let clip): return clip.channel?.username ?? L("Clips")
        }
    }

    private var video: some View {
        ZStack {
            Color.black
            if let player = model.player {
                VideoPlayerView(player: player)
            } else if let error = model.error {
                Text(error)
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding()
            } else {
                ProgressView()
            }
            if model.ended {
                VStack(spacing: 8) {
                    Image(systemName: "dot.radiowaves.left.and.right").font(.title2)
                    Text(L("The stream has ended.")).font(.subheadline.weight(.semibold))
                }
                .padding()
                .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .overlay(alignment: .topLeading) {
            if let resumed = model.resumedAt {
                Button {
                    model.restart()
                } label: {
                    Label("\(L("Resumed at %@", Fmt.clock(Int(resumed)))) · \(L("Start over"))", systemImage: "backward.end.fill")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.black.opacity(0.7), in: Capsule())
                }
                .padding(10)
            }
        }
    }

    @ViewBuilder
    private var info: some View {
        switch source {
        case .live(let slug):
            VStack(alignment: .leading, spacing: 4) {
                Text(model.channel?.livestream?.sessionTitle ?? "")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                HStack(spacing: 8) {
                    NavigationLink(value: Route.channel(slug)) {
                        Text(model.channel?.name ?? slug).font(.caption.weight(.semibold))
                    }
                    if let live = model.channel?.livestream {
                        Text([live.categories?.first?.name, L("%@ viewers", Fmt.count(live.viewerCount))]
                            .compactMap { $0 }.joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if let start = KDate.parse(model.channel?.livestream?.startTime), !model.ended {
                    TimelineView(.periodic(from: Date(), by: 1)) { context in
                        Text(L("Live for %@", Fmt.clock(max(0, Int(context.date.timeIntervalSince(start))))))
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .vod(let vod, let ref):
            VStack(alignment: .leading, spacing: 4) {
                Text(vod.sessionTitle ?? "VOD")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(3)
                HStack(spacing: 8) {
                    NavigationLink(value: Route.channel(ref.slug)) {
                        Text(ref.name).font(.caption.weight(.semibold))
                    }
                    Text([vod.categories?.first?.name, Fmt.relative(KDate.parse(vod.startTime))]
                        .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .clip(let clip):
            VStack(alignment: .leading, spacing: 4) {
                Text(clip.title ?? "Clip")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(3)
                HStack(spacing: 8) {
                    if let channelSlug = clip.channel?.slug {
                        NavigationLink(value: Route.channel(channelSlug)) {
                            Text(clip.channel?.username ?? channelSlug).font(.caption.weight(.semibold))
                        }
                    }
                    Text([clip.views.map { L("%@ views", Fmt.count($0)) }, Fmt.relative(KDate.parse(clip.createdAt))]
                        .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var sleepLabel: String {
        model.sleepAt.map { L("Stops at %@", Fmt.time($0)) } ?? L("Sleep timer")
    }

    private var shareURL: URL? {
        switch source {
        case .live(let slug):
            return URL(string: "https://kick.com/\(slug)")
        case .vod(let vod, let ref):
            if let uuid = vod.video?.uuid { return URL(string: "https://kick.com/\(ref.slug)/videos/\(uuid)") }
            return URL(string: "https://kick.com/\(ref.slug)")
        case .clip(let clip):
            return URL(string: "https://kick.com/\(clip.channel?.slug ?? "")?clip=\(clip.id)")
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .navigationBarTrailing) {
            if isLive {
                Button {
                    settings.chatVisible.toggle()
                } label: {
                    Image(systemName: settings.chatVisible ? "bubble.left.fill" : "bubble.left")
                }
                .accessibilityLabel(settings.chatVisible ? L("Hide chat") : L("Show chat"))
            }
            Menu {
                if isLive, let slug {
                    Button {
                        multi.toggle(slug)
                    } label: {
                        Label(multi.contains(slug) ? L("Remove from multi-view") : L("Add to multi-view"), systemImage: "rectangle.grid.2x2")
                    }
                    .disabled(!multi.contains(slug) && multi.slugs.count >= MultiView.limit)
                }
                Menu {
                    Button(L("Off")) { model.setSleep(minutes: nil) }
                    ForEach([15, 30, 60, 90, 120], id: \.self) { minutes in
                        Button(L("%d min", minutes)) { model.setSleep(minutes: minutes) }
                    }
                } label: {
                    Label(sleepLabel, systemImage: "moon.zzz")
                }
                if let url = shareURL {
                    ShareLink(item: url) {
                        Label(L("Share"), systemImage: "square.and.arrow.up")
                    }
                    Link(destination: url) {
                        Label(L("Open on kick.com"), systemImage: "safari")
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }
}

// MARK: - Chat

/// Chat du direct : derniers messages relus toutes les 3 s (historique
/// public du chat), ajoutés sans doublon, 300 gardés.
@MainActor
final class ChatModel: ObservableObject {
    @Published private(set) var messages: [KChatMessage] = []
    @Published private(set) var error: String?
    private var seen = Set<String>()
    private var task: Task<Void, Never>?

    func start(channelId: Int) {
        stop()
        task = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    let list = try await KickAPI.messages(channelId: channelId)
                    self?.merge(list)
                    self?.error = nil
                } catch {
                    if !Task.isCancelled { self?.error = KickAPI.message(error) }
                }
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    private func merge(_ list: [KChatMessage]) {
        let fresh = list
            .filter { $0.type == nil || $0.type == "message" || $0.type == "reply" }
            .filter { seen.insert($0.id).inserted }
            .sorted { ($0.createdAt ?? "") < ($1.createdAt ?? "") }
        guard !fresh.isEmpty else { return }
        messages += fresh
        if messages.count > 300 { messages.removeFirst(messages.count - 300) }
        if seen.count > 3000 { seen = Set(messages.map(\.id)) }
    }
}

/// Morceau d'un message : un mot, ou une emote « [emote:ID:NOM] ».
enum ChatToken: Hashable {
    case text(String)
    case emote(String, String)

    private static let regex = try? NSRegularExpression(pattern: #"\[emote:(\d+):([^\]]*)\]"#)

    static func parse(_ text: String) -> [ChatToken] {
        guard let regex else { return words(text) }
        var out: [ChatToken] = []
        var last = text.startIndex
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        for match in regex.matches(in: text, range: range) {
            guard let whole = Range(match.range, in: text),
                  let id = Range(match.range(at: 1), in: text),
                  let name = Range(match.range(at: 2), in: text) else { continue }
            out += words(String(text[last..<whole.lowerBound]))
            out.append(.emote(String(text[id]), String(text[name])))
            last = whole.upperBound
        }
        out += words(String(text[last...]))
        return out
    }

    /// Texte lisible : les emotes deviennent leur nom.
    static func plain(_ text: String) -> String {
        parse(text).map { token -> String in
            switch token {
            case .text(let word): return word
            case .emote(_, let name): return name
            }
        }.joined(separator: " ")
    }

    private static func words(_ text: String) -> [ChatToken] {
        text.split(separator: " ", omittingEmptySubsequences: true).map { .text(String($0)) }
    }
}

struct ChatView: View {
    @ObservedObject var model: ChatModel
    @ObservedObject private var settings = Settings.shared
    @State private var atBottom = true

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    if let error = model.error, model.messages.isEmpty {
                        Text(error).font(.caption).foregroundStyle(.secondary)
                    } else if model.messages.isEmpty {
                        Text(L("Chat refreshes every 3 seconds.")).font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(model.messages) { message in
                        ChatRow(message: message, timestamps: settings.chatTimestamps, fontSize: settings.chatFontSize)
                            .id(message.id)
                    }
                    Color.clear
                        .frame(height: 1)
                        .id("bottom")
                        .onAppear { atBottom = true }
                        .onDisappear { atBottom = false }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .onChange(of: model.messages.last?.id) { _ in
                guard atBottom else { return }
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .overlay(alignment: .bottom) {
                if !atBottom && !model.messages.isEmpty {
                    Button {
                        withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                    } label: {
                        Label(L("Latest messages"), systemImage: "arrow.down")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Theme.accent, in: Capsule())
                            .foregroundColor(.black)
                    }
                    .padding(.bottom, 8)
                }
            }
        }
    }
}

/// Badge de chat de Kick → symbole.
struct BadgeIcon: View {
    let type: String
    var size: Double = 13

    private var style: (symbol: String, color: Color)? {
        switch type {
        case "broadcaster": return ("video.fill", Theme.live)
        case "moderator": return ("shield.fill", Theme.accent)
        case "vip": return ("crown.fill", .pink)
        case "og": return ("flame.fill", .orange)
        case "founder": return ("medal.fill", .yellow)
        case "verified": return ("checkmark.seal.fill", .cyan)
        case "staff": return ("wrench.and.screwdriver.fill", .purple)
        case "subscriber": return ("star.fill", .yellow)
        case "sub_gifter": return ("gift.fill", .pink)
        default: return nil
        }
    }

    var body: some View {
        if let style {
            Image(systemName: style.symbol)
                .font(.system(size: size))
                .foregroundColor(style.color)
        }
    }
}

struct ChatRow: View {
    let message: KChatMessage
    let timestamps: Bool
    let fontSize: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let reply = message.reply {
                Text("↪ @\(reply.username): \(ChatToken.plain(reply.content))")
                    .font(.system(size: fontSize - 3))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            FlowLayout(spacing: 4) {
                if timestamps {
                    Text(Fmt.time(KDate.parse(message.createdAt)))
                        .font(.system(size: fontSize - 3).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                ForEach(message.sender?.identity?.badges ?? [], id: \.self) { badge in
                    BadgeIcon(type: badge.type ?? "", size: fontSize - 2)
                }
                Text(message.sender?.username ?? "?")
                    .font(.system(size: fontSize, weight: .bold))
                    .foregroundColor(Color(hex: message.sender?.identity?.color) ?? Theme.accent)
                ForEach(Array(ChatToken.parse(message.content ?? "").enumerated()), id: \.offset) { _, token in
                    switch token {
                    case .text(let word):
                        Text(word).font(.system(size: fontSize))
                    case .emote(let id, let name):
                        AsyncImage(url: URL(string: "https://files.kick.com/emotes/\(id)/fullsize")) { phase in
                            if let image = phase.image {
                                image.resizable().scaledToFit()
                            } else {
                                Text(name).font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        .frame(width: fontSize + 11, height: fontSize + 11)
                    }
                }
            }
        }
    }
}
