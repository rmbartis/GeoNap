// Copyright © 2026 Robert Bartis. All rights reserved.

// LiveActivityManager.swift
// Owns the Gold-tier Live Activity / Dynamic Island lifecycle — see
// GeoAlarmActivityAttributes.swift for what this is and why it's separate
// from AlarmKit's own built-in Live Activity.
//
// Called from AlarmManager at the two choke points every alarm lifecycle
// transition already funnels through — startMonitoring(_:) / stopMonitoring
// (_:) — plus explicitly at both fire points (fireTimeBased and the
// region-event fire block in handleRegionEvent), so a triggered alarm's
// Activity ends the instant it fires rather than lingering until the next
// stopMonitoring call. That's deliberate belt-and-suspenders: a
// non-repeating distance alarm stays region-registered (and `state ==
// .triggered`, not `.active`) after firing until the user edits/deletes it
// or a repeating alarm re-arms — see AlarmManager.handleRegionEvent's
// comments — so relying on stopMonitoring alone would leave a stale
// countdown Activity showing after the alarm already went off. That's
// exactly the same class of bug already documented for AlarmKit's own
// system Live Activity (see NapStopApp.swift/GeoAlarmScheduler.swift's
// "stale Live Activity" notes) — worth remembering as a pattern, not a
// coincidence.
//
// Every method here is a silent no-op on failure or when gated out (below
// Gold, system Live Activities disabled, etc.) — this is a nice-to-have
// overlay on top of the real alarm-firing mechanism (AlarmKit / region
// monitoring), never a requirement for it. Nothing in here should ever be
// able to affect whether an alarm actually fires.

import Foundation
import ActivityKit

@MainActor
final class LiveActivityManager {

    static let shared = LiveActivityManager()
    private init() {}

    private var activities: [UUID: Activity<GeoAlarmActivityAttributes>] = [:]

    // MARK: - Lifecycle

    /// Starts a Live Activity for `alarm` if: Gold tier (see
    /// EntitlementManager — the single point of control for tier, per the
    /// monetization-tier-pricing memory; this does NOT duplicate that
    /// check, just reacts to it), the system currently allows Live
    /// Activities (the user can disable them in system Settings), and one
    /// isn't already running for this alarm.
    /// Returns true when a Live Activity is now running for this alarm
    /// (either just started, or was already running) — callers use this to
    /// decide whether they need continuous GPS updates on this alarm's
    /// behalf (see AlarmManager.startMonitoring's liveActivityTrackedIDs).
    @discardableResult
    func start(for alarm: NapAlarm) -> Bool {
        guard EntitlementManager.isEntitled(to: .gold) else { return false }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            DebugLogger.shared.log("Live Activity: system authorization disabled — skipped for '\(alarm.name)'", category: "LiveActivity")
            return false
        }
        guard activities[alarm.id] == nil else { return true }   // already running for this alarm

        let attributes = GeoAlarmActivityAttributes(
            alarmID: alarm.id.uuidString,
            alarmName: alarm.name,
            triggerModeRaw: alarm.triggerMode.rawValue,
            regionEventRaw: alarm.regionEvent.rawValue
        )
        let initialState = GeoAlarmActivityAttributes.ContentState(
            distanceRemaining: nil,
            etaSeconds: nil,
            lastUpdated: Date()
        )

        do {
            let activity = try Activity<GeoAlarmActivityAttributes>.request(
                attributes: attributes,
                content: .init(state: initialState, staleDate: nil),
                pushType: nil   // Updated locally from GPS fixes, never via remote push.
            )
            activities[alarm.id] = activity
            DebugLogger.shared.log("Live Activity started for '\(alarm.name)'", category: "LiveActivity")
            return true
        } catch {
            DebugLogger.shared.log("Live Activity request FAILED for '\(alarm.name)': \(error.localizedDescription)", category: "LiveActivity")
            return false
        }
    }

    /// Updates the running Activity's content state, if one exists for this
    /// alarm. A no-op — not an error — when there isn't one, which is the
    /// common case (below Gold, or the system declined to start one), so
    /// every call site can call this unconditionally on every location fix
    /// without checking first.
    func update(alarmID: UUID, distanceRemaining: Double?, etaSeconds: Double?) {
        guard let activity = activities[alarmID] else { return }
        let state = GeoAlarmActivityAttributes.ContentState(
            distanceRemaining: distanceRemaining,
            etaSeconds: etaSeconds,
            lastUpdated: Date()
        )
        Task {
            await activity.update(.init(state: state, staleDate: nil))
        }
    }

    /// Ends the running Activity for `alarmID`, if any. See the type-level
    /// doc comment for why this is called from more than just
    /// stopMonitoring.
    func end(alarmID: UUID) {
        guard let activity = activities.removeValue(forKey: alarmID) else { return }
        Task {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    /// Ends every running Activity. Called from Settings' DEBUG-only Tier
    /// Simulation picker when dialing down below Gold, so a Live Activity
    /// never keeps running for a tier that shouldn't have it.
    ///
    /// TODO(StoreKit): once real purchase/expiry events exist, call this
    /// from wherever a real Gold→lower downgrade is detected too — there is
    /// no such event yet (see EntitlementManager's TODO(StoreKit)).
    func endAll() {
        for (_, activity) in activities {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
        activities.removeAll()
    }
}
