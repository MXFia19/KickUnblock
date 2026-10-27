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
                    if let category = live.categories?.first?.name {
                        Text(category)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
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
                    NavigationLink(value: Route.live(live.channel?.slug ?? "")) {
                        LiveCard(live: live)
                    }
                    .buttonStyle(.plain)
                    .onAppear {
                        if live.id == lives.last?.id { Task { await model.loadMore() } }
                    }
                }
                if model.loading {
                    ProgressView().frame(maxWidth: .infinity).padding()
                }
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .refreshable { await model.reload() }
    }
}

struct HomeView: View {
    @StateObject private var model = LivesModel(category: nil)
    @State private var language: String?

    private var languages: [String] {
        Array(Set(model.lives.compactMap(\.language))).sorted()
    }

    private var shown: [KLive] {
        guard let language else { return model.lives }
        return model.lives.filter { $0.language == language }
    }

    var body: some View {
        NavigationStack {
            LivesList(lives: shown, model: model) {
                if languages.count > 1 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            chip("Toutes", selected: language == nil) { language = nil }
                            ForEach(languages, id: \.self) { name in
                                chip(name, selected: language == name) { language = name }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Directs")
            .kickRoutes()
        }
        .task {
            if model.lives.isEmpty { await model.reload() }
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

    init(category: KCategory) {
        self.category = category
        _model = StateObject(wrappedValue: LivesModel(category: category.slug))
    }

    var body: some View {
        LivesList(lives: model.lives, model: model) { EmptyView() }
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

struct CategoriesView: View {
    @StateObject private var model = CategoriesModel()
    private let columns = [GridItem(.adaptive(minimum: 105), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                if let error = model.error, model.categories.isEmpty {
                    ErrorView(message: error) { Task { await model.reload() } }
                }
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(model.categories) { category in
                        NavigationLink(value: Route.category(category)) {
                            VStack(alignment: .leading, spacing: 4) {
                                Thumb(url: category.banner?.best)
                                    .aspectRatio(3 / 4, contentMode: .fit)
                                Text(category.name)
                                    .font(.caption.weight(.semibold))
                                    .lineLimit(2)
                                if let viewers = category.viewers {
                                    Text("\(Fmt.count(viewers)) spectateurs")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
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
            }
            .refreshable { await model.reload() }
            .navigationTitle("Catégories")
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
    @State private var results: [KSearchChannel] = []
    @State private var error: String?
    @State private var loading = false

    var body: some View {
        NavigationStack {
            List {
                if let error {
                    Text(error).foregroundStyle(.secondary)
                }
                ForEach(results) { channel in
                    NavigationLink(value: Route.channel(channel.slug)) {
                        HStack(spacing: 12) {
                            Avatar(url: channel.user?.avatar, size: 40)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(channel.user?.username ?? channel.slug)
                                    .font(.body.weight(.semibold))
                                if let followers = channel.followersCount {
                                    Text("\(Fmt.count(followers.value)) abonnés")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if channel.isLive == true { LiveBadge() }
                        }
                    }
                }
            }
            .listStyle(.plain)
            .overlay {
                if loading && results.isEmpty { ProgressView() }
            }
            .searchable(text: $query, prompt: "Chercher une chaîne")
            .navigationTitle("Recherche")
            .kickRoutes()
            .task(id: query) { await search() }
        }
    }

    private func search() async {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard text.count >= 2 else {
            results = []
            error = nil
            return
        }
        // Attente : une recherche par pause de frappe, pas une par lettre.
        try? await Task.sleep(nanoseconds: 400_000_000)
        guard !Task.isCancelled else { return }
        loading = true
        defer { loading = false }
        do {
            results = try await KickAPI.search(text).channels ?? []
            error = nil
        } catch {
            if !Task.isCancelled { self.error = KickAPI.message(error) }
        }
    }
}
