// GeoAlarmApp.swift
// Entry point. Wires SwiftData ModelContainer, LocationManager, and AlarmManager.

import SwiftUI
import SwiftData
import FirebaseCore

@main
struct GeoAlarmApp: App {
    @StateObject private var locationManager = LocationManager()
    @StateObject private var alarmManager = AlarmManager()
    @StateObject private var languageManager = LanguageManager.shared

    /// CloudKit-backed container with a local-only fallback.
    /// Falls back silently if the user is not signed into iCloud or if the
    /// CloudKit entitlement is missing (e.g. simulator without a paid account).
    private let container: ModelContainer = {
        let schema = Schema([GeoAlarm.self, GTFSFeedModel.self])
        let cloudConfig = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .automatic
        )
        if let c = try? ModelContainer(for: schema, configurations: [cloudConfig]) {
            return c
        }
        // Fallback: local storage only
        let localConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        return try! ModelContainer(for: schema, configurations: [localConfig])
    }()

    init() {
        FirebaseApp.configure()
        CrashReporter.log("App launched")
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(locationManager)
                .environmentObject(alarmManager)
                .environmentObject(languageManager)
                // Pass the selected .lproj bundle so every Text("key", bundle: bundle)
                // call — and LText("key") — resolves strings in the chosen language.
                .environment(\.languageBundle, languageManager.currentBundle)
                // Rebuild the entire view tree when language changes so all
                // Text views re-evaluate with the new bundle.
                .id(languageManager.currentLanguage)
        }
        .modelContainer(container)
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
