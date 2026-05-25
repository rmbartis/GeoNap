// ToggleAlarmIntent.swift
// "Hey Siri, enable/disable my Penn Station GeoAlarm"

import AppIntents
import SwiftData

// MARK: - Enable

struct EnableAlarmIntent: AppIntent {

    static var title: LocalizedStringResource = "Enable GeoAlarm"
    static var description = IntentDescription(
        "Enables a GeoAlarm so it starts monitoring your location.",
        categoryName: "Edit"
    )
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Alarm")
    var alarm: GeoAlarmEntity

    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await setAlarmState(id: alarm.id, active: true)
        return .result(dialog: "'\(alarm.name)' is now enabled.")
    }
}

// MARK: - Disable

struct DisableAlarmIntent: AppIntent {

    static var title: LocalizedStringResource = "Disable GeoAlarm"
    static var description = IntentDescription(
        "Disables a GeoAlarm so it stops monitoring your location.",
        categoryName: "Edit"
    )
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Alarm")
    var alarm: GeoAlarmEntity

    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await setAlarmState(id: alarm.id, active: false)
        return .result(dialog: "'\(alarm.name)' is now disabled.")
    }
}

// MARK: - Shared helper

private func setAlarmState(id: UUID, active: Bool) async throws {
    let container = try await MainActor.run { try IntentModelContainer.make() }
    let context   = ModelContext(container)
    let alarms    = try context.fetch(FetchDescriptor<GeoAlarm>())

    guard let match = alarms.first(where: { $0.id == id }) else { return }
    match.state = active ? .active : .inactive
    try context.save()
}
