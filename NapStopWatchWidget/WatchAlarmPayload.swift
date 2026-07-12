// Copyright © 2026 Robert Bartis. All rights reserved.

// WatchAlarmPayload.swift
// Lightweight Codable model transferred between the iOS app and the Watch
// targets via WCSession applicationContext. This is the copy used by the
// NapStopWatchWidget (watchOS complication) target.
//
// DELIBERATE DUPLICATE (2026-07-11): byte-identical to
// GeoAlarm/Models/WatchAlarmPayload.swift (main iOS target) and
// NapStopWatch/WatchAlarmPayload.swift (Watch app target). See the header
// comment on the iOS copy for why — same reasoning as
// GeoAlarmActivityAttributes.swift's duplication for the Live Activity
// extension (GeoAlarmLiveActivity/LIVE_ACTIVITY_SETUP.md). If you change
// this struct, change all three copies.

import Foundation

struct WatchAlarmPayload: Codable, Identifiable {
    let id: String          // UUID string
    let name: String
    let regionEvent: String // RegionEvent.rawValue
    let radius: Double      // metres
    let state: String       // AlarmState.rawValue
    let triggerCount: Int
}
