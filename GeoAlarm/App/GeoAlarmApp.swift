// GeoAlarmApp.swift
// Entry point. Wires SwiftData ModelContainer, LocationManager, and AlarmManager.

import SwiftUI
import SwiftData

@main
struct GeoAlarmApp: App {
    @StateObject private var locationManager = LocationManager()
    @StateObject private var alarmManager = AlarmManager()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(locationManager)
                .environmentObject(alarmManager)
        }
        .modelContainer(for: GeoAlarm.self)
    }
}

/// Thin wrapper that passes the SwiftData ModelContext to AlarmManager
/// on first appear, then hands off to ContentView.
struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var locationManager: LocationManager
    @EnvironmentObject var alarmManager: AlarmManager

    var body: some View {
        ContentView()
            .onAppear {
                alarmManager.setModelContext(modelContext)
                alarmManager.locationManager = locationManager
                locationManager.requestAlwaysAuthorization()
                alarmManager.reregisterAllRegions()
                alarmManager.requestNotificationPermission()
            }
    }
}
