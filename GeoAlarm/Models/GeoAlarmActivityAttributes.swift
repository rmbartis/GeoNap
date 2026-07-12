// Copyright © 2026 Robert Bartis. All rights reserved.

// GeoAlarmActivityAttributes.swift
// ActivityAttributes for the Gold-tier Live Activity / Dynamic Island
// countdown (see monetization-tier-pricing memory — previously listed as
// "not yet built"). This is the copy used by the main GeoNap app target,
// which starts/updates/ends the Activity — see LiveActivityManager.swift.
//
// NOTE (2026-07-11): there is a DELIBERATE duplicate of this exact struct
// at GeoAlarmLiveActivity/GeoAlarmActivityAttributes.swift, used by the
// widget extension target. Originally this was meant to be a single shared
// file added to both targets' membership, but the GeoAlarm folder's Xcode
// 16 synchronized-group ownership made that cross-target checkbox
// unreliable to complete via Xcode's UI in practice. ActivityAttributes
// data crosses a real process boundary (app process <-> extension
// process) via Codable serialization regardless of whether both sides
// share one file or declare identical types independently — so two
// source files with byte-identical property definitions are 100%
// equivalent at runtime to one shared file. If you change this struct,
// you MUST make the identical change to the other copy, or the two
// processes will silently fail to decode each other's data. See
// GeoAlarmLiveActivity/LIVE_ACTIVITY_SETUP.md for the full story.
//
// What this is for: AlarmKit's own built-in Live Activity (the system alert
// banner — see the "stale Live Activity" bug notes in NapStopApp.swift /
// GeoAlarmScheduler.swift) only appears once an alarm actually FIRES, and
// has no concept of GPS progress — it's a generic countdown/alert UI. This
// Activity is visible the WHOLE TIME an alarm is armed and tracking,
// showing live distance-remaining and/or an ETA countdown, which is
// specifically the part AlarmKit doesn't do.

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
