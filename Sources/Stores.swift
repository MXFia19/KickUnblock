import Foundation

/// Chaîne retenue (historique, VOD) : pseudo, nom, image.
struct ChannelRef: Codable, Hashable {
    let slug: String
    let name: String
    let avatar: String?

    var avatarURL: URL? { avatar.flatMap(URL.init(string:)) }
}

/// Chaînes suivies, gardées sur l'iPhone (pseudos en minuscules).
final class Follows: ObservableObject {
    static let shared = Follows()
    static let key = "follows"
    @Published private(set) var slugs: [String]

    init() {
        slugs = UserDefaults.standard.stringArray(forKey: Follows.key) ?? []
    }

    func isFollowed(_ slug: String) -> Bool { slugs.contains(slug.lowercased()) }

    func toggle(_ slug: String) {
        let s = slug.lowercased()
        if let i = slugs.firstIndex(of: s) { slugs.remove(at: i) } else { slugs.insert(s, at: 0) }
        UserDefaults.standard.set(slugs, forKey: Follows.key)
    }
}

/// Chaînes regardées récemment (20 au plus).
final class History: ObservableObject {
    static let shared = History()
    private let key = "history"
    @Published private(set) var channels: [ChannelRef]

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let list = try? JSONDecoder().decode([ChannelRef].self, from: data) {
            channels = list
        } else {
            channels = []
        }
    }

    func add(_ ref: ChannelRef) {
        channels.removeAll { $0.slug == ref.slug }
        channels.insert(ref, at: 0)
        if channels.count > 20 { channels.removeLast(channels.count - 20) }
        save()
    }

    func clear() {
        channels = []
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(channels) { UserDefaults.standard.set(data, forKey: key) }
    }
}

/// Où chaque VOD s'est arrêtée (secondes), 200 gardées.
enum VodProgress {
    private static let key = "vodProgress"

    static func get(_ id: Int) -> Double? {
        UserDefaults.standard.dictionary(forKey: key)?[String(id)] as? Double
    }

    static func set(_ id: Int, _ seconds: Double) {
        var all = UserDefaults.standard.dictionary(forKey: key) ?? [:]
        all[String(id)] = seconds
        if all.count > 200, let first = all.keys.first { all.removeValue(forKey: first) }
        UserDefaults.standard.set(all, forKey: key)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

/// Directs choisis pour le multi-live (4 au plus).
final class MultiView: ObservableObject {
    static let shared = MultiView()
    static let limit = 4
    @Published private(set) var slugs: [String] = []

    func contains(_ slug: String) -> Bool { slugs.contains(slug.lowercased()) }

    /// Ajoute ou retire ; false si le multi-live est déjà plein.
    @discardableResult
    func toggle(_ slug: String) -> Bool {
        let s = slug.lowercased()
        if let i = slugs.firstIndex(of: s) {
            slugs.remove(at: i)
            return true
        }
        guard slugs.count < MultiView.limit else { return false }
        slugs.append(s)
        return true
    }

    func clear() { slugs = [] }
}
