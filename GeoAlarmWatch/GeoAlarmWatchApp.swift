// GeoAlarmWatchApp.swift
// Entry point for the GeoAlarmWatch watchOS target.

import SwiftUI

@main
struct GeoAlarmWatchApp: App {
    @StateObject private var alarmStore = WatchAlarmStore.shared

    var body: some Scene {
        WindowGroup {
            NearestAlarmView()
                .environmentObject(alarmStore)
        }
    }
}
