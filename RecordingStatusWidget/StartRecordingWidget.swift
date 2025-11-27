import WidgetKit
import SwiftUI
import AppIntents

// MARK: - App Intent for starting a recording
// This intent is duplicated here because widget extensions are separate targets
struct StartRecordingIntent: AppIntent {
    static let title: LocalizedStringResource = "Start New Recording"
    static let description = IntentDescription("Creates a new note and starts recording immediately.")
    static let openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        return .result()
    }
}

struct StartRecordingWidget: Widget {
    let kind: String = "StartRecordingWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            if #available(iOS 17.0, *) {
                StartRecordingWidgetEntryView(entry: entry)
                    .containerBackground(.fill.tertiary, for: .widget)
            } else {
                StartRecordingWidgetEntryView(entry: entry)
                    .padding()
                    .background()
            }
        }
        .configurationDisplayName("Start Recording")
        .description("Tap to start a new recording.")
        .supportedFamilies([.accessoryCircular])
    }
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(date: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> ()) {
        let entry = SimpleEntry(date: Date())
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SimpleEntry>) -> ()) {
        let entry = SimpleEntry(date: Date())
        let timeline = Timeline(entries: [entry], policy: .never)
        completion(timeline)
    }
}

struct SimpleEntry: TimelineEntry {
    let date: Date
}

struct StartRecordingWidgetEntryView: View {
    var entry: Provider.Entry

    var body: some View {
        Button(intent: StartRecordingIntent()) {
            Image(systemName: "mic.fill")
                .font(.system(size: 30))
                .foregroundColor(.white)
        }
        .buttonStyle(.plain)
    }
}

