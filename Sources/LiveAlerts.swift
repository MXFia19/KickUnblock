import BackgroundTasks
import Foundation
import UserNotifications

/// Notifications des chaînes suivies qui passent en direct : vérifiées en
/// arrière-plan quand iOS le permet (BGAppRefreshTask, environ toutes les
/// 15 minutes ou plus), une notification par nouveau direct.
enum LiveAlerts {
    static let taskId = "com.mxfia19.KickUnblock.refresh"
    private static let knownKey = "liveAlertsKnown"

    /// À faire au lancement de l'app (avant la fin du démarrage).
    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskId, using: nil) { task in
            guard let refresh = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            schedule()
            let work = Task {
                await check(notify: true)
                refresh.setTaskCompleted(success: true)
            }
            refresh.expirationHandler = { work.cancel() }
        }
    }

    static func schedule() {
        guard UserDefaults.standard.bool(forKey: "liveAlerts") else { return }
        let request = BGAppRefreshTaskRequest(identifier: taskId)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    /// Chaînes suivies en direct ; `notify` : annonce celles qui ne l'étaient
    /// pas à la vérification précédente.
    static func check(notify: Bool) async {
        let slugs = UserDefaults.standard.stringArray(forKey: Follows.key) ?? []
        var live: [String: (name: String, title: String)] = [:]
        for slug in slugs.prefix(40) {
            if Task.isCancelled { return }
            if let channel = try? await KickAPI.channel(slug), channel.isLive {
                live[slug] = (channel.name, channel.livestream?.sessionTitle ?? "")
            }
        }
        let known = Set(UserDefaults.standard.stringArray(forKey: knownKey) ?? [])
        if notify {
            for (slug, info) in live where !known.contains(slug) {
                let content = UNMutableNotificationContent()
                content.title = L("%@ is live", info.name)
                content.body = info.title
                content.sound = .default
                content.userInfo = ["slug": slug]
                let request = UNNotificationRequest(identifier: "live-\(slug)", content: content, trigger: nil)
                try? await UNUserNotificationCenter.current().add(request)
            }
        }
        UserDefaults.standard.set(Array(live.keys), forKey: knownKey)
    }
}
