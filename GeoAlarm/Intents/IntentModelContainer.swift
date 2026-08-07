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
        let schema = Schema([NapAlarm.self, GTFSFeedModel.self])
        let cloudConfig = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .automatic
        )
        if let c = try? ModelContainer(for: schema, configurations: [cloudConfig]) {
            return c
        }
        return try ModelContainerFactory.recoveringLocalContainer(schema: schema)
    }
}
