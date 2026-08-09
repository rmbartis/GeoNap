// Copyright © 2026 Robert Bartis. All rights reserved.

// NapStopApp.swift
// Entry point. Wires SwiftData ModelContainer, LocationManager, and AlarmManager.

import SwiftUI
import SwiftData
import CoreSpotlight
import BackgroundTasks
import UserNotifications

@main
struct NapStopApp: App {
    @StateObject private var locationManager = LocationManager()
    @StateObject private var alarmManager = AlarmManager()
    // LanguageManager persists the selected in-app language to plain
    // UserDefaults.standard (AppStorageKey.appLanguage) — state that lives
    // entirely outside the isolated in-memory SwiftData store below, so it
    // survives across every subsequent launch on the same simulator,
    // --uitesting or not. Once
    // test_switchingLanguage_rebuildsWithoutCrashing_andReturnsToSettings
    // runs once (this run or an earlier CI pass), every later UI test launch
    // boots in Spanish — which is exactly what silently broke "Save Alarm"
    // for three straight test runs (Bob — 2026-07-09 CI stability audit,
    // fifth pass): the button's real accessibility label was "Guardar
    // Alarma", not "Save Alarm", so no amount of scrolling or keyboard
    // dismissal could ever find it. Clear the stored language INSIDE this
    // property's own init closure — not in NapStopApp.init() below, which
    // runs too late: `@StateObject`'s default-value expression evaluates
    // (and reads UserDefaults via `LanguageManager.shared`'s `private
    // init()`) as part of struct property initialization, which completes
    // before a custom init() body ever runs.
    @StateObject private var languageManager: LanguageManager = {
        if ProcessInfo.processInfo.arguments.contains("--uitesting") {
            UserDefaults.standard.removeObject(forKey: AppStorageKey.appLanguage)
        }
        return LanguageManager.shared
    }()

    /// CloudKit-backed container with a local-only fallback.
    /// Falls back silently if the user is not signed into iCloud or if the
    /// CloudKit entitlement is missing (e.g. simulator without a paid account).
    ///
    /// UI tests (`--uitesting` launch argument, set by NapStopUITests) get an
    /// isolated in-memory store instead: every launch starts with zero alarms,
    /// deterministically, with no dependency on CloudKit/network availability
    /// in CI (Bob, 2026-07-05 — previously the UI test suite assumed a
    /// `--reset-alarms` flag that was never actually implemented anywhere).
    ///
    /// Never force-crashes on a bad on-disk store (Bob, 2026-07-25, after a
    /// TestFlight crash: NapStopApp.init() -> swift_unexpectedError from a
    /// `try!` here). A device that loses power mid-write — e.g. the battery
    /// dying while an alarm was being saved — can leave the local SQLite/WAL
    /// store corrupted; that used to mean a permanent crash-on-launch loop,
    /// since both the CloudKit attempt and the local fallback point at the
    /// same on-disk file and would fail identically forever. See
    /// ModelContainerFactory.swift for the recovery (delete the corrupted
    /// store and rebuild) and the last-resort in-memory fallback below.
    private let container: ModelContainer = {
        let schema = ModelContainerFactory.schema

        if ProcessInfo.processInfo.arguments.contains("--uitesting") {
            return ModelContainerFactory.makeInMemory(schema: schema)
        }

        let cloudConfig = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .automatic
        )
        if let c = try? ModelContainer(for: schema, configurations: [cloudConfig]) {
            return c
        }

        if let recovered = try? ModelContainerFactory.recoveringLocalContainer(schema: schema) {
            return recovered
        }

