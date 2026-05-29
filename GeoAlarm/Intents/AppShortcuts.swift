// AppShortcuts.swift
// Registers Siri phrases so shortcuts appear automatically in Spotlight,
// the Shortcuts app, and Siri suggestions — no user setup required.
//
// All phrases MUST contain \(.applicationName) (an AppIntents requirement).
// The token is substituted with the app's display name at runtime.

import AppIntents

struct NapAlarmShortcuts: AppShortcutsProvider {

    static var appShortcuts: [AppShortcut] {

        // ── Create ────────────────────────────────────────────────────────────
        AppShortcut(
            intent: CreateAlarmIntent(),
            phrases: [
                "Create a \(.applicationName)",
                "New \(.applicationName)",
                "Set a \(.applicationName)"
            ],
            shortTitle: "Create NapAlarm",
            systemImageName: "location.fill"
        )

        // ── Enable ────────────────────────────────────────────────────────────
        AppShortcut(
            intent: EnableAlarmIntent(),
            phrases: [
                "Enable my \(.applicationName)",
                "Turn on \(.applicationName)",
                "Activate \(.applicationName)"
            ],
            shortTitle: "Enable NapAlarm",
            systemImageName: "play.circle.fill"
        )

        // ── Disable ───────────────────────────────────────────────────────────
        AppShortcut(
            intent: DisableAlarmIntent(),
            phrases: [
                "Disable my \(.applicationName)",
                "Turn off \(.applicationName)",
                "Deactivate \(.applicationName)"
            ],
            shortTitle: "Disable NapAlarm",
            systemImageName: "pause.circle.fill"
        )
    }
}
