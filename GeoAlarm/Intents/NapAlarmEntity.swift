// NapAlarmEntity.swift
// AppEntity that lets Siri and Shortcuts resolve alarm names to NapAlarm records.
// NapAlarmQuery backs the entity with live SwiftData lookups.

import AppIntents
import SwiftData
import Foundation

// MARK: - Entity

struct NapAlarmEntity: AppEntity {

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "NapAlarm"
    static var defaultQuery = NapAlarmQuery()

    let id: UUID
    let name: String
    let isActive: Bool

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

// MARK: - Query

struct NapAlarmQuery: EntityQuery {

    /// Called when a Shortcut resolves an alarm by its saved UUID.
    func entities(for identifiers: [UUID]) async throws -> [NapAlarmEntity] {
        let container = try await MainActor.run { try IntentModelContainer.make() }
        let context   = ModelContext(container)
        let alarms    = try context.fetch(FetchDescriptor<NapAlarm>())
        return alarms
            .filter { identifiers.contains($0.id) }
            .map    { NapAlarmEntity(id: $0.id, name: $0.name, isActive: $0.isActive) }
    }

    /// Populates the picker when the user configures a Shortcut in the Shortcuts app.
    func suggestedEntities() async throws -> [NapAlarmEntity] {
        let container = try await MainActor.run { try IntentModelContainer.make() }
        let context   = ModelContext(container)
        let alarms    = try context.fetch(
            FetchDescriptor<NapAlarm>(sortBy: [SortDescriptor(\.name)])
        )
        return alarms.map { NapAlarmEntity(id: $0.id, name: $0.name, isActive: $0.isActive) }
    }
}
