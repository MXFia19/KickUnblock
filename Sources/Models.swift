import Foundation

// Réponses de l'API de kick.com, lues avec `convertFromSnakeCase`
// (session_title → sessionTitle). Presque tout est facultatif : Kick omet
// des champs ou les met à null selon la réponse. Les listes sont lues
// élément par élément : un élément d'une forme inattendue est écarté au lieu
// de faire échouer toute la réponse.

/// Liste dont les éléments illisibles sont écartés.
struct LossyArray<Element: Decodable & Hashable>: Decodable, Hashable {
    let items: [Element]

    private struct Skip: Decodable {
        init(from decoder: Decoder) throws {}
    }

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var out: [Element] = []
        while !container.isAtEnd {
            if let element = try? container.decode(Element.self) {
                out.append(element)
            } else {
                _ = try? container.decode(Skip.self)
            }
        }
        items = out
    }
}

/// Entier que Kick donne parfois en texte (« 195953 »).
struct FlexInt: Decodable, Hashable {
    let value: Int

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
}

/// Image de Kick : `src` (miniatures), `url` ou `responsive` (bannières).
struct KImage: Decodable, Hashable {
    let src: String?
    let url: String?
    let responsive: String?

    var best: URL? { [src, url, responsive].compactMap { $0 }.first.flatMap(URL.init(string:)) }
}

struct KCategory: Decodable, Hashable, Identifiable {
    let id: Int
    let name: String
    let slug: String
    let viewers: Int?
    let banner: KImage?
}

/// Utilisateur derrière une chaîne : son image s'appelle `profilepic` (liste
/// des lives), `profile_pic` (chaîne) ou `profilePic` (recherche).
struct KUser: Decodable, Hashable {
    let id: Int?
    let username: String?
    let profilepic: String?
    let profilePic: String?
    let bio: String?
    let twitter: String?
    let instagram: String?
    let youtube: String?
    let tiktok: String?
    let discord: String?
    let facebook: String?

    var avatarString: String? { profilePic ?? profilepic }
    var avatar: URL? { avatarString.flatMap(URL.init(string:)) }
}

struct KChannelLite: Decodable, Hashable {
    let id: Int
    let slug: String
    let user: KUser?
}

/// Un direct de la liste des lives (accueil, catégorie).
struct KLive: Decodable, Hashable, Identifiable {
    let id: Int
    let sessionTitle: String?
    let viewerCount: Int?
    let startTime: String?
    let language: String?
    let isMature: Bool?
    let thumbnail: KImage?
    let categories: [KCategory]?
    let channel: KChannelLite?
}

/// Page de résultats (lives, catégories).
struct KPage<Item: Decodable & Hashable>: Decodable {
    let data: [Item]
    let nextPageUrl: String?

    enum CodingKeys: String, CodingKey {
        case data, nextPageUrl
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        data = try c.decode(LossyArray<Item>.self, forKey: .data).items
        nextPageUrl = try? c.decode(String.self, forKey: .nextPageUrl)
    }
}

/// Direct en cours d'une chaîne (`livestream` de la chaîne).
struct KLiveStream: Decodable, Hashable {
    let id: Int
    let sessionTitle: String?
    let viewerCount: Int?
    let startTime: String?
    let isLive: Bool?
    let isMature: Bool?
    let categories: [KCategory]?
    let thumbnail: KImage?
}

struct KChatroom: Decodable, Hashable {
    let id: Int
}

struct KChannel: Decodable, Hashable {
    let id: Int
    let slug: String
    let playbackUrl: String?
    let followersCount: FlexInt?
    let user: KUser?
    let livestream: KLiveStream?
    let chatroom: KChatroom?
    let bannerImage: KImage?
    let recentCategories: LossyArray<KCategory>?

    var name: String { user?.username ?? slug }
    var isLive: Bool { livestream?.isLive ?? (livestream != nil) }
    var ref: ChannelRef { ChannelRef(slug: slug, name: name, avatar: user?.avatarString) }
}

struct KSearch: Decodable {
    let channels: [KSearchChannel]
    let categories: [KCategory]

    enum CodingKeys: String, CodingKey {
        case channels, categories
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        channels = (try? c.decode(LossyArray<KSearchChannel>.self, forKey: .channels))?.items ?? []
        categories = (try? c.decode(LossyArray<KCategory>.self, forKey: .categories))?.items ?? []
    }
}

struct KSearchChannel: Decodable, Hashable, Identifiable {
    let id: Int
    let slug: String
    let isLive: Bool?
    let followersCount: FlexInt?
    let user: KUser?
}

/// VOD d'une chaîne : un ancien direct, avec `source` (playlist HLS).
struct KVod: Decodable, Hashable, Identifiable {
    let id: Int
    let sessionTitle: String?
    let source: String?
    let duration: Int?          // millisecondes
    let startTime: String?
    let thumbnail: KImage?
    let categories: [KCategory]?
    let video: KVideoMeta?
}

struct KVideoMeta: Decodable, Hashable {
    let uuid: String?
    let views: Int?
}

struct KClipsPage: Decodable {
    let clips: [KClip]
    let nextCursor: String?

    enum CodingKeys: String, CodingKey {
        case clips, nextCursor
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        clips = (try? c.decode(LossyArray<KClip>.self, forKey: .clips))?.items ?? []
        nextCursor = try? c.decode(String.self, forKey: .nextCursor)
    }
}

struct KClip: Decodable, Hashable, Identifiable {
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

struct KClipChannel: Decodable, Hashable {
    let slug: String?
    let username: String?
    let profilePicture: String?
}

struct KMessagesResponse: Decodable {
    let data: KMessagesData?
}

struct KMessagesData: Decodable {
    let messages: [KChatMessage]

    enum CodingKeys: String, CodingKey {
        case messages
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        messages = (try? c.decode(LossyArray<KChatMessage>.self, forKey: .messages))?.items ?? []
    }
}

struct KChatMessage: Decodable, Hashable, Identifiable {
    let id: String
    let content: String?
    let createdAt: String?
    let type: String?
    let metadata: String?
    let sender: KSender?
}

/// Message auquel un message répond (`metadata`, texte JSON).
struct KReply: Hashable {
    let username: String
    let content: String
}

extension KChatMessage {
    var reply: KReply? {
        guard type == "reply", let data = metadata?.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sender = json["original_sender"] as? [String: Any],
              let original = json["original_message"] as? [String: Any] else { return nil }
        return KReply(username: sender["username"] as? String ?? "?", content: original["content"] as? String ?? "")
    }
}

struct KSender: Decodable, Hashable {
    let id: Int?
    let username: String?
    let identity: KIdentity?
}

struct KIdentity: Decodable, Hashable {
    let color: String?
    let badges: [KBadge]

    enum CodingKeys: String, CodingKey {
        case color, badges
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        color = try? c.decode(String.self, forKey: .color)
        badges = (try? c.decode(LossyArray<KBadge>.self, forKey: .badges))?.items ?? []
    }
}

struct KBadge: Decodable, Hashable {
    let type: String?
    let text: String?
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
