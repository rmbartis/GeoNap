// Copyright © 2026 Robert Bartis. All rights reserved.

// GeoAlarmActivityAttributes.swift
// ActivityAttributes for the Gold-tier Live Activity / Dynamic Island
// countdown. This is the copy used by the GeoAlarmLiveActivityExtension
// widget target, which renders the Activity — see
// GeoAlarmLiveActivityWidget.swift in this same folder.
//
// DELIBERATE DUPLICATE (2026-07-11): byte-identical to
// GeoAlarm/Models/GeoAlarmActivityAttributes.swift, used by the main
// GeoNap app target. This folder is an Xcode 16 synchronized group owned
// solely by the GeoAlarmLiveActivityExtension target, and the main app's
// GeoAlarm/Models folder is a separate synchronized group owned solely by
// GeoNap — getting one physical file to show up in both targets' File
// Inspector "Target Membership" list turned out not to work reliably
// through Xcode's UI for this project. Since ActivityAttributes data
// crosses a real process boundary (app process <-> extension process) via
// Codable serialization, two independently-compiled files with identical
// property definitions are functionally equivalent to one shared file at
// runtime — this sidesteps the cross-target membership issue entirely.
//
// If you change this struct, you MUST make the identical change to
// GeoAlarm/Models/GeoAlarmActivityAttributes.swift, or the app and the
// widget extension will silently fail to decode each other's data. See
// LIVE_ACTIVITY_SETUP.md for the full story.

import Foundation
import ActivityKit

struct GeoAlarmActivityAttributes: ActivityAttributes {

    public struct ContentState: Codable, Hashable {
        /// Meters remaining to the alarm's coordinate, when known. Populated
        /// for both trigger modes once a GPS fix is available — a
        /// time-trigger alarm still has a real physical distance, it just
        /// also has an ETA below.
        var distanceRemaining: Double?

        /// Seconds until estimated arrival. Only meaningful for
        /// triggerMode == .time — there's no ETA concept for a pure
        /// distance/geofence trigger (see AlarmManager's ETAEstimator,
        /// which only exists for time-mode alarms).
        var etaSeconds: Double?

        /// When this snapshot was computed. The widget uses this to show a
        /// relative "updated Xs ago" if fresh fixes stop arriving (weak
        /// signal, backgrounded too long) instead of silently going stale
        /// with no indication anything's wrong.
        var lastUpdated: Date
    }

    /// Alarm identity + fields the widget needs to render but that never
    /// change over the Activity's lifetime — ActivityAttributes' top-level
    /// properties are fixed at `Activity.request(attributes:...)` time, only
    /// `ContentState` updates afterward.
    var alarmID: String
    var alarmName: String
    /// TriggerMode.rawValue ("distance" / "time") — the widget uses this to
    /// decide whether to show a distance readout, an ETA countdown, or both.
    var triggerModeRaw: String
    /// RegionEvent.rawValue ("onEntry" / "onExit") — drives the widget's
    /// verb/icon ("arriving at" vs. "leaving").
    var regionEventRaw: String
}
