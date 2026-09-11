// Copyright © 2026 Robert Bartis. All rights reserved.

// IntentModelContainer.swift
// Provides a ModelContainer for AppIntents, which run outside the main app
// process and cannot access the @EnvironmentObject AlarmManager directly.
// Uses the same schema as NapStopApp (.modelContainer(for: NapAlarm.self)).

import SwiftData
import Foundation

enum IntentModelContainer {
    /// Returns a CloudKit-backed ModelContainer matching the main app's store.
    /// Falls back to local-only if CloudKit is unavailable.
    /// @MainActor required because ModelContainer.init is main-actor isolated.
    ///
    /// If the local store is corrupted (e.g. left in a bad state after the
    /// device lost power mid-write — see ModelContainerFactory.swift's file
    /// header for the crash this class of bug caused in NapStopApp), the
    /// local attempt below deletes it and retries once rather than failing
    /// forever. Unlike NapStopApp, this still `throws` on total failure —
    /// there's no "last resort" here; an Intent run out-of-process should
    /// surface a clear error to Shortcuts/the widget rather than silently
    /// operating on an empty in-memory store.
    @MainActor
    static func make() throws -> ModelContainer {
        // MUST be ModelContainerFactory.schema (not a hand-rolled Schema([...])
        // here) — this was the actual cause of a 2026-09-11 background crash
        // (0xdead10cc / RUNNINGBOARD SIGKILL while the app was suspended
        // overnight). This used to list only [NapAlarm.self, GTFSFeedModel
        // .self], missing AutoNotifyDefaultsRecord.self (added to the real
        // schema 2026-07-11 — see ModelContainerFactory.swift/
        // AutoNotifyDefaultsStore.swift). Every time this opened the SAME
        // on-disk CloudKit store the main app uses, SwiftData saw a 2-entity
        // schema against a 3-entity on-disk model and treated it as needing
        // a store migration — which CalendarScanBackgroundTask.run() (the
        // only caller, via existingCalendarEventIDs()) then triggered from
        // a background execution context. The migration's WAL checkpoint
        // got stuck retrying a busy lock (sqlite3InvokeBusyHandler /
        // walBusyLock) long enough that RunningBoard killed the whole
        // process for holding a file lock while backgrounded. Using the one
        // real schema means there's never a mismatch to "migrate" away.
        // See ModelContainerFactory.openCloudKitContainerRecoveringIfNeeded's
        // doc comment — recovers a corrupted local store and retries
        // CloudKit against the freshly recovered file, rather than
        // silently settling for local-only when the original failure was
        // file corruption, not an iCloud/CloudKit problem.
        return try ModelContainerFactory.openCloudKitContainerRecoveringIfNeeded(schema: ModelContainerFactory.schema)
    }
}
