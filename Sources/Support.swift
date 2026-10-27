import SwiftUI

enum Theme {
    static let accent = Color(red: 0.18, green: 0.84, blue: 0.40)
    static let live = Color(red: 0.92, green: 0.16, blue: 0.20)
}

extension Color {
    /// « #RRGGBB » → couleur ; nil sinon.
    init?(hex: String?) {
        guard var s = hex?.trimmingCharacters(in: .whitespaces), !s.isEmpty else { return nil }
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(red: Double((v >> 16) & 0xff) / 255, green: Double((v >> 8) & 0xff) / 255, blue: Double(v & 0xff) / 255)
    }
}

enum Fmt {
    /// 1 234 → « 1.2K » (anglais) ou « 1,2 k » (français).
    static func count(_ n: Int?) -> String {
        guard let n else { return "" }
        let french = Settings.shared.isFrench
        let text: String
        if n >= 1_000_000 {
            text = String(format: "%.1f", Double(n) / 1_000_000) + (french ? " M" : "M")
        } else if n >= 10_000 {
            text = String(format: "%.0f", Double(n) / 1_000) + (french ? " k" : "K")
        } else if n >= 1_000 {
            text = String(format: "%.1f", Double(n) / 1_000) + (french ? " k" : "K")
        } else {
            text = "\(n)"
        }
        return french ? text.replacingOccurrences(of: ".", with: ",") : text
    }

    static func clock(_ seconds: Int) -> String {
        let h = seconds / 3600, m = (seconds % 3600) / 60, s = seconds % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    static func relative(_ date: Date?) -> String {
        guard let date else { return "" }
        let f = RelativeDateTimeFormatter()
        f.locale = Settings.shared.locale
        f.unitsStyle = .short
        return f.localizedString(for: date, relativeTo: Date())
    }

    static func time(_ date: Date?) -> String {
        guard let date else { return "" }
        let f = DateFormatter()
        f.locale = Settings.shared.locale
        f.timeStyle = .short
        return f.string(from: date)
    }
}

// MARK: - Petits éléments communs

struct Thumb: View {
    let url: URL?

    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.06))
            .overlay {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        Color.clear
                    }
                }
            }
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

struct Avatar: View {
    let url: URL?
    var size: CGFloat = 36

    var body: some View {
        AsyncImage(url: url) { phase in
            if let image = phase.image {
                image.resizable().scaledToFill()
            } else {
                Circle().fill(Color.white.opacity(0.1))
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}

struct LiveBadge: View {
    var body: some View {
        Text(L("LIVE"))
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Theme.live, in: RoundedRectangle(cornerRadius: 4))
            .foregroundColor(.white)
    }
}

struct ErrorView: View {
    let message: String
    var retry: (() -> Void)?

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(message)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            if let retry {
                Button(L("Retry"), action: retry).buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

/// Titre d'une rangée de l'accueil.
struct SectionTitle: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.headline)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Mise en page « au fil du texte » : mots et emotes du chat.
struct FlowLayout: Layout {
    var spacing: CGFloat = 4
    var lineSpacing: CGFloat = 2

    private func size(of view: LayoutSubview, maxWidth: CGFloat) -> CGSize {
        let s = view.sizeThatFits(.unspecified)
        return s.width > maxWidth ? view.sizeThatFits(ProposedViewSize(width: maxWidth, height: nil)) : s
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, line: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let s = size(of: view, maxWidth: maxWidth)
            if x > 0 && x + s.width > maxWidth {
                y += line + lineSpacing
                x = 0
                line = 0
            }
            x += s.width + spacing
            line = max(line, s.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: min(widest, maxWidth), height: y + line)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, line: CGFloat = 0
        for view in subviews {
            let s = size(of: view, maxWidth: bounds.width)
            if x > bounds.minX && x + s.width > bounds.maxX {
                y += line + lineSpacing
                x = bounds.minX
                line = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            line = max(line, s.height)
        }
    }
}

/// Lien d'un réseau social de la page « À propos » (pseudo ou adresse).
enum Social {
    static func url(_ kind: String, _ value: String?) -> URL? {
        guard let raw = value?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return nil }
        if raw.lowercased().hasPrefix("http") { return URL(string: raw) }
        let handle = raw.hasPrefix("@") ? String(raw.dropFirst()) : raw
        let encoded = handle.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? handle
        switch kind {
        case "twitter": return URL(string: "https://x.com/\(encoded)")
        case "instagram": return URL(string: "https://instagram.com/\(encoded)")
        case "youtube": return URL(string: "https://www.youtube.com/@\(encoded)")
        case "tiktok": return URL(string: "https://www.tiktok.com/@\(encoded)")
        case "discord": return URL(string: "https://discord.gg/\(encoded)")
        case "facebook": return URL(string: "https://facebook.com/\(encoded)")
        default: return nil
        }
    }
}
