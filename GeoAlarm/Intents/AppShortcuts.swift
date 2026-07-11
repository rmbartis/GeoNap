// Copyright © 2026 Robert Bartis. All rights reserved.

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
            shortTitle: "Create GeoNap",
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
            shortTitle: "Enable GeoNap",
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
            shortTitle: "Disable GeoNap",
            systemImageName: "pause.circle.fill"
        )

        // ── Notify Contacts ───────────────────────────────────────────────────
        // Used as Action 1 in a Personal Automation — see NotifyContactsIntent.swift's
        // file header for the full setup (Trigger: App → GeoNap → Is Opened,
        // If Body has any value, Send Message inside, Run Immediately). This
        // intent returns a structured Body/Recipients result and never throws —
        // see the file header for why (a thrown error surfaced as a system
        // "Automation Failed" banner on every ordinary app-open).
        AppShortcut(
            intent: NotifyContactsIntent(),
            phrases: [
                "Notify my contacts via \(.applicationName)",
                "Send \(.applicationName) alert to contacts"
            ],
            shortTitle: "Notify Contacts",
            systemImageName: "message.fill"
        )

        // ── Run Shortcut on Alarm ─────────────────────────────────────────────
        // Used as an action in the SAME Personal Automation as NotifyContactsIntent
        // — see RunAlarmShortcutIntent.swift's file header for the full setup
        // (Trigger: App → GeoNap → Is Opened, If Shortcut Name is not empty,
        // Run Shortcut, Run Immediately). Never throws, same reasoning as
        // NotifyContactsIntent.
        AppShortcut(
            intent: RunAlarmShortcutIntent(),
            phrases: [
                "Get \(.applicationName) alarm shortcut",
                "Run \(.applicationName) alarm shortcut"
            ],
            shortTitle: "Get Alarm Shortcut",
            systemImageName: "bolt.horizontal.circle.fill"
        )
    }
}
