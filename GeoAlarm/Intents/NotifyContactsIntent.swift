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
//             the SMS is sent the next time GeoNap is opened after an alarm —
//             which means this intent runs on EVERY ordinary app-open too,
//             not just the ones following an alarm. See the no-throw note
//             below — that's a direct consequence of this trigger choice.)
//   Action 1: "Notify Contacts via GeoNap"   ← this intent
//             → outputs: "Body" (String) and "Recipients" ([String]) — BOTH
//               EMPTY (never thrown) if there's no fresh alarm, so opening the
//               app for any other reason is a silent no-op
//   Action 2: If  → "Body" is not empty
//               "Send Message"
//                 Message    → "Body" from Action 1
//                 Recipients → "Recipients" from Action 1 (no manual contact
//                              entry — sourced from the alarm's own Auto-Notify
//                              contacts / Auto-Notify Defaults, same as the
//                              in-app compose sheet)
//   Setting : Run Immediately  ✓
//
// With that automation in place — and the "I've set up the Shortcuts automation"
// switch enabled in Settings so the in-app compose sheet is suppressed — iOS
// sends the SMS with no compose sheet and no Send tap the next time the user
// opens GeoNap after an alarm fires, and does nothing (silently) on every
// other open.
//
// Why this intent never throws: it used to throw `IntentError.noPendingNotification`
// whenever there was nothing fresh to send. That felt right in isolation, but
// combined with the "Is Opened" trigger it meant a thrown error — and the
// resulting system "Automation Failed" notification — on nearly every normal
// app-open, since a fresh pending alarm is the rare case, not the common one.
// Returning an empty result instead, with the Shortcut's own "If Body is not
// empty" check gating Send Message, keeps the common case silent.
//
// No time-based staleness cutoff (removed 2026-07-11): this used to reject a
// pending body older than 15 minutes, on the theory that a casual app-open
// long after an alarm shouldn't resend an old message. In practice, GeoNap's
// whole use case is a traveler who is asleep, or busy gathering bags and
// getting off a bus/train, when an alarm fires — a real, legitimate gap
// between firing and the next app-open regularly exceeded 15 minutes and
// caused a genuine send to be silently dropped (see the 2026-07-11 debug-log
// investigation). Because `perform()` already reads-then-clears these keys
// unconditionally on every app-open, dropping the cutoff creates no
// duplicate-send risk — it only means a message can now arrive later than
// it used to, which is preferable to it never arriving. Users are warned
// about this delay (and about the one-pending-message-only limitation below)
// in the in-app Help text. See `help.body.autoNotify` in Localizable.strings.
//
// One-pending-message-only (unchanged): `queueAutoNotify` overwrites the same
// UserDefaults keys every time ANY alarm fires, so if a second alarm fires
// before the user opens the app after the first, the first alarm's message is
// silently replaced, not queued. This is independent of the staleness cutoff
// removed above and is also called out in the Help text.

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
    /// alarm last fired. No longer used to reject stale bodies (see the 2026-07-11
    /// note above) — kept because `isFresh` still needs to distinguish "an alarm
    /// has fired" (> 0) from "no alarm has ever fired" (0, the UserDefaults
    /// default for a missing double), which covers the ordinary-app-open case.
    static let pendingBodyTimestamp = "autoNotify_pendingBodyTimestamp"
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

    // Optional, not just empty-when-absent (Bob — 2026-07-09, ninth pass:
    // found live on-device after Auto-SMS setup was otherwise wired
    // correctly, matching this file's exported "If Body has any value" +
    // "Send Message" structure exactly). Shortcuts' "Has Any Value" check
    // on a @Property means "is this property present at all" — a
    // non-optional String/[String] is ALWAYS present, even when its value
    // is "" / [], so with these declared non-optional the automation's "If
    // Body has any value" gate was structurally incapable of ever
    // evaluating false. That let "Send Message" run on every ordinary
    // app-open with an empty body and no recipients, which Shortcuts can't
    // auto-address, so it fell back to popping open the interactive "New
    // Message" compose sheet instead of silently doing nothing. Making both
    // properties genuinely Optional — nil (not empty) when there's nothing
    // fresh to send — is what makes "Has Any Value" mean what the
    // Shortcut's author actually intends.
    @Property(identifier: "body", title: "Body")
    var body: String?

    @Property(identifier: "recipients", title: "Recipients")
    var recipients: [String]?

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(body ?? "")")
    }

    /// Required by `TransientAppEntity` conformance (Protocol requires
    /// initializer 'init()' with type '()'). Not used directly — always
    /// constructed via `init(body:recipients:)` below, which overwrites both
    /// defaults immediately.
    init() {
        self.body = nil
        self.recipients = nil
    }

    init(body: String?, recipients: [String]?) {
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
        recently triggered GeoNap alarm, or an empty result if there's nothing \
        fresh to send (this never throws — wrap "Send Message" in an "If Body \
        is not empty" check in a Personal Automation set to "Run Immediately", \
        so SMS sends with no compose sheet and no manual contact entry, and \
        every other app-open is a silent no-op).
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

        // Read + clear unconditionally so this is one-shot per alarm regardless
        // of what we do with the values below.
        let body   = defaults.string(forKey: bodyKey) ?? ""
        let phones = defaults.stringArray(forKey: phonesKey) ?? []
        let firedAt = defaults.double(forKey: tsKey)   // 0 if never set
        defaults.removeObject(forKey: bodyKey)
        defaults.removeObject(forKey: phonesKey)
        defaults.removeObject(forKey: tsKey)

        // Nothing to send — this is the common case (every app-open that isn't
        // right after an alarm). Return an empty result rather than throwing:
        // see the file-header note on why throwing here caused an "Automation
        // Failed" notification on ordinary app-opens. The Shortcut's own
        // "If Body is not empty" check makes this a silent no-op. No staleness
        // cutoff — see the 2026-07-11 file-header note: a pending body is sent
        // however long ago it fired, since it's cleared unconditionally above
        // and can therefore never be resent.
        guard Self.shouldNotify(body: body, phones: phones, firedAt: firedAt) else {
            return .result(value: NotifyContactsResult(body: nil, recipients: nil))
        }

        return .result(value: NotifyContactsResult(body: body, recipients: phones))
    }

    /// Whether an alarm has actually fired at all (`firedAt > 0`), as opposed to
    /// this being an ordinary app-open with nothing pending (`firedAt == 0`, the
    /// UserDefaults default for a missing double). No longer time-bounded — see
    /// the 2026-07-11 file-header note on why the old 15-minute cutoff was
    /// dropped.
    static func isFresh(firedAt: TimeInterval) -> Bool {
        firedAt > 0
    }

    /// Whether `perform()` should return the real body/recipients (true) or the
    /// empty sentinel result (false) that keeps the Shortcut's "If Body is not
    /// empty" gate closed. Extracted as a pure function — same rationale as
    /// `isFresh` — so the no-throw redesign (2026-07-09, fixing the
    /// "Automation Failed" banner on every ordinary app-open) has direct test
    /// coverage instead of only being exercised by manually opening the app.
    static func shouldNotify(body: String,
                              phones: [String],
                              firedAt: TimeInterval) -> Bool {
        guard !body.isEmpty, !phones.isEmpty else { return false }
        return isFresh(firedAt: firedAt)
    }
}
