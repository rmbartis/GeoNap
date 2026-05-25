// WatchAlarmPayload.swift
// Lightweight Codable model transferred between the iOS app and the Watch
// targets via WCSession applicationContext.
//
// ⚠️ Add this file to THREE targets in Xcode:
//    • GeoAlarm (iOS)
//    • GeoAlarmWatch (watchOS app)
//    • GeoAlarmWatchWidget (watchOS complication extension)

import Foundation

struct WatchAlarmPayload: Codable, Identifiable {
    let id: String          // UUID string
    let name: String
    let regionEvent: String // RegionEvent.rawValue
    let radius: Double      // metres
    let state: String       // AlarmState.rawValue
    let triggerCount: Int
}
