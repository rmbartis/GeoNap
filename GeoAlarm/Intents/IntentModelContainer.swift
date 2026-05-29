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
        let localConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        return try ModelContainer(for: schema, configurations: [localConfig])
    }
}
