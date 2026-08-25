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
    /// `@State`, not `let`, since 2026-08-24 (non-blocking iCloud sync
    /// architecture): launch ALWAYS starts on a temporary in-memory
    /// placeholder — never touches CloudKit synchronously — and
    /// `resolveCloudKitContainerIfNeeded()` below resolves the real
    /// container in the background and swaps it in, mutating `container`
    /// after init returns.
    ///
    /// REVISED 2026-08-25: the first version of this also tried ONE fast,
    /// synchronous CloudKit attempt here in init() before falling back to
    /// the placeholder (`ModelContainerFactory.quickCloudKitAttempt`).
    /// Removed after a real-device restart test hung for 2+ minutes with NO
    /// log evidence a launch even started — `ModelContainer(...
    /// cloudKitDatabase: .automatic)` has no timeout, and `init()` runs
    /// before the Scene/View hierarchy exists, so nothing (not even the
    /// syncing banner) could render while it was blocked. init() now does
    /// zero CloudKit/network work — see its own comment for the full
    /// account. `resolveCloudKitContainerPatiently`'s first attempt still
    /// resolves near-instantly on the common warm-CloudKit case, so this
    /// costs nothing in practice.
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
    @State private var container: ModelContainer

    init() {
        // Unconditional, guaranteed-once-per-process marker — MUST be the
        // very first thing init() does, before any container/CloudKit work
        // below. Added 2026-08-24 as direct evidence for a theory: RootView's
        // .onAppear — where DebugLogger's session header AND
        // AlarmManager.setModelContext()/PurchaseManager.shared.start()
        // used to live — was suspected of not firing on every real launch,
        // particularly ones triggered by iOS in the background (e.g. a
        // location/region-monitoring wake right after a device reboot)
        // rather than a user tapping the icon. init() has no such
        // ambiguity: it runs exactly once, unconditionally, on every
        // process launch, so this line is the ground truth for "how many
        // times did the process actually start" when reading a debug log —
        // see RootView.performLaunchSetupIfNeeded's doc comment for the
        // fix this evidence led to.
        //
        // MOVED HERE 2026-08-25: previously this ran after the container
        // was selected below, which briefly included a synchronous, no-
        // timeout `ModelContainer(...cloudKitDatabase:...)` attempt
        // (`quickCloudKitAttempt`). A device test right after a real reboot
        // showed the app stuck for 2+ minutes with NO log evidence of a
        // new launch at all — consistent with that synchronous CloudKit
        // call hanging before this marker (and everything else) ever ran.
        // Keeping this line first means a repeat of that failure mode will
        // still show up as "a launch started, then nothing" instead of
        // vanishing from the log entirely — and see below for the actual
        // fix (no more synchronous CloudKit calls in init() at all).
        CrashReporter.log("App launched")
        DebugLogger.shared.log("NapStopApp.init() — process launched", category: "Launch")

        let schema = ModelContainerFactory.schema
        // NEVER touch CloudKit synchronously here. `init()` runs before the
        // Scene/View hierarchy exists — nothing can render, including the
        // syncing banner, until it returns, and `ModelContainer(for:
        // configurations: [cloudKitDatabase: .automatic])` has no timeout of
        // its own. `openCloudKitContainerRecoveringIfNeeded`'s existing
        // retry loop proves this call CAN throw slowly right after boot; it
        // can plausibly also just hang rather than throw, blocking launch
        // indefinitely with nothing on screen and nothing in the log. So
        // launch ALWAYS starts on the local in-memory placeholder — instant,
        // no network, no CloudKit — and the real container is resolved
        // entirely off this path by resolveCloudKitContainerIfNeeded(),
        // triggered from RootView's already-proven three-trigger hook. On
        // the common case (CloudKit already warm) that resolves in well
        // under a second and the user never sees a placeholder or banner.
        _container = State(initialValue: ModelContainerFactory.makeLocalPlaceholder(schema: schema))

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
            RootView(resolveCloudKitContainerIfNeeded: resolveCloudKitContainerIfNeeded)
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

    /// Resolves the real CloudKit-backed container in the background and
    /// swaps it in for the launch-time placeholder — the ONLY place this
    /// app ever attempts to open the CloudKit-backed store (see init()'s
    /// comment for why that attempt was removed from the launch path
    /// entirely on 2026-08-25). Triggered unconditionally from
    /// RootView.performLaunchSetupIfNeeded: that's the same
    /// three-independent-trigger hook already proven reliable for
    /// background/post-reboot launches (see that method's doc comment) —
    /// reusing it here instead of inventing a second, unvalidated entry
    /// point for essentially the same "run once, reliably, after real
    /// launch" requirement. No-op for `--uitesting` launches, which stay on
    /// their isolated in-memory store deliberately (see `container`'s doc
    /// comment) — never attempt or need CloudKit.
    ///
    /// `resolveCloudKitContainerPatiently` tries immediately on its first
    /// attempt, so the common case (CloudKit already warm) resolves in a
    /// fraction of a second. To avoid flashing the syncing banner on that
    /// fast path, `alarmManager.isSyncingWithiCloud` is only flipped on if
    /// resolution is STILL in progress after a short grace period — a
    /// separate `Task` racing the resolve, cancelled the moment it finishes.
    ///
    /// Any alarm the user creates against the placeholder during this
    /// window is carried over via `migratePlaceholderAlarms` before the
    /// swap, so nothing typed in during the syncing banner is lost.
    /// Re-points `alarmManager` at the resolved context and reloads +
    /// re-registers regions so the visible alarm list and active geofences
    /// reflect the merged result immediately, rather than waiting for the
    /// next relaunch.
    private func resolveCloudKitContainerIfNeeded() async {
        guard !ProcessInfo.processInfo.arguments.contains("--uitesting") else { return }
        let schema = ModelContainerFactory.schema
        let placeholder = container

        let bannerDelay: UInt64 = 400_000_000 // 0.4s — see doc comment above
        let bannerTask = Task {
            try? await Task.sleep(nanoseconds: bannerDelay)
            guard !Task.isCancelled else { return }
            alarmManager.isSyncingWithiCloud = true
            DebugLogger.shared.log("iCloud sync: still resolving after 0.4s — showing syncing banner", category: "ModelContainer")
        }

        let resolved = await ModelContainerFactory.resolveCloudKitContainerPatiently(schema: schema)
        bannerTask.cancel()

        let migratedCount = ModelContainerFactory.migratePlaceholderAlarms(from: placeholder, into: resolved)
        container = resolved
        alarmManager.setModelContext(resolved.mainContext)
        alarmManager.reregisterAllRegions()
        alarmManager.isSyncingWithiCloud = false
        let migrationNote = migratedCount > 0 ? " — migrated \(migratedCount) alarm(s) created while syncing" : ""
        DebugLogger.shared.log("iCloud sync: resolved container installed\(migrationNote)", category: "ModelContainer")
    }
}

