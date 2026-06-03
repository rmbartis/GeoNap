// NotifyContactsIntent.swift
// An AppIntent that retrieves the message body written to UserDefaults when
// the most recent NapAlarm fired, and returns it as a plain String.
//
// Designed for use in a Shortcuts Personal Automation:
//
//   Trigger : When I receive a notification from GeoNap
//   Action 1: "Notify Contacts via NapAlarm"   ← this intent
//             → output: message body String
//   Action 2: "Send Message"
//             Message    → "Body" from Action 1
//             Recipients → pick your contacts (configured once at setup)
//   Setting : Run Without Asking  ✓
//
// With that automation in place, iOS sends the SMS automatically every
// time a NapAlarm fires — no compose sheet, no tap required.

import AppIntents
import Foundation

// MARK: - UserDefaults keys
//
// Top-level, no type annotation — avoids any actor-isolation inference.

enum AutoNotifyDefaultsKey {
    static let pendingBody = "autoNotify_pendingBody"
}

// MARK: - Intent

struct NotifyContactsIntent: AppIntent {

    static var title: LocalizedStringResource = "Notify Contacts via NapAlarm"
    static var description = IntentDescription(
        """
        Returns the message body for the most recently triggered NapAlarm. \
        Use the output with a "Send Message" action in a Personal Automation \
        set to "Run Without Asking" to send SMS without a compose sheet.
        """,
        categoryName: "Notify"
    )

    // Runs silently — does not open the app.
    static var openAppWhenRun: Bool = false

    // MARK: - Perform

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let defaults = UserDefaults.standard
        // Use the literal directly — avoids @MainActor isolation inference
        // that affects AutoNotifyDefaultsKey when accessed from a non-isolated context.
        let key = "autoNotify_pendingBody"

        guard let body = defaults.string(forKey: key), !body.isEmpty else {
            throw IntentError.noPendingNotification
        }

        // Clear so a stale body isn't re-used before the next alarm fires.
        defaults.removeObject(forKey: key)

        return .result(value: body)
    }
}

// MARK: - Errors

extension NotifyContactsIntent {
    enum IntentError: Error, CustomLocalizedStringResourceConvertible {
        case noPendingNotification

        var localizedStringResource: LocalizedStringResource {
            "No pending alarm notification found. The alarm may not have fired yet, or the message has already been sent."
        }
    }
}
