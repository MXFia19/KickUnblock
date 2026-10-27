import AVFoundation
import SwiftUI

@main
struct KickUnblockApp: App {
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Son des vidéos même en mode silencieux, en arrière-plan et en PiP.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        LiveAlerts.register()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .tint(Theme.accent)
                .preferredColorScheme(.dark)
        }
        .onChange(of: scenePhase) { phase in
            if phase == .background { LiveAlerts.schedule() }
        }
    }
}

enum AppTab: Hashable {
    case live, browse, search, following, settings
}

struct RootView: View {
    @ObservedObject private var settings = Settings.shared
    @ObservedObject private var multi = MultiView.shared
    @State private var tab = AppTab.live
    @State private var showMulti = false

    var body: some View {
        TabView(selection: $tab) {
            HomeView()
                .tabItem { Label(L("Live"), systemImage: "dot.radiowaves.left.and.right") }
                .tag(AppTab.live)
            CategoriesView()
                .tabItem { Label(L("Browse"), systemImage: "square.grid.2x2") }
                .tag(AppTab.browse)
            SearchView()
                .tabItem { Label(L("Search"), systemImage: "magnifyingglass") }
                .tag(AppTab.search)
            FollowsView()
                .tabItem { Label(L("Following"), systemImage: "heart") }
                .tag(AppTab.following)
            SettingsView()
                .tabItem { Label(L("Settings"), systemImage: "gearshape") }
                .tag(AppTab.settings)
        }
        // Langue changée : tous les textes sont refaits (l'onglet reste).
        .id(settings.language)
        .overlay(alignment: .bottomTrailing) {
            if !multi.slugs.isEmpty {
                Button {
                    showMulti = true
                } label: {
                    Label("\(L("Multi-view")) · \(multi.slugs.count)", systemImage: "rectangle.grid.2x2.fill")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Theme.accent, in: Capsule())
                        .foregroundColor(.black)
                }
                .padding(.trailing, 16)
                .padding(.bottom, 62)
            }
        }
        .fullScreenCover(isPresented: $showMulti) {
            MultiViewScreen()
        }
    }
}

/// Écrans ouverts depuis une liste (chaque onglet a sa pile de navigation).
enum Route: Hashable {
    case channel(String)            // pseudo de la chaîne
    case live(String)               // pseudo de la chaîne en direct
    case vod(KVod, ChannelRef)
    case clip(KClip)
    case category(KCategory)
}

struct RouteView: View {
    let route: Route

    var body: some View {
        switch route {
        case .channel(let slug): ChannelView(slug: slug)
        case .live(let slug): WatchView(source: .live(slug))
        case .vod(let vod, let ref): WatchView(source: .vod(vod, ref))
        case .clip(let clip): WatchView(source: .clip(clip))
        case .category(let category): CategoryLivesView(category: category)
        }
    }
}

extension View {
    func kickRoutes() -> some View {
        navigationDestination(for: Route.self) { RouteView(route: $0) }
    }
}

/// Menu d'une chaîne (appui long sur un direct) : suivre, multi-live, partager.
@MainActor @ViewBuilder
func channelMenu(_ slug: String) -> some View {
    let followed = Follows.shared.isFollowed(slug)
    Button {
        Follows.shared.toggle(slug)
    } label: {
        Label(followed ? L("Unfollow") : L("Follow"), systemImage: followed ? "heart.slash" : "heart")
    }
    let inMulti = MultiView.shared.contains(slug)
    Button {
        MultiView.shared.toggle(slug)
    } label: {
        Label(inMulti ? L("Remove from multi-view") : L("Add to multi-view"), systemImage: "rectangle.grid.2x2")
    }
    .disabled(!inMulti && MultiView.shared.slugs.count >= MultiView.limit)
    if let url = URL(string: "https://kick.com/\(slug)") {
        ShareLink(item: url) {
            Label(L("Share"), systemImage: "square.and.arrow.up")
        }
        Link(destination: url) {
            Label(L("Open on kick.com"), systemImage: "safari")
        }
    }
}