/// Thin wrapper that passes the SwiftData ModelContext to AlarmManager
/// on first appear, then hands off to ContentView.
struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject var locationManager: LocationManager
    @EnvironmentObject var alarmManager: AlarmManager
    // Guards the launch-time location request below — see comment there.
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false

    // Guards performLaunchSetupIfNeeded() so its real work only ever
    // executes once per process, even though — as of 2026-08-24 — it's
    // now triggered from THREE independent SwiftUI entry points instead of
    // just one. See that method's doc comment for why.
    @State private var hasCompletedLaunchSetup = false

    // Set by NapStopApp — resolves the real CloudKit-backed container in
    // the background and swaps it in for the launch-time placeholder, if
    // needed. Defaulted to a no-op so this View stays constructible without
    // it (previews, tests). See NapStopApp.resolveCloudKitContainerIfNeeded's
    // doc comment for why this lives there and is just invoked from here.
    var resolveCloudKitContainerIfNeeded: () async -> Void = {}

    var body: some View {
        ContentView()
            .onAppear { performLaunchSetupIfNeeded(trigger: "onAppear") }
            .task { performLaunchSetupIfNeeded(trigger: "task") }
            // When the app returns to the foreground, clean up any windowed alarms
            // whose active window ended while the app was suspended/terminated
            // (the in-memory window-end timer can't run in that state).
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    alarmManager.deactivateExpiredWindowAlarms()
                    // Safety net, same 2026-08-24 fix as above: a
                    // background/location-triggered launch reaching
                    // .active is a third independent chance to catch setup
                    // that .onAppear/.task may have missed.
                    performLaunchSetupIfNeeded(trigger: "scenePhase")
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

    /// Found 2026-08-24, investigating alarms and Platinum tier both
    /// appearing "reset" after a device restart: a debug log spanning
    /// several real restart tests showed 4 separate "WCSession activated"
    /// entries — a reliable once-per-process marker, since it's logged from
    /// WatchConnectivityManager.shared's singleton `init()` — but only ONE
    /// "Session started" header, which used to be written from THIS
    /// closure when it was wired to `.onAppear` alone. Location delegate
    /// callbacks kept logging normally on every one of those launches
    /// (they don't depend on this setup running), which is exactly why
    /// every debug log collected during this investigation looked "clean"
    /// with no errors anywhere: `alarmManager.setModelContext(...)` and
    /// `PurchaseManager.shared.start()` simply never ran on those launches,
    /// so `alarms` stayed at its default empty array and `verifiedTier`
    /// stayed at whatever UserDefaults last cached for that entire process
    /// lifetime — not corruption, not a CloudKit/StoreKit timing race, just
    /// this closure not reliably firing for a launch iOS triggers itself in
    /// the background (e.g. region-monitoring resuming right after a
    /// reboot) as opposed to the user tapping the icon.
    ///
    /// Fix: call this from `.onAppear`, `.task`, AND the first `.active`
    /// scenePhase transition — three independent SwiftUI signals instead
    /// of relying on one. `hasCompletedLaunchSetup` ensures the actual
    /// setup — including things that are NOT safe to run twice, like
    /// `observeRemoteChanges()`'s `NotificationCenter` observer registration
    /// inside `setModelContext()` — still only executes once per process,
    /// regardless of how many of the three triggers actually fire.
    private func performLaunchSetupIfNeeded(trigger: String) {
        guard !hasCompletedLaunchSetup else { return }
        hasCompletedLaunchSetup = true

        // Stamp a fresh session header (with the current build) at launch so
        // every run in the debug log is tied to the build it ran on.
        DebugLogger.shared.beginSessionIfEnabled()
        DebugLogger.shared.log("RootView launch setup running (triggered by \(trigger))", category: "Launch")

        // Copy bundled WAV sounds into Library/Sounds so UNNotificationSound(named:)
        // can find them. Must run before any alarm can fire.
        NotificationSound.installBundledSoundsIfNeeded()
        alarmManager.setModelContext(modelContext)
        AutoNotifyDefaultsStore.configure(modelContext)
        alarmManager.locationManager = locationManager
        // Only fire this for users who've already completed onboarding.
        // On a fresh install, ContentView's onAppear (this closure) runs
        // at the same moment the onboarding fullScreenCover is presented
        // — an unconditional call here raced ahead of onboarding's own
        // "Continue" button and popped the system location prompt on top
        // of the language picker (App Store Review Guideline 5.1.1(iv)
        // rejection, found via device testing 2026-08-21, after the
        // OnboardingView fix for the same guideline). For a returning
        // user this is a harmless no-op if already authorized, or a
        // legitimate re-prompt if they haven't decided yet.
        if hasSeenOnboarding {
            locationManager.requestAlwaysAuthorization()
        }
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
        // Same guard as the location request above and for the same
        // reason — on a fresh install this raced ahead of onboarding's
        // "Continue" button and popped the AlarmKit system dialog on
        // top of the language picker (found via device testing
        // 2026-08-21, same session as the location fix). First-time
        // users now get this from OnboardingView's Continue button.
        if hasSeenOnboarding {
            Task { await GeoAlarmScheduler.ensureAuthorized() }
        }
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
        // Non-blocking iCloud sync (2026-08-24): if launch's quick CloudKit
        // attempt in NapStopApp.init() didn't succeed, this is what actually
        // resolves the real container in the background and swaps it in —
        // piggybacking on this already-validated three-trigger-reliable
        // hook rather than a separate, unproven SwiftUI entry point. No-op
        // (returns immediately) on the common path where launch's quick
        // attempt already succeeded.
        Task {
            await resolveCloudKitContainerIfNeeded()
        }
    }
}

