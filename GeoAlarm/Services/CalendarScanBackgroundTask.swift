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
import SwiftData

/// Pure decision logic for `CalendarScanBackgroundTask.scheduleNextRefresh()`:
/// should it actually submit a new `BGAppRefreshTaskRequest`, or leave an
/// already-pending one alone? Extracted as a standalone enum (mirrors
/// `CalendarScanCandidateMerger`, `CalendarScanLocationExtractor`, etc.) so
/// the decision is unit testable without touching BGTaskScheduler.
///
/// Without this guard, `scheduleNextRefresh()` used to cancel + resubmit
/// unconditionally on every call, including from `RootView.onAppear` — which
/// fires on every app foreground, not just cold launch. Each call reset
/// `earliestBeginDate` to "4 hours from now," so anyone who opens the app
/// more than once every 4 hours kept pushing the window out, and the
/// background task could never actually become eligible to run. Bob hit this
/// directly: a calendar event created over an hour earlier still hadn't been
/// picked up by Automatic mode, because normal app use (checking on it) kept
/// resetting the clock (2026-07-03).
enum CalendarScanRefreshScheduling {
    /// - Parameters:
    ///   - force: Bypass the pending-request check — used when the schedule
    ///     genuinely needs to restart (e.g. right after a scan just ran and
    ///     consumed the previous request).
    ///   - existingEarliestDate: The `earliestBeginDate` of the
    ///     currently-tracked pending request, if any.
    ///   - now: Current time (injected for testability).
    static func shouldSubmit(force: Bool, existingEarliestDate: Date?, now: Date) -> Bool {
        if force { return true }
        guard let existing = existingEarliestDate else { return true }
        return existing <= now
    }
}

enum CalendarScanBackgroundTask {

    /// Must exactly match the identifier registered in Info.plist's
    /// BGTaskSchedulerPermittedIdentifiers and used in the `.backgroundTask`
    /// scene modifier — the OS silently drops mismatched requests.
    static let identifier = "com.rmbartis.GeoNap.calendarScanRefresh"

    /// How far out to ask the OS to run the next scan, resolved from the
    /// user's Settings → Calendar Scanning → Scan Behavior picker
    /// (CalendarScanRefreshInterval; defaults to 4h). The OS treats this as
    /// an earliest-possible time, not a guarantee — actual execution is
    /// opportunistic and system-scheduled regardless of what's picked here.
    private static var refreshInterval: TimeInterval {
        let stored = UserDefaults.standard.integer(forKey: AppStorageKey.calendarScanRefreshIntervalMinutes)
        return CalendarScanRefreshInterval.resolve(storedMinutes: stored).timeInterval
    }

    // MARK: - Scheduling

    /// (Re-)submits a background refresh request if one isn't already
    /// pending. It's a no-op unless calendar scanning is enabled and Scan
    /// Mode is Automatic. Safe to call anytime, including opportunistically
    /// on every app foreground — see `CalendarScanRefreshScheduling` for why
    /// this is idempotent by default rather than resetting the clock on
    /// every call.
    ///
    /// - Parameter force: Pass `true` only when the schedule genuinely needs
    ///   to restart (currently just `CalendarScanBackgroundTask.run()`, right
    ///   after its own request was consumed by the OS). Settings-change call
    ///   sites (enabling scanning, switching to Automatic) don't need this —
    ///   disabling/switching to Manual already clears the tracked date, so
    ///   re-enabling naturally submits fresh.
    static func scheduleNextRefresh(force: Bool = false) {
        guard UserDefaults.standard.bool(forKey: AppStorageKey.calendarScanEnabled) else {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
            UserDefaults.standard.removeObject(forKey: AppStorageKey.calendarScanNextRefreshEarliestDate)
            return
        }
        let modeRaw = UserDefaults.standard.string(forKey: AppStorageKey.calendarScanModeRaw) ?? CalendarScanMode.automatic.rawValue
        guard CalendarScanMode(rawValue: modeRaw) == .automatic else {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
            UserDefaults.standard.removeObject(forKey: AppStorageKey.calendarScanNextRefreshEarliestDate)
            return
        }

        let existingEarliestDate = UserDefaults.standard.object(forKey: AppStorageKey.calendarScanNextRefreshEarliestDate) as? Date
        guard CalendarScanRefreshScheduling.shouldSubmit(force: force, existingEarliestDate: existingEarliestDate, now: Date()) else {
            return // Already have a request pending whose window hasn't opened yet — leave it alone.
        }

        // Only reached when we're actually (re)submitting — safe to cancel
        // first since we know we're about to replace it.
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)

