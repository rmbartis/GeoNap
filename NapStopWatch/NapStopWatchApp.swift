// NapStopWatchApp.swift
// Entry point for the NapAlarmWatch watchOS target.

import SwiftUI

@main
struct NapStopWatchApp: App {
    @StateObject private var alarmStore = WatchAlarmStore.shared

    var body: some Scene {
        WindowGroup {
            NearestAlarmView()
                .environmentObject(alarmStore)
        }
    }
}
