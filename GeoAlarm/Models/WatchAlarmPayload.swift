// Copyright © 2026 Robert Bartis. All rights reserved.

// WatchAlarmPayload.swift
// Lightweight Codable model transferred between the iOS app and the Watch
// targets via WCSession applicationContext. This is the copy used by the
// main GeoNap (iOS) target.
//
// NOTE (2026-07-11): there are DELIBERATE duplicates of this exact struct
// at NapStopWatch/WatchAlarmPayload.swift and
// NapStopWatchWidget/WatchAlarmPayload.swift, one per Watch target. This
// mirrors the fix applied to GeoAlarmActivityAttributes.swift for the Live
// Activity extension (see GeoAlarmLiveActivity/LIVE_ACTIVITY_SETUP.md) —
// getting one physical file to show up in multiple targets' File Inspector
// "Target Membership" list proved unreliable through Xcode's UI for this
// project's Xcode-16-synchronized-group folders. WatchAlarmPayload data
// already crosses a real process boundary via WCSession/Codable, so three
// independently-compiled identical struct definitions are functionally
// equivalent to one shared file. If you change this struct, change all
// three copies. See NapStopWatch/WATCH_SETUP.md.

import Foundation

struct WatchAlarmPayload: Codable, Identifiable {
    let id: String          // UUID string
    let name: String
    let regionEvent: String // RegionEvent.rawValue
    let radius: Double      // metres
    let state: String       // AlarmState.rawValue
    let triggerCount: Int
}
