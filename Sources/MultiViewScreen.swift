import AVKit
import SwiftUI

/// Une tuile du multi-live : son direct, en 720p au plus, son coupé sauf
/// pour la tuile choisie.
@MainActor
final class TileModel: ObservableObject {
    @Published private(set) var player: AVPlayer?
    @Published private(set) var name = ""
    @Published private(set) var error: String?

    func start(_ slug: String, audible: Bool) async {
        guard player == nil else { return }
        do {
            let c = try await KickAPI.channel(slug)
            name = c.name
            guard c.isLive, let text = c.playbackUrl, let url = URL(string: text) else {
                error = L("Offline")
                return
            }
            let p = makePlayer(url, maxHeight: 720)
            p.isMuted = !audible
            player = p
            p.play()
        } catch {
            self.error = KickAPI.message(error)
        }
    }

    func setAudible(_ on: Bool) {
        player?.isMuted = !on
    }

    func stop() {
        player?.pause()
        player = nil
    }
}

struct MultiTile: View {
    let slug: String
    let audible: Bool
    let onSelect: () -> Void
    let onRemove: () -> Void
    @StateObject private var model = TileModel()

    var body: some View {
        ZStack {
            Color.black
            if let player = model.player {
                VideoPlayerView(player: player, controls: false)
                    .allowsHitTesting(false)
            } else if let error = model.error {
                Text(error).font(.caption).foregroundStyle(.secondary)
            } else {
                ProgressView()
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .overlay(alignment: .topLeading) {
            HStack(spacing: 6) {
                Image(systemName: audible ? "speaker.wave.2.fill" : "speaker.slash.fill")
                Text(model.name.isEmpty ? slug : model.name).lineLimit(1)
            }
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.black.opacity(0.6), in: Capsule())
            .padding(6)
        }
        .overlay(alignment: .topTrailing) {
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundColor(.white.opacity(0.85))
            }
            .padding(6)
        }
        .overlay {
            if audible { Rectangle().stroke(Theme.accent, lineWidth: 2) }
        }
        .task { await model.start(slug, audible: audible) }
        .onChange(of: audible) { on in model.setAudible(on) }
        .onDisappear { model.stop() }
    }
}

/// Jusqu'à 4 directs à la fois ; toucher un direct pour l'entendre.
struct MultiViewScreen: View {
    @ObservedObject private var multi = MultiView.shared
    @Environment(\.dismiss) private var dismiss
    @State private var audio: String?

    var body: some View {
        GeometryReader { geo in
            let slugs = multi.slugs
            let landscape = geo.size.width > geo.size.height
            let columns = slugs.count <= 1 ? 1 : (slugs.count == 2 && !landscape ? 1 : 2)
            let rows = stride(from: 0, to: slugs.count, by: columns).map { Array(slugs[$0..<min($0 + columns, slugs.count)]) }
            VStack(spacing: 2) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 2) {
                        ForEach(row, id: \.self) { slug in
                            MultiTile(
                                slug: slug,
                                audible: audio == slug,
                                onSelect: { audio = slug },
                                onRemove: {
                                    multi.toggle(slug)
                                    if audio == slug { audio = multi.slugs.first }
                                }
                            )
                        }
                    }
                }
            }
        }
        .background(Color.black.ignoresSafeArea())
        .safeAreaInset(edge: .top) {
            HStack(spacing: 14) {
                Text(L("Tap a stream to hear it."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(L("Clear")) { multi.clear() }
                    .font(.subheadline)
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill").font(.title2)
                }
                .accessibilityLabel(L("Close"))
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
        }
        .onAppear {
            if audio == nil { audio = multi.slugs.first }
        }
        .onChange(of: multi.slugs) { slugs in
            if slugs.isEmpty { dismiss() }
        }
    }
}
