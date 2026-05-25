// IntentModelContainer.swift
// Provides a ModelContainer for AppIntents, which run outside the main app
// process and cannot access the @EnvironmentObject AlarmManager directly.
// Uses the same schema as GeoAlarmApp (.modelContainer(for: GeoAlarm.self)).

import SwiftData
import Foundation

enum IntentModelContainer {
    /// Returns a configured ModelContainer for use inside AppIntent.perform().
    /// @MainActor required because ModelContainer.init is main-actor isolated.
    @MainActor
    static func make() throws -> ModelContainer {
        try ModelContainer(for: GeoAlarm.self)
    }
}
