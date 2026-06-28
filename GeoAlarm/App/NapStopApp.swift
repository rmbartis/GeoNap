// NapStopApp.swift
// Entry point. Wires SwiftData ModelContainer, LocationManager, and AlarmManager.

import SwiftUI
import SwiftData
import CoreSpotlight

@main
struct NapStopApp: App {
    @StateObject private var locationManager = LocationManager()
    @StateObject private var alarmManager = AlarmManager()
    @StateObject private var languageManager = LanguageManager.shared

    /// CloudKit-backed container with a local-only fallback.
    /// Falls back silently if the user is not signed into iCloud or if the
    /// CloudKit entitlement is missing (e.g. simulator without a paid account).
    private let container: ModelContainer = {
        let schema = Schema([NapAlarm.self, GTFSFeedModel.self])
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
        CrashReporter.log("App launched")
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(locationManager)
                .environmentObject(alarmManager)
                .environmentObject(languageManager)
                // Pass the selected .lproj bundle so every Text("key", bundle: bundle)
                // call resolves strings in the chosen language.
                .environment(\.languageBundle, languageManager.currentBundle)
                // REQUIRED on iOS 26: changing only the environment bundle does not
                // re-resolve already-rendered Text(_:bundle:) views, so the visible
                // language wouldn't change until relaunch. Re-id'ing the view tree on
                // language change forces a full rebuild so every string re-resolves.
                .id(languageManager.currentLanguage)
        }
        .modelContainer(container)
    }
}

/// Thin wrapper that passes the SwiftData ModelContext to AlarmManager
/// on first appear, then hands off to ContentView.
struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject var locationManager: LocationManager
    @EnvironmentObject var alarmManager: AlarmManager

    var body: some View {
        ContentView()
            .onAppear {
                // Stamp a fresh session header (with the current build) at launch so
                // every run in the debug log is tied to the build it ran on.
                DebugLogger.shared.beginSessionIfEnabled()
                // Copy bundled WAV sounds into Library/Sounds so UNNotificationSound(named:)
                // can find them. Must run before any alarm can fire.
                NotificationSound.installBundledSoundsIfNeeded()
                alarmManager.setModelContext(modelContext)
                alarmManager.locationManager = locationManager
                locationManager.requestAlwaysAuthorization()
                alarmManager.reregisterAllRegions()
                // AlarmKit (iOS 26+): prompt for alarm permission so a geofence
                // fire can present a system alarm. Lazily re-checked before each
                // fire, but requesting at launch surfaces the prompt early.
                Task { await GeoAlarmScheduler.ensureAuthorized() }
            }
            // When the app returns to the foreground, clean up any windowed alarms
            // whose active window ended while the app was suspended/terminated
            // (the in-memory window-end timer can't run in that state).
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    alarmManager.deactivateExpiredWindowAlarms()
                }
            }
            // Handle Spotlight search result taps — route to the matching alarm.
            .onContinueUserActivity(CSSearchableItemActionType) { activity in
                guard
                    let idString = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String,
                    let uuid = UUID(uuidString: idString)
                else { return }
                alarmManager.spotlightAlarmID = uuid
            }
    }
}

