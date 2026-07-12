//
//  GeoAlarmLiveActivityBundle.swift
//  GeoAlarmLiveActivity
//
//  Created by bartis on 7/11/26.
//

import WidgetKit
import SwiftUI

// The plain widget, Control widget, and placeholder Live Activity stubs
// Xcode's wizard generates alongside this bundle have been emptied out
// (see GeoAlarmLiveActivity.swift / GeoAlarmLiveActivityControl.swift /
// GeoAlarmLiveActivityLiveActivity.swift) — this extension only ships the
// real Live Activity implementation, GeoAlarmLiveActivityWidget.

@main
struct GeoAlarmLiveActivityBundle: WidgetBundle {
    var body: some Widget {
        GeoAlarmLiveActivityWidget()
    }
}