        let request = BGAppRefreshTaskRequest(identifier: identifier)
        let earliest = Date(timeIntervalSinceNow: refreshInterval)
        request.earliestBeginDate = earliest
        do {
            try BGTaskScheduler.shared.submit(request)
            UserDefaults.standard.set(earliest, forKey: AppStorageKey.calendarScanNextRefreshEarliestDate)
            DebugLogger.shared.log("Scheduled next calendar scan background refresh (earliest in \(Int(refreshInterval / 3600))h).", category: "CalendarScan")
        } catch {
            UserDefaults.standard.removeObject(forKey: AppStorageKey.calendarScanNextRefreshEarliestDate)
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
        UserDefaults.standard.removeObject(forKey: AppStorageKey.calendarScanNextRefreshEarliestDate)
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
    /// nothing else will submit the next request otherwise. Forces the
    /// reschedule since the request that triggered this run was just
    /// consumed by the OS — there's genuinely nothing else pending now.
    @MainActor
    static func run() async {
        defer { scheduleNextRefresh(force: true) }

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
        let rawHandled = CalendarScanCandidateStore.loadHandled()
        // Same reconciliation as the manual "Scan Now" path (see
        // CalendarScanSettingsView.runScanNow) — drop "added" records whose
        // alarm was since deleted so that event can be re-offered. This runs
        // outside the main app scene, with no AlarmManager instance to ask,
        // so it fetches alarms via its own ModelContainer (Bob, 2026-07-03).
        let existingAlarmEventIDs = existingCalendarEventIDs()
        let handled = CalendarScanCandidateMerger.reconcileHandled(rawHandled, existingAlarmEventIDs: existingAlarmEventIDs)
        let result = CalendarScanCandidateMerger.mergeScanResults(found: found, existingPending: existingPending, handled: handled)

        CalendarScanCandidateStore.savePending(result.pending)
        CalendarScanCandidateStore.saveHandled(result.handled)

        DebugLogger.shared.log("Background calendar scan: found=\(found.count) pending=\(result.pending.count) new=\(result.newlyPendingIDs.count)", category: "CalendarScan")

        guard !result.newlyPendingIDs.isEmpty,
              UserDefaults.standard.bool(forKey: AppStorageKey.calendarScanNotifyOnResults) else { return }
        await CalendarScanNotifier.postNewTripsNotification(count: result.newlyPendingIDs.count, bundle: LanguageManager.shared.currentBundle)
    }

    /// The set of `calendarEventID` values currently in use by any saved
    /// alarm. Opens its own ModelContainer against the same CloudKit-backed
    /// store NapStopApp uses (via IntentModelContainer, the same helper
    /// AppIntents/Siri Shortcuts use for the same "running outside the main
    /// scene" reason) rather than reaching for a live AlarmManager, which
    /// doesn't exist in a BGAppRefreshTask context.
    @MainActor
    private static func existingCalendarEventIDs() -> Set<String> {
        do {
            let container = try IntentModelContainer.make()
            let context = ModelContext(container)
            let alarms = try context.fetch(FetchDescriptor<NapAlarm>())
            return Set(alarms.compactMap(\.calendarEventID))
        } catch {
            DebugLogger.shared.log("Background calendar scan: failed to fetch existing alarms for handled-reconciliation: \(error.localizedDescription)", category: "CalendarScan")
            return []
        }
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
