// CalendarScanBackgroundTask.swift
// Phase 3: BGAppRefreshTask that periodically re-runs the calendar scan
// pipeline in the background when Scan Mode is set to Automatic, so trips
// can be found (and, if enabled, notified about) without the user having to
// open the app and tap "Scan Now".
//
// Registered via SwiftUI's `.backgroundTask(.appRefresh(identifier))` scene
// modifier in NapStopApp.swift (iOS 17+ API) rather than the older
// BGTaskScheduler.register(forTaskWithIdentifier:) + AppDelegate dance — the
// scene modifier handles registration for us; this type only owns scheduling
// future requests and running the actual scan.
//
// ⚠️ Like GeoAlarmScheduler, this must be verified on a real device — the
// system decides when (and whether) to actually invoke a BGAppRefreshTask
// based on usage patterns and battery state; it is NOT a reliable timer, and
// the Simulator generally won't run it at all. Two ways to test without
// waiting on the OS:
//   1. `runScanNowForTesting()` below runs the exact same scan/merge/notify
//      code path synchronously from anywhere (e.g. a debug button) — this is
//      what actually exercises the logic; it does not go through BGTaskScheduler.
//   2. To test the OS delivering the task for real, pause at a breakpoint
//      after `scheduleNextRefresh()` runs at least once, then in the Xcode
//      debugger console run:
//      e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@"com.rmbartis.GeoNap.calendarScanRefresh"]
//      (undocumented but long-standing Apple debugging API for BGTaskScheduler).

import Foundation
import BackgroundTasks

enum CalendarScanBackgroundTask {

    /// Must exactly match the identifier registered in Info.plist's
    /// BGTaskSchedulerPermittedIdentifiers and used in the `.backgroundTask`
    /// scene modifier — the OS silently drops mismatched requests.
    static let identifier = "com.rmbartis.GeoNap.calendarScanRefresh"

    /// How far out to ask the OS to run the next scan. The OS treats this as
    /// an earliest-possible time, not a guarantee — actual execution is
    /// opportunistic and system-scheduled.
    private static let refreshInterval: TimeInterval = 4 * 60 * 60 // 4 hours

    // MARK: - Scheduling

    /// Submits a new background refresh request, replacing any pending one.
    /// Safe to call anytime; it's a no-op unless calendar scanning is enabled
    /// and Scan Mode is Automatic. Call this at app launch and whenever the
    /// user changes a relevant Settings toggle.
    static func scheduleNextRefresh() {
        // Always clear any existing pending request first — submitting while
        // one is already pending for this identifier throws, and settings
        // may have changed since the last request was scheduled.
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)

        guard UserDefaults.standard.bool(forKey: AppStorageKey.calendarScanEnabled) else { return }
        let modeRaw = UserDefaults.standard.string(forKey: AppStorageKey.calendarScanModeRaw) ?? CalendarScanMode.automatic.rawValue
        guard CalendarScanMode(rawValue: modeRaw) == .automatic else { return }

        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: refreshInterval)
        do {
            try BGTaskScheduler.shared.submit(request)
            DebugLogger.shared.log("Scheduled next calendar scan background refresh (earliest in \(Int(refreshInterval / 3600))h).", category: "CalendarScan")
        } catch {
            // Common in Simulator (background task submission is unsupported
            // there) — not fatal, just means Automatic mode only really scans
            // when the app is opened until this is verified on a device.
            DebugLogger.shared.log("Failed to schedule calendar scan background refresh: \(error.localizedDescription)", category: "CalendarScan")
        }
    }

    /// Cancels any pending background refresh request — call when the user
    /// disables scanning or switches to Manual Only.
    static func cancelScheduledRefresh() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
    }

    // MARK: - Execution

    /// Runs one scan pass: fetches events for the enabled calendars, merges
    /// results against the persisted pending/handled state (so already
    /// handled trips aren't re-surfaced), saves the result, and — if new
    /// candidates showed up and the user has notifications enabled — posts a
    /// local notification.
    ///
    /// Always re-schedules the next refresh before returning (even on early
    /// exit) so Automatic mode keeps running; BGAppRefreshTask is one-shot —
    /// nothing else will submit the next request otherwise.
    @MainActor
    static func run() async {
        defer { scheduleNextRefresh() }

        guard UserDefaults.standard.bool(forKey: AppStorageKey.calendarScanEnabled) else { return }
        let enabledIDs = CalendarScanStorage.decodeStringSet(
            UserDefaults.standard.string(forKey: AppStorageKey.calendarScanEnabledCalendarIDs) ?? "[]"
        )
        guard !enabledIDs.isEmpty else { return }

        let storedLookahead = UserDefaults.standard.integer(forKey: AppStorageKey.calendarScanLookaheadDays)
        let lookaheadDays = storedLookahead > 0 ? storedLookahead : 14

        let service = CalendarScanService()
        guard service.isAuthorized else { return }

        let found = await service.scanForCandidates(enabledCalendarIDs: enabledIDs, lookaheadDays: lookaheadDays)

        let existingPending = CalendarScanCandidateStore.loadPending()
        let handled = CalendarScanCandidateStore.loadHandled()
        let result = CalendarScanCandidateMerger.mergeScanResults(found: found, existingPending: existingPending, handled: handled)

        CalendarScanCandidateStore.savePending(result.pending)
        CalendarScanCandidateStore.saveHandled(result.handled)

        DebugLogger.shared.log("Background calendar scan: found=\(found.count) pending=\(result.pending.count) new=\(result.newlyPendingIDs.count)", category: "CalendarScan")

        guard !result.newlyPendingIDs.isEmpty,
              UserDefaults.standard.bool(forKey: AppStorageKey.calendarScanNotifyOnResults) else { return }
        await CalendarScanNotifier.postNewTripsNotification(count: result.newlyPendingIDs.count, bundle: LanguageManager.shared.currentBundle)
    }

    /// Runs the exact same scan/merge/persist/notify pipeline as a real
    /// background invocation, but callable directly — for verifying the
    /// feature end-to-end without waiting on (or fighting with) the OS's
    /// opportunistic BGAppRefreshTask scheduling. Does NOT go through
    /// BGTaskScheduler at all, so it works in the Simulator too.
    @MainActor
    static func runScanNowForTesting() async {
        await run()
    }
}
