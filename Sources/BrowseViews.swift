import SwiftUI

// MARK: - Directs (accueil et catégorie)

@MainActor
final class LivesModel: ObservableObject {
    @Published private(set) var lives: [KLive] = []
    @Published private(set) var error: String?
    @Published private(set) var loading = false
    private var page = 1
    private var more = true
    let category: String?

    init(category: String?) {
        self.category = category
    }

    func reload() async {
        page = 1
        more = true
        lives = []
        await loadMore()
    }

    func loadMore() async {
        guard !loading, more else { return }
        loading = true
        defer { loading = false }
        do {
            let result = try await KickAPI.lives(page: page, category: category)
            let known = Set(lives.map(\.id))
            lives += result.data.filter { !known.contains($0.id) }
            more = result.nextPageUrl != nil && !result.data.isEmpty
            page += 1
            error = nil
        } catch {
            self.error = KickAPI.message(error)
        }
    }
}

struct LiveCard: View {
    let live: KLive

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Thumb(url: live.thumbnail?.best)
                .aspectRatio(16 / 9, contentMode: .fit)
                .overlay(alignment: .topLeading) {
                    HStack(spacing: 6) {
                        LiveBadge()
                        Text(Fmt.count(live.viewerCount))
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 4))
                        if live.isMature == true {
                            Text("18+")
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 3)
                                .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 4))
                        }
                    }
                    .padding(8)
                }
            HStack(alignment: .top, spacing: 10) {
                Avatar(url: live.channel?.user?.avatar, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(live.sessionTitle ?? "")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                    Text(live.channel?.user?.username ?? live.channel?.slug ?? "")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text([live.categories?.first?.name, live.language].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .contentShape(Rectangle())
    }
}

/// Liste des directs d'un modèle, avec la suite au bas de la liste.
struct LivesList<Header: View>: View {
    let lives: [KLive]
    @ObservedObject var model: LivesModel
    @ViewBuilder let header: () -> Header

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                header()
                if let error = model.error, lives.isEmpty {
                    ErrorView(message: error) { Task { await model.reload() } }
                }
                ForEach(lives) { live in
                    let slug = live.channel?.slug ?? ""
                    NavigationLink(value: Route.live(slug)) {
                        LiveCard(live: live)
                    }
                    .buttonStyle(.plain)
                    .contextMenu { channelMenu(slug) }
                    .onAppear {
                        if live.id == model.lives.last?.id { Task { await model.loadMore() } }
                    }
                }
                if model.loading {
                    ProgressView().frame(maxWidth: .infinity).padding()
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 80)
        }
        .refreshable { await model.reload() }
    }
}

/// Chaîne ronde d'une rangée (suivies en direct, vues récemment).
struct ChannelBubble: View {
    let name: String
    let avatar: URL?
    var live = false

    var body: some View {
        VStack(spacing: 6) {
            Avatar(url: avatar, size: 58)
                .overlay {
                    if live { Circle().stroke(Theme.live, lineWidth: 2.5) }
                }
            Text(name)
                .font(.caption2)
                .lineLimit(1)
                .frame(width: 70)
        }
    }
}

struct HomeView: View {
    @StateObject private var model = LivesModel(category: nil)
    @ObservedObject private var settings = Settings.shared
    @ObservedObject private var follows = FollowsModel.shared
    @ObservedObject private var history = History.shared

    private var languages: [String] {
        Array(Set(model.lives.compactMap(\.language))).sorted()
    }

    private var shown: [KLive] {
        model.lives.filter { live in
            (settings.homeLanguage == nil || live.language == settings.homeLanguage)
                && !(settings.hideMature && live.isMature == true)
        }
    }

    private var liveFollows: [KChannel] { follows.channels.filter(\.isLive) }

