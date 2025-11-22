//
//  RecordingStatusWidget.swift
//  RecordingStatusWidget
//
//  Created by Tony Chong on 2025/7/7.
//

import WidgetKit
import SwiftUI
import ActivityKit

struct RecordingStatusWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RecordingActivityAttributes.self) { context in
            // Lock screen UI
            HStack(spacing: 16) {
                Image("PrivateMindIcon", bundle: .main)
                    .renderingMode(.original)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                
                VStack(alignment: .leading) {
                    Text(context.attributes.meetingTitle)
                        .font(.headline)
                    HStack {
                        Image(systemName: "mic.fill")
                            .foregroundColor(.yellow)
                        
                        switch context.state.state {
                        case .recording(let startTime):
                            Text("Recording")
                            Spacer()
                            Text(startTime, style: .timer)
                        case .paused(let elapsedTime):
                            Text("Paused")
                            Spacer()
                            Text(Self.formatInterval(elapsedTime))
                        }
                    }
                    .font(.subheadline)
                }
            }
            .padding()
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "mic.fill")
                        .foregroundColor(.yellow)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    switch context.state.state {
                    case .recording(let startTime):
                        Text(startTime, style: .timer)
                    case .paused(let elapsedTime):
                        Text(Self.formatInterval(elapsedTime))
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                     Text(context.attributes.meetingTitle)
                        .font(.caption)
                        .lineLimit(1)
                }
            } compactLeading: {
                Image(systemName: "mic.fill")
                    .foregroundColor(.yellow)
            } compactTrailing: {
                switch context.state.state {
                case .recording(let startTime):
                    Text(startTime, style: .timer)
                        .monospacedDigit()
                        .frame(width: 40)
                case .paused(let elapsedTime):
                    Text(Self.formatInterval(elapsedTime))
                        .monospacedDigit()
                        .frame(width: 40)
                }
            } minimal: {
                Image(systemName: "mic.fill")
                    .foregroundColor(.yellow)
            }
        }
    }
    
    private static func formatInterval(_ interval: TimeInterval) -> String {
        let totalSeconds = Int(interval)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
