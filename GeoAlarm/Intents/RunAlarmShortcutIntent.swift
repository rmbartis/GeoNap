// Copyright © 2026 Robert Bartis. All rights reserved.

// RunAlarmShortcutIntent.swift
// An AppIntent that retrieves the name of the Shortcut configured on the most
// recently fired GeoNap alarm that has "Run Shortcut on Alarm" enabled, and
// clears it. Deliberately mirrors NotifyContactsIntent.swift's design almost
// line for line — see that file's header for the full rationale (why "Is
// Opened" is the only app trigger iOS offers, why this never throws, why
// there's no staleness cutoff).
//
// Designed to live in the SAME Shortcuts Personal Automation as
// NotifyContactsIntent (Trigger: App → GeoNap → "Is Opened", Run
// Immediately): add a second action pair alongside "Notify Contacts via
// GeoNap" / "Send Message" —
//   Action: "Get Alarm Shortcut via GeoNap"   ← this intent
//           → output: "Shortcut Name" (String), nil (never thrown) if
//             there's nothing pending, so an ordinary app-open is a silent
//             no-op here too.
//   Action: If → "Shortcut Name" is not empty
//             "Run Shortcut" (input: "Shortcut Name" from the action above)
//
// GeoNap itself never inspects or constrains what the named Shortcut does —
// HomeKit scenes, an email, remote-starting a car, a webhook, anything the
// Shortcuts app supports. See AlarmManager.runShortcutIfConfigured(for:) for
// how the name gets queued, and help.body.runShortcut for the user-facing
// explanation (including the single-pending-slot limitation this intent
// shares with NotifyContactsIntent — only the most recently fired alarm's
// Shortcut runs if a second one fires before the user opens the app).

import AppIntents
import Foundation

// MARK: - UserDefaults keys

enum RunShortcutDefaultsKey {
    static let pendingShortcutName = "runShortcut_pendingName"
    /// Unix time (TimeInterval) when `pendingShortcutName` was last written.
    /// Not used for staleness rejection — matches AutoNotifyDefaultsKey's
    /// pendingBodyTimestamp as of 2026-07-11 (no cutoff). Kept so a future
    /// queue-based fix (see the TODO on AlarmManager.queueAutoNotify, which
    /// would need a matching change here) has a fire time to sort by.
    static let pendingShortcutFiredAt = "runShortcut_pendingFiredAt"
}

// MARK: - Structured result

/// The output of `RunAlarmShortcutIntent`. Optional, not empty-when-absent —
/// same reasoning as `NotifyContactsResult`: a non-optional String is always
/// "present" as far as Shortcuts' "Has Any Value" check is concerned, even
/// when it's "", which would let "Run Shortcut" attempt to run an empty name
/// on every ordinary app-open.
struct RunAlarmShortcutResult: TransientAppEntity {

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "GeoNap Alarm Shortcut"

    @Property(identifier: "shortcutName", title: "Shortcut Name")
    var shortcutName: String?

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(shortcutName ?? "")")
    }

    init() {
        self.shortcutName = nil
    }

    init(shortcutName: String?) {
        self.shortcutName = shortcutName
    }
}

// MARK: - Intent

struct RunAlarmShortcutIntent: AppIntent {

    static var title: LocalizedStringResource = "Get Alarm Shortcut via GeoNap"
    static var description = IntentDescription(
        """
        Returns the name of the Shortcut configured on the most recently \
        fired GeoNap alarm that has Run Shortcut on Alarm enabled, or an \
        empty result if nothing is pending (this never throws — wrap "Run \
        Shortcut" in an "If Shortcut Name is not empty" check in a Personal \
        Automation set to "Run Immediately", so every other app-open is a \
        silent no-op).
        """,
        categoryName: "Notify"
    )

    // Runs silently — does not open the app.
    static var openAppWhenRun: Bool = false

    // MARK: - Perform

    func perform() async throws -> some IntentResult & ReturnsValue<RunAlarmShortcutResult> {
        let defaults = UserDefaults.standard
        // Literals directly, not RunShortcutDefaultsKey — avoids the same
        // actor-isolation inference NotifyContactsIntent.perform() sidesteps.
        let nameKey = "runShortcut_pendingName"
        let tsKey   = "runShortcut_pendingFiredAt"

        // Read + clear unconditionally so this is one-shot regardless of what
        // we do with the values below — including the entitlement check just
        // below, so a downgraded-then-re-upgraded user never runs a stale
        // Shortcut queued while they were locked out.
        let name    = defaults.string(forKey: nameKey) ?? ""
        let firedAt = defaults.double(forKey: tsKey)   // 0 if never set
        defaults.removeObject(forKey: nameKey)
        defaults.removeObject(forKey: tsKey)

        // Platinum-tier gate. This is the load-bearing check — Run Shortcut is a
        // Platinum feature (monetization-tier-pricing memory), and this intent is
        // reachable directly from a Shortcuts automation, bypassing any
        // in-app UI lock entirely. AlarmManager.runShortcutIfConfigured also
        // gates so a non-entitled device never queues a name in the first
        // place, but that's defense in depth, not the enforcement point —
        // this guard is. `isPlatinumTier` is `isEntitled(to: .platinum)` — see
        // EntitlementManager.swift's file header for why this currently
        // reads as "always true" in both RELEASE (distribution stays Platinum
        // for everyone until real StoreKit exists) and DEBUG (unless a test
        // or Settings' Tier Simulation section overrides it lower).
        guard EntitlementManager.isEntitled(to: .platinum) else {
            return .result(value: RunAlarmShortcutResult(shortcutName: nil))
        }

        guard Self.shouldRun(shortcutName: name, firedAt: firedAt) else {
            return .result(value: RunAlarmShortcutResult(shortcutName: nil))
        }

        return .result(value: RunAlarmShortcutResult(shortcutName: name))
    }

    /// Whether an alarm with Run Shortcut actually fired at all (`firedAt >
    /// 0`), as opposed to an ordinary app-open with nothing pending
    /// (`firedAt == 0`). No time bound — matches
    /// NotifyContactsIntent.isFresh(firedAt:) as of 2026-07-11.
    static func isFresh(firedAt: TimeInterval) -> Bool {
        firedAt > 0
    }

    /// Whether `perform()` should return the real shortcut name (true) or the
    /// empty sentinel result (false) that keeps the Shortcut's "If Shortcut
    /// Name is not empty" gate closed.
    static func shouldRun(shortcutName: String, firedAt: TimeInterval) -> Bool {
        guard !shortcutName.isEmpty else { return false }
        return isFresh(firedAt: firedAt)
    }
}
