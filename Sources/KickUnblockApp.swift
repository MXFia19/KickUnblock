import AVFoundation
import SwiftUI

@main
struct KickUnblockApp: App {
    init() {
        // Son des vidéos même en mode silencieux, en arrière-plan et en PiP.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .tint(Theme.accent)
                .preferredColorScheme(.dark)
        }
    }
}

struct RootView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("Directs", systemImage: "dot.radiowaves.left.and.right") }
            CategoriesView()
                .tabItem { Label("Catégories", systemImage: "square.grid.2x2") }
            SearchView()
                .tabItem { Label("Recherche", systemImage: "magnifyingglass") }
            FollowsView()
                .tabItem { Label("Suivis", systemImage: "heart") }
        }
    }
}

/// Écrans ouverts depuis une liste (chaque onglet a sa pile de navigation).
enum Route: Hashable {
    case channel(String)        // pseudo de la chaîne
    case live(String)           // pseudo de la chaîne en direct
    case vod(KVod, String)      // VOD et nom de la chaîne
    case clip(KClip)
    case category(KCategory)
}

struct RouteView: View {
    let route: Route

    var body: some View {
        switch route {
        case .channel(let slug): ChannelView(slug: slug)
        case .live(let slug): WatchView(source: .live(slug))
        case .vod(let vod, let name): WatchView(source: .vod(vod, name))
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
