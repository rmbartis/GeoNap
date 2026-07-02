// NotifyContactsIntent.swift
// An AppIntent that retrieves the message body written to UserDefaults when
// the most recent NapAlarm fired, and returns it as a plain String.
//
// Designed for use in a Shortcuts Personal Automation:
//
//   Trigger : App → GeoNap → "Is Opened"   (iOS has no "app received a
//             notification" trigger; "Is Opened" is the only app trigger, so
//             the SMS is sent the next time GeoNap is opened after an alarm)
//   Action 1: "Notify Contacts via NapAlarm"   ← this intent
//             → output: message body String (empty/throws if no FRESH alarm,
//               so opening the app for any other reason sends nothing)
//   Action 2: "Send Message"
//             Message    → "Body" from Action 1
//             Recipients → pick your contacts (configured once at setup)
//   Setting : Run Without Asking  ✓
//
// With that automation in place — and the "I've set up the Shortcuts automation"
// switch enabled in Settings so the in-app compose sheet is suppressed — iOS
// sends the SMS with no compose sheet and no Send tap the next time the user
// opens GeoNap after an alarm fires (within the freshness window).

import AppIntents
import Foundation

// MARK: - UserDefaults keys
//
// Top-level, no type annotation — avoids any actor-isolation inference.

enum AutoNotifyDefaultsKey {
    static let pendingBody = "autoNotify_pendingBody"
    /// Unix time (TimeInterval) when `pendingBody` was last written, i.e. when an
    /// alarm last fired. Used to reject stale bodies so opening the app casually
    /// (long after an alarm) doesn't resend an old message.
    static let pendingBodyTimestamp = "autoNotify_pendingBodyTimestamp"
    /// How recently an alarm must have fired for the Shortcuts automation to send.
    /// Covers the normal gap between the alarm firing and the user opening the app;
    /// beyond this the pending body is treated as stale and ignored.
    static let freshnessWindow: TimeInterval = 15 * 60   // 15 minutes
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
        // Use the literals directly — avoids @MainActor isolation inference
        // that affects AutoNotifyDefaultsKey when accessed from a non-isolated context.
        let key      = "autoNotify_pendingBody"
        let tsKey    = "autoNotify_pendingBodyTimestamp"
        let window: TimeInterval = 15 * 60   // keep in sync with AutoNotifyDefaultsKey.freshnessWindow

        guard let body = defaults.string(forKey: key), !body.isEmpty else {
            throw IntentError.noPendingNotification
        }

        // Freshness guard: only send if an alarm fired within the window. This is
        // what makes the "When GeoNap Is Opened" automation safe — opening the app
        // for any other reason finds a stale (or already-cleared) body and sends
        // nothing. Clear the body either way so it's one-shot per alarm.
        let firedAt = defaults.double(forKey: tsKey)   // 0 if never set
        defaults.removeObject(forKey: key)
        defaults.removeObject(forKey: tsKey)

        guard Self.isFresh(firedAt: firedAt,
                           now: Date().timeIntervalSince1970,
                           window: window) else {
            throw IntentError.noPendingNotification
        }

        return .result(value: body)
    }

    /// Pure freshness decision, extracted so it can be unit-tested without
    /// constructing an AppIntent or invoking `perform()`. A pending body is
    /// "fresh" when an alarm actually fired (`firedAt > 0`) and it did so no
    /// longer than `window` seconds ago. Behaviour-preserving with the inline
    /// guard that previously lived in `perform()`.
    static func isFresh(firedAt: TimeInterval,
                        now: TimeInterval,
                        window: TimeInterval) -> Bool {
        guard firedAt > 0 else { return false }
        return (now - firedAt) <= window
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
