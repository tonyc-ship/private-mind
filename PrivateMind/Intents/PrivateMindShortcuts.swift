import AppIntents

struct PrivateMindShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartRecordingIntent(),
            phrases: [
                "Start recording in \(.applicationName)",
                "New note in \(.applicationName)",
                "Record audio in \(.applicationName)",
                "Record note in \(.applicationName)"
            ],
            shortTitle: "Start Recording",
            systemImageName: "mic.circle.fill"
        )
    }
}

