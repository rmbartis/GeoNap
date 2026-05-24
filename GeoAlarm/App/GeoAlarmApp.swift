// GeoAlarmApp.swift
// Entry point for the GeoAlarm iOS application.

internal import SwiftUI

@main
struct GeoAlarmApp: App {
    @StateObject private var locationManager = LocationManager()
    @StateObject private var alarmManager = AlarmManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(locationManager)
                .environmentObject(alarmManager)
                .onAppear {
                    alarmManager.locationManager = locationManager
                    locationManager.requestAlwaysAuthorization()
                    alarmManager.reregisterAllRegions()
                    alarmManager.requestNotificationPermission()
                }
        }
    }
}
