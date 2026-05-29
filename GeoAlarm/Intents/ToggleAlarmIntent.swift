// ToggleAlarmIntent.swift
// "Hey Siri, enable/disable my Penn Station NapAlarm"

import AppIntents
import SwiftData

// MARK: - Enable

struct EnableAlarmIntent: AppIntent {

    static var title: LocalizedStringResource = "Enable NapAlarm"
    static var description = IntentDescription(
        "Enables a NapAlarm so it starts monitoring your location.",
        categoryName: "Edit"
    )
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Alarm")
    var alarm: NapAlarmEntity

    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await setAlarmState(id: alarm.id, active: true)
        return .result(dialog: "'\(alarm.name)' is now enabled.")
    }
}

// MARK: - Disable

struct DisableAlarmIntent: AppIntent {

    static var title: LocalizedStringResource = "Disable NapAlarm"
    static var description = IntentDescription(
        "Disables a NapAlarm so it stops monitoring your location.",
        categoryName: "Edit"
    )
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Alarm")
    var alarm: NapAlarmEntity

    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await setAlarmState(id: alarm.id, active: false)
        return .result(dialog: "'\(alarm.name)' is now disabled.")
    }
}

// MARK: - Shared helper

private func setAlarmState(id: UUID, active: Bool) async throws {
    let container = try await MainActor.run { try IntentModelContainer.make() }
    let context   = ModelContext(container)
    let alarms    = try context.fetch(FetchDescriptor<NapAlarm>())

    guard let match = alarms.first(where: { $0.id == id }) else { return }
    match.state = active ? .active : .inactive
    try context.save()
}