    var body: some View {
        NavigationStack {
            LivesList(lives: shown, model: model) {
                if !liveFollows.isEmpty {
                    SectionTitle(text: L("Followed channels live"))
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(liveFollows, id: \.slug) { channel in
                                NavigationLink(value: Route.live(channel.slug)) {
                                    ChannelBubble(name: channel.name, avatar: channel.user?.avatar, live: true)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                if !history.channels.isEmpty {
                    SectionTitle(text: L("Recently watched"))
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(history.channels, id: \.slug) { ref in
                                NavigationLink(value: Route.channel(ref.slug)) {
                                    ChannelBubble(name: ref.name, avatar: ref.avatarURL)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                if languages.count > 1 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            chip(L("All"), selected: settings.homeLanguage == nil) { settings.homeLanguage = nil }
                            ForEach(languages, id: \.self) { name in
                                chip(name, selected: settings.homeLanguage == name) { settings.homeLanguage = name }
                            }
                        }
                    }
                }
            }
            .navigationTitle(L("Live"))
            .kickRoutes()
        }
        .task {
            if model.lives.isEmpty { await model.reload() }
            if follows.channels.isEmpty && !Follows.shared.slugs.isEmpty { await follows.load(Follows.shared.slugs) }
        }
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(selected ? Theme.accent : Color.white.opacity(0.1), in: Capsule())
                .foregroundColor(selected ? .black : .primary)
        }
        .buttonStyle(.plain)
    }
}

struct CategoryLivesView: View {
    let category: KCategory
    @StateObject private var model: LivesModel
    @ObservedObject private var settings = Settings.shared

    init(category: KCategory) {
        self.category = category
        _model = StateObject(wrappedValue: LivesModel(category: category.slug))
    }

    var body: some View {
        LivesList(lives: model.lives.filter { !(settings.hideMature && $0.isMature == true) }, model: model) {
            EmptyView()
        }
        .navigationTitle(category.name)
        .task {
            if model.lives.isEmpty { await model.reload() }
        }
    }
}

// MARK: - Catégories

@MainActor
final class CategoriesModel: ObservableObject {
    @Published private(set) var categories: [KCategory] = []
    @Published private(set) var error: String?
    @Published private(set) var loading = false
    private var page = 1
    private var more = true

    func reload() async {
        page = 1
        more = true
        categories = []
        await loadMore()
    }

    func loadMore() async {
        guard !loading, more else { return }
        loading = true
        defer { loading = false }
        do {
            let result = try await KickAPI.categories(page: page)
            let known = Set(categories.map(\.id))
            categories += result.data.filter { !known.contains($0.id) }
            more = result.nextPageUrl != nil && !result.data.isEmpty
            page += 1
            error = nil
        } catch {
            self.error = KickAPI.message(error)
        }
    }
}

struct CategoryTile: View {
    let category: KCategory

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Thumb(url: category.banner?.best)
                .aspectRatio(3 / 4, contentMode: .fit)
            Text(category.name)
                .font(.caption.weight(.semibold))
                .lineLimit(2)
            if let viewers = category.viewers {
                Text(L("%@ viewers", Fmt.count(viewers)))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct CategoriesView: View {
    @StateObject private var model = CategoriesModel()
    @State private var filter = ""
    private let columns = [GridItem(.adaptive(minimum: 105), spacing: 12)]

    private var shown: [KCategory] {
        let text = filter.trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? model.categories : model.categories.filter { $0.name.localizedCaseInsensitiveContains(text) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if let error = model.error, model.categories.isEmpty {
                    ErrorView(message: error) { Task { await model.reload() } }
                }
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(shown) { category in
                        NavigationLink(value: Route.category(category)) {
                            CategoryTile(category: category)
                        }
                        .buttonStyle(.plain)
                        .onAppear {
                            if category.id == model.categories.last?.id { Task { await model.loadMore() } }
                        }
                    }
                }
                .padding()
                if model.loading {
                    ProgressView().padding()
                }
                Color.clear.frame(height: 70)
            }
            .refreshable { await model.reload() }
            .searchable(text: $filter, prompt: L("Filter categories"))
            .navigationTitle(L("Browse"))
            .kickRoutes()
        }
        .task {
            if model.categories.isEmpty { await model.reload() }
        }
    }
}

// MARK: - Recherche

struct SearchView: View {
    @State private var query = ""
    @State private var channels: [KSearchChannel] = []
    @State private var categories: [KCategory] = []
    @State private var error: String?
    @State private var loading = false
    @State private var searched = false

    var body: some View {
        NavigationStack {
            List {
                if let error {
                    Text(error).foregroundStyle(.secondary)
                } else if searched && !loading && channels.isEmpty && categories.isEmpty {
                    Text(L("No results.")).foregroundStyle(.secondary)
                }
                if !channels.isEmpty {
                    Section(L("Channels")) {
                        ForEach(channels) { channel in
                            NavigationLink(value: Route.channel(channel.slug)) {
                                HStack(spacing: 12) {
                                    Avatar(url: channel.user?.avatar, size: 40)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(channel.user?.username ?? channel.slug)
                                            .font(.body.weight(.semibold))
                                        if let followers = channel.followersCount {
                                            Text(L("%@ followers", Fmt.count(followers.value)))
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                    if channel.isLive == true { LiveBadge() }
                                }
                            }
                            .contextMenu { channelMenu(channel.slug) }
                        }
                    }
                }
                if !categories.isEmpty {
                    Section(L("Categories")) {
                        ForEach(categories) { category in
                            NavigationLink(value: Route.category(category)) {
                                HStack(spacing: 12) {
                                    Thumb(url: category.banner?.best)
                                        .frame(width: 36, height: 48)
                                    Text(category.name).font(.body.weight(.semibold))
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
            .overlay {
                if loading && channels.isEmpty && categories.isEmpty { ProgressView() }
            }
            .searchable(text: $query, prompt: L("Search channels and categories"))
            .navigationTitle(L("Search"))
            .kickRoutes()
            .task(id: query) { await search() }
        }
    }

    private func search() async {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard text.count >= 2 else {
            channels = []
            categories = []
            error = nil
            searched = false
            return
        }
        // Attente : une recherche par pause de frappe, pas une par lettre.
        try? await Task.sleep(nanoseconds: 400_000_000)
        guard !Task.isCancelled else { return }
        loading = true
        defer { loading = false }
        do {
            let result = try await KickAPI.search(text)
            channels = result.channels
            categories = result.categories
            error = nil
            searched = true
        } catch {
            if !Task.isCancelled { self.error = KickAPI.message(error) }
        }
    }
}
