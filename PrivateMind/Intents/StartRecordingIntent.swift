import AppIntents
import SwiftUI

struct StartRecordingIntent: AppIntent {
    static let title: LocalizedStringResource = "Start New Recording"
    static let description = IntentDescription("Creates a new note and starts recording immediately.")
    static let openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        NavigationManager.shared.shouldStartNewNote = true
        return .result()
    }
}