        // Absolute last resort — the CloudKit attempt above AND the
        // corrupted-store recovery both failed (e.g. genuinely out of disk
        // space). Run in memory rather than crash: the app stays launchable
        // for this session (no persisted alarms survive it) instead of
        // repeating the fatal crash this replaces.
        CrashReporter.log("ModelContainer: all disk-backed attempts failed at launch — running in-memory for this session")
        return ModelContainerFactory.makeInMemory(schema: schema)
    }()

    init() {
        // UI tests launch straight past onboarding — otherwise every run on a
        // fresh simulator (where "hasSeenOnboarding" has never been written)
        // would block on the onboarding fullScreenCover before reaching any
        // of the screens the tests actually exercise (Bob, 2026-07-05).
        if ProcessInfo.processInfo.arguments.contains("--uitesting") {
            UserDefaults.standard.set(true, forKey: "hasSeenOnboarding")
        }
        #if DEBUG
        // XCUITest runs as a separate process from the app — it can't call
        // EntitlementManager.testOverride = ... directly, so it passes the
        // desired tier as a launch argument instead (e.g.
        // "--uitesting-tier Free") and this reads it back before any UI
        // renders. Must run in init(), not RootView.onAppear — by the time a
        // View's onAppear fires, SwiftUI has already evaluated body once
        // with whatever tier was in effect at that point, and a gated
        // control's initial disabled state could be wrong for that first
        // frame. Silently a no-op if the flag is absent (ordinary manual
        // Xcode runs) or doesn't match a known tier name.
        if let tier = EntitlementManager.parseTierLaunchArgument(from: ProcessInfo.processInfo.arguments) {
            EntitlementManager.testOverride = tier
        }
        #endif
        CrashReporter.log("App launched")
        // Must happen before anything reads these UserDefaults keys directly
        // (e.g. CalendarScanBackgroundTask, which runs outside any View and
        // can't rely on @AppStorage's in-memory-only default). See
        // AppStorageKey.registerCalendarScanDefaults() for why this is needed.
        AppStorageKey.registerCalendarScanDefaults()
        // Same rationale, for GTFSService reading the retention-days default
        // directly (see AppStorageKey.registerGTFSCacheDefaults()).
        AppStorageKey.registerGTFSCacheDefaults()
        // Must be set early to catch a cold-launch tap on the "new trips
        // found" notification — see CalendarScanNotificationDelegate.
        UNUserNotificationCenter.current().delegate = CalendarScanNotificationDelegate.shared
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
        // Phase 3: periodic background re-scan of the user's calendars when
        // Scan Mode is Automatic. The identifier must match Info.plist's
        // BGTaskSchedulerPermittedIdentifiers exactly. This scene modifier
        // handles registering the task handler with the OS; scheduling
        // (deciding WHEN to ask for the next run) is CalendarScanBackgroundTask's
        // job, triggered at launch below and after relevant Settings changes.
        .backgroundTask(.appRefresh(CalendarScanBackgroundTask.identifier)) {
            await CalendarScanBackgroundTask.run()
        }
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
                AutoNotifyDefaultsStore.configure(modelContext)
                alarmManager.locationManager = locationManager
                locationManager.requestAlwaysAuthorization()
                alarmManager.reregisterAllRegions()
                // UI tests get an isolated in-memory SwiftData store (see
                // `container` above), but AlarmKit alarms are OS-level state
                // that lives entirely outside that store — a real alarm left
                // over from a prior run (manual testing or an earlier CI
                // pass) keeps showing its Live Activity across every
                // subsequent launch, silently intercepting taps meant for
                // the app's own toolbar underneath it. Clear the slate
                // before any test-driven alarm scheduling can happen. (Bob —
                // 2026-07-09 CI stability audit, after a failure screenshot
                // showed a stale "Penn Station" Live Activity banner
                // blocking addAlarmMenuButton / settingsButton.)
                if ProcessInfo.processInfo.arguments.contains("--uitesting") {
                    GeoAlarmScheduler.cancelAll()
                }
                // AlarmKit (iOS 26+): prompt for alarm permission so a geofence
                // fire can present a system alarm. Lazily re-checked before each
                // fire, but requesting at launch surfaces the prompt early.
                Task { await GeoAlarmScheduler.ensureAuthorized() }
                // Phase 3, item 9: start StoreKit's transaction listener and
                // run the first entitlement check. Called here (not
                // NapStopApp.init()) because `App.init()` isn't reliably
                // MainActor-isolated, and PurchaseManager is a `@MainActor`
                // class — same reasoning as the other launch-time async
                // kick-offs on this screen.
                PurchaseManager.shared.start()
                // Phase 3: (re-)submit the next Calendar Scanning background
                // refresh request. No-ops internally unless scanning is
                // enabled and Scan Mode is Automatic.
                CalendarScanBackgroundTask.scheduleNextRefresh()
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

