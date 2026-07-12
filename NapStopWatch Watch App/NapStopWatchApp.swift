// Copyright © 2026 Robert Bartis. All rights reserved.

// NapStopWatchApp.swift
// Entry point for the watchOS app (real Xcode target name: "NapStopWatch
// Watch App" — see this folder's WATCH_SETUP.md for why the folder is
// named with a space, unlike the rest of this project's synchronized
// groups).

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
