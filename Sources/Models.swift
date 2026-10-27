import Foundation

// Réponses de l'API de kick.com, lues avec `convertFromSnakeCase`
// (session_title → sessionTitle). Presque tout est facultatif : Kick omet
// des champs ou les met à null selon la réponse.

/// Entier que Kick donne parfois en texte (« 195953 »).
struct FlexInt: Codable, Hashable {
    let value: Int

    init(_ value: Int) { self.value = value }

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let i = try? c.decode(Int.self) {
            value = i
        } else if let s = try? c.decode(String.self), let i = Int(s) {
            value = i
        } else {
            value = 0
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(value)
    }
}

/// Image de Kick : `src` (miniatures), `url` ou `responsive` (bannières).
struct KImage: Codable, Hashable {
    let src: String?
    let url: String?
    let responsive: String?

    var best: URL? { [src, url, responsive].compactMap { $0 }.first.flatMap(URL.init(string:)) }
}

struct KCategory: Codable, Hashable, Identifiable {
    let id: Int
    let name: String
    let slug: String
    let viewers: Int?
    let banner: KImage?
}

/// Utilisateur derrière une chaîne : son image s'appelle `profilepic` (liste
/// des lives), `profile_pic` (chaîne) ou `profilePic` (recherche).
struct KUser: Codable, Hashable {
    let id: Int?
    let username: String?
    let profilepic: String?
    let profilePic: String?
    let bio: String?

    var avatar: URL? { (profilePic ?? profilepic).flatMap(URL.init(string:)) }
}

struct KChannelLite: Codable, Hashable {
    let id: Int
    let slug: String
    let user: KUser?
}

/// Un direct de la liste des lives (accueil, catégorie).
struct KLive: Codable, Hashable, Identifiable {
    let id: Int
    let sessionTitle: String?
    let viewerCount: Int?
    let startTime: String?
    let language: String?
    let thumbnail: KImage?
    let categories: [KCategory]?
    let channel: KChannelLite?
}

/// Page de résultats (lives, catégories).
struct KPage<Item: Decodable>: Decodable {
    let data: [Item]
    let nextPageUrl: String?
}

/// Direct en cours d'une chaîne (`livestream` de la chaîne).
struct KLiveStream: Codable, Hashable {
    let id: Int
    let sessionTitle: String?
    let viewerCount: Int?
    let startTime: String?
    let isLive: Bool?
    let categories: [KCategory]?
    let thumbnail: KImage?
}

struct KChatroom: Codable, Hashable {
    let id: Int
}

struct KChannel: Codable, Hashable {
    let id: Int
    let slug: String
    let playbackUrl: String?
    let followersCount: FlexInt?
    let user: KUser?
    let livestream: KLiveStream?
    let chatroom: KChatroom?
    let bannerImage: KImage?

    var name: String { user?.username ?? slug }
    var isLive: Bool { livestream?.isLive ?? (livestream != nil) }
}

struct KSearch: Codable {
    let channels: [KSearchChannel]?
}

struct KSearchChannel: Codable, Hashable, Identifiable {
    let id: Int
    let slug: String
    let isLive: Bool?
    let followersCount: FlexInt?
    let user: KUser?
}

/// VOD d'une chaîne : un ancien direct, avec `source` (playlist HLS).
struct KVod: Codable, Hashable, Identifiable {
    let id: Int
    let sessionTitle: String?
    let source: String?
    let duration: Int?          // millisecondes
    let startTime: String?
    let thumbnail: KImage?
    let categories: [KCategory]?
    let video: KVideoMeta?
}

struct KVideoMeta: Codable, Hashable {
    let uuid: String?
    let views: Int?
}

struct KClipsPage: Codable {
    let clips: [KClip]
    let nextCursor: String?
}

struct KClip: Codable, Hashable, Identifiable {
    let id: String
    let title: String?
    let videoUrl: String?
    let clipUrl: String?
    let thumbnailUrl: String?
    let duration: Int?          // secondes
    let views: Int?
    let createdAt: String?
    let channel: KClipChannel?
    let category: KCategory?
}

struct KClipChannel: Codable, Hashable {
    let slug: String?
    let username: String?
    let profilePicture: String?
}

struct KMessagesResponse: Codable {
    let data: KMessagesData?
}

struct KMessagesData: Codable {
    let messages: [KChatMessage]?
}

struct KChatMessage: Codable, Hashable, Identifiable {
    let id: String
    let content: String?
    let createdAt: String?
    let type: String?
    let sender: KSender?
}

struct KSender: Codable, Hashable {
    let id: Int?
    let username: String?
    let identity: KIdentity?
}

struct KIdentity: Codable, Hashable {
    let color: String?
}

/// Dates de Kick : « 2026-10-27 13:16:23 » (UTC) ou ISO 8601, avec ou sans
/// fractions de seconde.
enum KDate {
    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static let plain: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    static func parse(_ text: String?) -> Date? {
        guard let text, !text.isEmpty else { return nil }
        let trimmed = text.replacingOccurrences(of: #"\.\d+"#, with: "", options: .regularExpression)
        return iso.date(from: trimmed) ?? plain.date(from: trimmed)
    }
}
