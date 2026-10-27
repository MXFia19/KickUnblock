import AVKit
import SwiftUI

/// Ce que lit le lecteur.
enum WatchSource: Hashable {
    case live(String)           // pseudo de la chaîne
    case vod(KVod, String)      // VOD et nom de la chaîne
    case clip(KClip)
}

/// Lecteur d'iOS (plein écran, image dans l'image, AirPlay).
struct VideoPlayerView: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.allowsPictureInPicturePlayback = true
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        if controller.player !== player { controller.player = player }
    }
}

@MainActor
final class WatchModel: ObservableObject {
    @Published private(set) var player: AVPlayer?
    @Published private(set) var channel: KChannel?
    @Published private(set) var error: String?

    /// Flux du direct (adresse relue à chaque ouverture : son jeton expire),
    /// de la VOD ou du clip, lu directement par AVPlayer.
    func start(_ source: WatchSource) async {
        switch source {
        case .live(let slug):
            do {
                let c = try await KickAPI.channel(slug)
                channel = c
                guard c.isLive, let text = c.playbackUrl, let url = URL(string: text) else {
                    error = "Cette chaîne n'est pas en direct."
                    return
                }
                play(url)
            } catch {
                self.error = KickAPI.message(error)
            }
        case .vod(let vod, _):
            guard let text = vod.source, let url = URL(string: text) else {
                error = "Cette VOD n'a pas de vidéo lisible."
                return
            }
            play(url)
        case .clip(let clip):
            guard let text = clip.videoUrl ?? clip.clipUrl, let url = URL(string: text) else {
                error = "Ce clip n'a pas de vidéo lisible."
                return
            }
            play(url)
        }
    }

    private func play(_ url: URL) {
        let p = AVPlayer(url: url)
        player = p
        p.play()
    }

    func stop() {
        player?.pause()
        player = nil
    }
}

struct WatchView: View {
    let source: WatchSource
    @StateObject private var model = WatchModel()
    @StateObject private var chat = ChatModel()

    private var isLive: Bool {
        if case .live = source { return true }
        return false
    }

    var body: some View {
        VStack(spacing: 0) {
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
            }
            .aspectRatio(16 / 9, contentMode: .fit)
            info
                .padding(.horizontal)
                .padding(.vertical, 10)
            if isLive {
                Divider()
                ChatView(model: chat)
            } else {
                Spacer(minLength: 0)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await model.start(source)
            if isLive, let id = model.channel?.id { chat.start(channelId: id) }
        }
        .onDisappear {
            model.stop()
            chat.stop()
        }
    }

    private var title: String {
        switch source {
        case .live(let slug): return model.channel?.name ?? slug
        case .vod(_, let name): return name
        case .clip(let clip): return clip.channel?.username ?? "Clip"
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
                        Text([live.categories?.first?.name, "\(Fmt.count(live.viewerCount)) spectateurs"]
                            .compactMap { $0 }.joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .vod(let vod, let name):
            VStack(alignment: .leading, spacing: 4) {
                Text(vod.sessionTitle ?? "VOD")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(3)
                Text([name, Fmt.relative(KDate.parse(vod.startTime))].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .clip(let clip):
            VStack(alignment: .leading, spacing: 4) {
                Text(clip.title ?? "Clip")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(3)
                Text([clip.channel?.username, clip.views.map { "\(Fmt.count($0)) vues" }].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Chat

/// Chat du direct : derniers messages relus toutes les 3 s (API publique de
/// l'historique du chat), ajoutés sans doublon, 200 gardés.
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
            .filter { $0.type == nil || $0.type == "message" }
            .filter { seen.insert($0.id).inserted }
            .sorted { ($0.createdAt ?? "") < ($1.createdAt ?? "") }
        guard !fresh.isEmpty else { return }
        messages += fresh
        if messages.count > 200 { messages.removeFirst(messages.count - 200) }
        if seen.count > 2000 { seen = Set(messages.map(\.id)) }
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

    private static func words(_ text: String) -> [ChatToken] {
        text.split(separator: " ", omittingEmptySubsequences: true).map { .text(String($0)) }
    }
}

struct ChatView: View {
    @ObservedObject var model: ChatModel

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    if let error = model.error, model.messages.isEmpty {
                        Text(error).font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(model.messages) { message in
                        ChatRow(message: message).id(message.id)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .onChange(of: model.messages.last?.id) { id in
                guard let id else { return }
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(id, anchor: .bottom) }
            }
        }
    }
}

struct ChatRow: View {
    let message: KChatMessage

    var body: some View {
        FlowLayout(spacing: 4) {
            Text(message.sender?.username ?? "?")
                .font(.subheadline.weight(.bold))
                .foregroundColor(Color(hex: message.sender?.identity?.color) ?? Theme.accent)
            ForEach(Array(ChatToken.parse(message.content ?? "").enumerated()), id: \.offset) { _, token in
                switch token {
                case .text(let word):
                    Text(word).font(.subheadline)
                case .emote(let id, let name):
                    AsyncImage(url: URL(string: "https://files.kick.com/emotes/\(id)/fullsize")) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFit()
                        } else {
                            Text(name).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 26, height: 26)
                }
            }
        }
    }
}
