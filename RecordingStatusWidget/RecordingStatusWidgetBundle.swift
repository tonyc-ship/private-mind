//
//  RecordingStatusWidgetBundle.swift
//  RecordingStatusWidget
//
//  Created by Tony Chong on 2025/7/7.
//

import WidgetKit
import SwiftUI

@main
struct RecordingStatusWidgetBundle: WidgetBundle {
    var body: some Widget {
        RecordingStatusWidget()
        RecordingStatusWidgetControl()
        RecordingStatusWidgetLiveActivity()
    }
}
