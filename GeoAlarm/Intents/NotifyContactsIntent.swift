// Copyright © 2026 Robert Bartis. All rights reserved.

// NotifyContactsIntent.swift
// An AppIntent that retrieves the message body AND recipient phone numbers
// written to UserDefaults when the most recent GeoNap alarm fired, and returns
// them as a structured result with two named outputs: "Body" and "Recipients".
//
// Designed for use in a Shortcuts Personal Automation:
//
//   Trigger : App → GeoNap → "Is Opened"   (iOS has no "app received a
//             notification" trigger; "Is Opened" is the only app trigger, so
//             the SMS is sent the next time GeoNap is opened after an alarm)
//   Action 1: "Notify Contacts via GeoNap"   ← this intent
//             → outputs: "Body" (String) and "Recipients" ([String]) — empty/
//               throws if no FRESH alarm, so opening the app for any other
//               reason sends nothing
//   Action 2: "Send Message"
//             Message    → "Body" from Action 1
//             Recipients → "Recipients" from Action 1 (no manual contact entry —
//                          sourced from the alarm's own Auto-Notify contacts /
//                          Auto-Notify Defaults, same as the in-app compose sheet)
//   Setting : Run Immediately  ✓
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
    /// Recipient phone numbers for the pending body, written alongside it by
    /// `AlarmManager.queueAutoNotify(for:)`. Sourced from the alarm's own
    /// Auto-Notify contacts (or Auto-Notify Defaults) — the same list used for
    /// the in-app compose-sheet fallback — so Shortcuts never needs a manually
    /// configured, static recipient list.
    static let pendingPhones = "autoNotify_pendingPhones"
    /// Unix time (TimeInterval) when `pendingBody` was last written, i.e. when an
    /// alarm last fired. Used to reject stale bodies so opening the app casually
    /// (long after an alarm) doesn't resend an old message.
    static let pendingBodyTimestamp = "autoNotify_pendingBodyTimestamp"
    /// How recently an alarm must have fired for the Shortcuts automation to send.
    /// Covers the normal gap between the alarm firing and the user opening the app;
    /// beyond this the pending body is treated as stale and ignored.
    static let freshnessWindow: TimeInterval = 15 * 60   // 15 minutes
}

// MARK: - Structured result

/// The output of `NotifyContactsIntent`. Exposes the message text and the
/// recipient phone numbers as two separately-named Shortcuts variables — "Body"
/// and "Recipients" — so a "Send Message" action can bind both its Message and
/// Recipients fields directly to this single action's output, with no manual
/// contact entry required in the Shortcuts editor.
///
/// Conforms to `TransientAppEntity` rather than `AppEntity`/`AppEnum` because
/// this value is a one-shot result of running the intent, not something a user
/// looks up or queries later — `TransientAppEntity` supplies the `id` and
/// `defaultQuery` boilerplate automatically.
struct NotifyContactsResult: TransientAppEntity {

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "GeoNap Notification"

    @Property(identifier: "body", title: "Body")
    var body: String

    @Property(identifier: "recipients", title: "Recipients")
    var recipients: [String]

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(body)")
    }

    /// Required by `TransientAppEntity` conformance (Protocol requires
    /// initializer 'init()' with type '()'). Not used directly — always
    /// constructed via `init(body:recipients:)` below, which overwrites both
    /// defaults immediately.
    init() {
        self.body = ""
        self.recipients = []
    }

    init(body: String, recipients: [String]) {
        self.body = body
        self.recipients = recipients
    }
}

// MARK: - Intent

struct NotifyContactsIntent: AppIntent {

    static var title: LocalizedStringResource = "Notify Contacts via GeoNap"
    static var description = IntentDescription(
        """
        Returns the message body and recipient phone numbers for the most \
        recently triggered GeoNap alarm. Use the "Body" and "Recipients" \
        outputs directly in a "Send Message" action inside a Personal \
        Automation set to "Run Immediately" to send SMS with no compose sheet \
        and no manual contact entry.
        """,
        categoryName: "Notify"
    )

    // Runs silently — does not open the app.
    static var openAppWhenRun: Bool = false

    // MARK: - Perform

    func perform() async throws -> some IntentResult & ReturnsValue<NotifyContactsResult> {
        let defaults = UserDefaults.standard
        // Use the literals directly — avoids @MainActor isolation inference
        // that affects AutoNotifyDefaultsKey when accessed from a non-isolated context.
        let bodyKey   = "autoNotify_pendingBody"
        let phonesKey = "autoNotify_pendingPhones"
        let tsKey     = "autoNotify_pendingBodyTimestamp"
        let window: TimeInterval = 15 * 60   // keep in sync with AutoNotifyDefaultsKey.freshnessWindow

        guard let body = defaults.string(forKey: bodyKey), !body.isEmpty else {
            throw IntentError.noPendingNotification
        }
        let phones = defaults.stringArray(forKey: phonesKey) ?? []

        // Freshness guard: only send if an alarm fired within the window. This is
        // what makes the "When GeoNap Is Opened" automation safe — opening the app
        // for any other reason finds a stale (or already-cleared) body and sends
        // nothing. Clear everything either way so it's one-shot per alarm.
        let firedAt = defaults.double(forKey: tsKey)   // 0 if never set
        defaults.removeObject(forKey: bodyKey)
        defaults.removeObject(forKey: phonesKey)
        defaults.removeObject(forKey: tsKey)

        guard Self.isFresh(firedAt: firedAt,
                           now: Date().timeIntervalSince1970,
                           window: window) else {
            throw IntentError.noPendingNotification
        }

        // No recipients (e.g. the alarm that fired had only email contacts, or
        // none at all) — nothing for Send Message to address, so don't return
        // a result that would silently try to send to no one.
        guard !phones.isEmpty else {
            throw IntentError.noPendingNotification
        }

        return .result(value: NotifyContactsResult(body: body, recipients: phones))
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
