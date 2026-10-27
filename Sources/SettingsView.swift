import SwiftUI
import UserNotifications

struct SettingsView: View {
    @ObservedObject private var settings = Settings.shared
    @ObservedObject private var history = History.shared

    private var version: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        return "\(v) (\(b))"
    }

    /// Notifications : autorisation demandée en les activant.
    private var alerts: Binding<Bool> {
        Binding(
            get: { settings.liveAlerts },
            set: { on in
                guard on else {
                    settings.liveAlerts = false
                    return
                }
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
                    DispatchQueue.main.async {
                        settings.liveAlerts = granted
                        if granted {
                            LiveAlerts.schedule()
                            // Les directs déjà en cours ne sont pas annoncés.
                            Task { await LiveAlerts.check(notify: false) }
                        }
                    }
                }
            }
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(L("Language")) {
                    Picker(L("App language"), selection: $settings.language) {
                        Text(L("System")).tag(AppLanguage.system)
                        Text("English").tag(AppLanguage.en)
                        Text("Français").tag(AppLanguage.fr)
                    }
                }
                Section(L("Playback")) {
                    Picker(L("Maximum quality"), selection: $settings.maxQuality) {
                        Text(L("Auto")).tag(0)
                        Text("1080p").tag(1080)
                        Text("720p").tag(720)
                        Text("480p").tag(480)
                        Text("360p").tag(360)
                        Text("160p").tag(160)
                    }
                    Toggle(L("Resume VODs where I left off"), isOn: $settings.resumeVods)
                }
                Section(L("Chat")) {
                    Toggle(L("Show chat"), isOn: $settings.chatVisible)
                    Toggle(L("Timestamps"), isOn: $settings.chatTimestamps)
                    Stepper(value: $settings.chatFontSize, in: 11...22, step: 1) {
                        Text("\(L("Text size")) · \(Int(settings.chatFontSize))")
                    }
                }
                Section(L("Browse")) {
                    Toggle(L("Hide 18+ streams"), isOn: $settings.hideMature)
                }
                Section {
                    Toggle(L("Notify me when followed channels go live"), isOn: alerts)
                } header: {
                    Text(L("Notifications"))
                } footer: {
                    Text(L("Checked in the background when iOS allows it (about every 15 minutes or more)."))
                }
                Section(L("History")) {
                    Button(L("Clear watch history"), role: .destructive) {
                        history.clear()
                        VodProgress.clear()
                    }
                }
                Section(L("About")) {
                    HStack {
                        Text(L("Version"))
                        Spacer()
                        Text(version).foregroundStyle(.secondary)
                    }
                    if let url = URL(string: "https://github.com/MXFia19/KickUnblock") {
                        Link(L("Source code"), destination: url)
                    }
                }
            }
            .navigationTitle(L("Settings"))
        }
    }
}
