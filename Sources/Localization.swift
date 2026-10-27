import Foundation

/// Langue de l'app : celle de l'iPhone (anglais, ou français s'il est en
/// français), ou choisie dans les réglages.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system, en, fr
    var id: String { rawValue }
}

/// Réglages, gardés sur l'iPhone.
final class Settings: ObservableObject {
    static let shared = Settings()
    private let store = UserDefaults.standard

    @Published var language: AppLanguage { didSet { store.set(language.rawValue, forKey: "language") } }
    @Published var hideMature: Bool { didSet { store.set(hideMature, forKey: "hideMature") } }
    /// Hauteur d'image maximale (0 : automatique).
    @Published var maxQuality: Int { didSet { store.set(maxQuality, forKey: "maxQuality") } }
    @Published var resumeVods: Bool { didSet { store.set(resumeVods, forKey: "resumeVods") } }
    @Published var chatVisible: Bool { didSet { store.set(chatVisible, forKey: "chatVisible") } }
    @Published var chatTimestamps: Bool { didSet { store.set(chatTimestamps, forKey: "chatTimestamps") } }
    @Published var chatFontSize: Double { didSet { store.set(chatFontSize, forKey: "chatFontSize") } }
    @Published var liveAlerts: Bool { didSet { store.set(liveAlerts, forKey: "liveAlerts") } }
    /// Langue choisie dans l'accueil (nil : toutes).
    @Published var homeLanguage: String? { didSet { store.set(homeLanguage, forKey: "homeLanguage") } }

    init() {
        language = AppLanguage(rawValue: store.string(forKey: "language") ?? "") ?? .system
        hideMature = store.bool(forKey: "hideMature")
        maxQuality = store.integer(forKey: "maxQuality")
        resumeVods = store.object(forKey: "resumeVods") as? Bool ?? true
        chatVisible = store.object(forKey: "chatVisible") as? Bool ?? true
        chatTimestamps = store.bool(forKey: "chatTimestamps")
        chatFontSize = store.object(forKey: "chatFontSize") as? Double ?? 15
        liveAlerts = store.bool(forKey: "liveAlerts")
        homeLanguage = store.string(forKey: "homeLanguage")
    }

    var isFrench: Bool {
        switch language {
        case .fr: return true
        case .en: return false
        case .system: return Locale.preferredLanguages.first?.hasPrefix("fr") ?? false
        }
    }

    var locale: Locale { Locale(identifier: isFrench ? "fr_FR" : "en_US") }
}

/// Texte de l'interface : l'anglais (la clé), ou sa traduction française.
func L(_ key: String) -> String {
    Settings.shared.isFrench ? (French.strings[key] ?? key) : key
}

/// Texte avec des valeurs (%@, %d).
func L(_ key: String, _ args: CVarArg...) -> String {
    String(format: L(key), locale: Settings.shared.locale, arguments: args)
}

enum French {
    static let strings: [String: String] = [
        // Onglets et titres
        "Live": "Directs",
        "Browse": "Catégories",
        "Search": "Recherche",
        "Following": "Suivis",
        "Settings": "Réglages",
        "Multi-view": "Multi-live",
        // Accueil, listes
        "All": "Toutes",
        "Followed channels live": "Tes chaînes en direct",
        "Recently watched": "Vu récemment",
        "LIVE": "EN DIRECT",
        "%@ viewers": "%@ spectateurs",
        "%@ followers": "%@ abonnés",
        "%@ views": "%@ vues",
        "Retry": "Réessayer",
        "Search channels and categories": "Chercher une chaîne ou une catégorie",
        "Filter categories": "Filtrer les catégories",
        "Channels": "Chaînes",
        "Categories": "Catégories",
        "No results.": "Aucun résultat.",
        // Chaîne
        "VODs": "VODs",
        "Clips": "Clips",
        "About": "À propos",
        "No VODs.": "Aucune VOD.",
        "No clips.": "Aucun clip.",
        "Follow": "Suivre",
        "Unfollow": "Ne plus suivre",
        "Share": "Partager",
        "Open on kick.com": "Ouvrir sur kick.com",
        "Add to multi-view": "Ajouter au multi-live",
        "Remove from multi-view": "Retirer du multi-live",
        "Top · all time": "Populaires · toujours",
        "Top · this month": "Populaires · ce mois",
        "Top · this week": "Populaires · cette semaine",
        "Top · today": "Populaires · aujourd’hui",
        "Most recent": "Les plus récents",
        "Sort": "Trier",
        "Recent categories": "Catégories récentes",
        "No description.": "Pas de description.",
        "Offline": "Hors ligne",
        // Lecteur
        "This channel is not live.": "Cette chaîne n’est pas en direct.",
        "The stream has ended.": "Le direct est terminé.",
        "This VOD has no playable video.": "Cette VOD n’a pas de vidéo lisible.",
        "This clip has no playable video.": "Ce clip n’a pas de vidéo lisible.",
        "Live for %@": "En direct depuis %@",
        "Sleep timer": "Minuteur de veille",
        "Off": "Non",
        "%d min": "%d min",
        "Stops at %@": "Arrêt à %@",
        "Show chat": "Afficher le chat",
        "Hide chat": "Masquer le chat",
        "Resumed at %@": "Reprise à %@",
        "Start over": "Reprendre au début",
        // Chat
        "Latest messages": "Derniers messages",
        "Chat refreshes every 3 seconds.": "Le chat se relit toutes les 3 secondes.",
        // Suivis
        "No followed channels yet. Tap the heart on a channel page to see it here.": "Aucune chaîne suivie. Touche le cœur sur la page d’une chaîne pour la retrouver ici.",
        // Multi-live
        "Tap a stream to hear it.": "Touche un direct pour l’entendre.",
        "Close": "Fermer",
        "Clear": "Vider",
        // Réglages
        "Language": "Langue",
        "App language": "Langue de l’app",
        "System": "Système",
        "Playback": "Lecture",
        "Maximum quality": "Qualité maximale",
        "Auto": "Automatique",
        "Resume VODs where I left off": "Reprendre les VODs où je m’étais arrêté",
        "Chat": "Chat",
        "Timestamps": "Heure des messages",
        "Text size": "Taille du texte",
        "Hide 18+ streams": "Masquer les directs 18+",
        "Notifications": "Notifications",
        "Notify me when followed channels go live": "Me prévenir quand une chaîne suivie passe en direct",
        "Checked in the background when iOS allows it (about every 15 minutes or more).": "Vérifié en arrière-plan quand iOS le permet (environ toutes les 15 minutes ou plus).",
        "History": "Historique",
        "Clear watch history": "Effacer l’historique",
        "Version": "Version",
        "Source code": "Code source",
        "%@ is live": "%@ est en direct",
        // Erreurs
        "Kick refused the app's requests (error 403).": "Kick refuse les requêtes de l’app (erreur 403).",
        "Kick returned an error (%d).": "Kick a répondu par une erreur (%d).",
        "Kick's response could not be read.": "Réponse de Kick illisible.",
        "No internet connection.": "Pas de connexion Internet.",
        "Kick is not responding: %@": "Kick ne répond pas : %@",
        "Error.": "Erreur.",
    ]
}
