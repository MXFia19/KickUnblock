import Foundation

enum KickError: LocalizedError {
    case refused
    case http(Int)
    case decoding

    var errorDescription: String? {
        switch self {
        case .refused: return "Kick refuse les requêtes de l'app (erreur 403)."
        case .http(let code): return "Kick a répondu par une erreur (\(code))."
        case .decoding: return "Réponse de Kick illisible."
        }
    }
}

/// API de kick.com, lue comme le fait son site : requêtes simples de l'app
/// (URLSession et son User-Agent), sans imiter un navigateur ni l'app Kick.
enum KickAPI {
    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    /// Morceau d'adresse sûr (pseudo d'une chaîne).
    private static func segment(_ text: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-_.")
        return text.lowercased().addingPercentEncoding(withAllowedCharacters: allowed) ?? text
    }

    static func get<T: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> T {
        guard var comps = URLComponents(string: "https://kick.com" + path) else { throw KickError.http(0) }
        if !query.isEmpty { comps.queryItems = query }
        guard let url = comps.url else { throw KickError.http(0) }
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        if code == 403 { throw KickError.refused }
        guard (200..<300).contains(code) else { throw KickError.http(code) }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw KickError.decoding
        }
    }

    /// Directs les plus regardés (toutes langues), ou ceux d'une catégorie.
    static func lives(page: Int, category: String?) async throws -> KPage<KLive> {
        var query = [
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "limit", value: "24"),
            URLQueryItem(name: "sort", value: "desc"),
        ]
        if let category { query.append(URLQueryItem(name: "subcategory", value: category)) }
        return try await get("/stream/livestreams/fr", query: query)
    }

    static func channel(_ slug: String) async throws -> KChannel {
        try await get("/api/v2/channels/\(segment(slug))")
    }

    static func vods(_ slug: String) async throws -> [KVod] {
        try await get("/api/v2/channels/\(segment(slug))/videos")
    }

    static func clips(_ slug: String, cursor: String?) async throws -> KClipsPage {
        var query = [URLQueryItem(name: "sort", value: "view"), URLQueryItem(name: "time", value: "all")]
        if let cursor { query.append(URLQueryItem(name: "cursor", value: cursor)) }
        return try await get("/api/v2/channels/\(segment(slug))/clips", query: query)
    }

    static func search(_ text: String) async throws -> KSearch {
        try await get("/api/search", query: [URLQueryItem(name: "searched_word", value: text)])
    }

    static func categories(page: Int) async throws -> KPage<KCategory> {
        try await get("/api/v1/subcategories", query: [
            URLQueryItem(name: "limit", value: "32"),
            URLQueryItem(name: "page", value: String(page)),
        ])
    }

    /// Derniers messages du chat d'une chaîne (id de la chaîne).
    static func messages(channelId: Int) async throws -> [KChatMessage] {
        let response: KMessagesResponse = try await get("/api/v2/channels/\(channelId)/messages")
        return response.data?.messages ?? []
    }

    /// Phrase pour l'utilisateur.
    static func message(_ error: Error) -> String {
        if let e = error as? KickError { return e.errorDescription ?? "Erreur." }
        if let e = error as? URLError, e.code == .notConnectedToInternet { return "Pas de connexion Internet." }
        return "Kick ne répond pas : \(error.localizedDescription)"
    }
}
