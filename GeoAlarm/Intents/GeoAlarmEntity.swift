// GeoAlarmEntity.swift
// AppEntity that lets Siri and Shortcuts resolve alarm names to GeoAlarm records.
// GeoAlarmQuery backs the entity with live SwiftData lookups.

import AppIntents
import SwiftData
import Foundation

// MARK: - Entity

struct GeoAlarmEntity: AppEntity {

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "GeoAlarm"
    static var defaultQuery = GeoAlarmQuery()

    let id: UUID
    let name: String
    let isActive: Bool

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

// MARK: - Query

struct GeoAlarmQuery: EntityQuery {

    /// Called when a Shortcut resolves an alarm by its saved UUID.
    func entities(for identifiers: [UUID]) async throws -> [GeoAlarmEntity] {
        let container = try await MainActor.run { try IntentModelContainer.make() }
        let context   = ModelContext(container)
        let alarms    = try context.fetch(FetchDescriptor<GeoAlarm>())
        return alarms
            .filter { identifiers.contains($0.id) }
            .map    { GeoAlarmEntity(id: $0.id, name: $0.name, isActive: $0.isActive) }
    }

    /// Populates the picker when the user configures a Shortcut in the Shortcuts app.
    func suggestedEntities() async throws -> [GeoAlarmEntity] {
        let container = try await MainActor.run { try IntentModelContainer.make() }
        let context   = ModelContext(container)
        let alarms    = try context.fetch(
            FetchDescriptor<GeoAlarm>(sortBy: [SortDescriptor(\.name)])
        )
        return alarms.map { GeoAlarmEntity(id: $0.id, name: $0.name, isActive: $0.isActive) }
    }
}
