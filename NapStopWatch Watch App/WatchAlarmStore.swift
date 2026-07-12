// Copyright © 2026 Robert Bartis. All rights reserved.

// WatchAlarmStore.swift
// Receives alarm data from the iPhone via WCSession and persists it locally
// so the complication extension can also read it from the shared App Group.
//
// Also surfaces a proactive alert (haptic + local notification) on the
// Watch itself when an alarm transitions to "triggered" — added 2026-07-11.
// Before this, applicationContext updates were purely silent: they updated
// the store/complication but produced nothing the user would notice unless
// they had NearestAlarmView open at that exact moment. AlarmKit's own alert
// on the iPhone side does NOT mirror to a paired Watch (confirmed by
// tracing the fire path — see GeoAlarmScheduler.swift), so this is the
// Watch's only source of a proactive alert.

import Foundation
import Combine
import WatchConnectivity
import WidgetKit
import UserNotifications
import WatchKit

@MainActor
final class WatchAlarmStore: NSObject, ObservableObject {

    static let shared = WatchAlarmStore()

    @Published private(set) var alarms: [WatchAlarmPayload] = []

    /// The alarm to feature in the complication — first in the list
    /// (iOS side sends them sorted: triggered first, then active).
    var featuredAlarm: WatchAlarmPayload? { alarms.first }
    var activeCount: Int { alarms.count }

    // MARK: - Storage

    /// Use the App Group container so the widget extension can read the same data.
    private static let suiteName = "group.com.rmbartis.NapAlarm"

    /// DELIBERATE DUPLICATE of WatchConnectivityManager.alarmsKey (iOS
    /// target only — not visible here across the target boundary, same
    /// reasoning as WatchAlarmPayload.swift's duplication). Also matches
    /// the literal `storageKey` already hard-coded in
    /// NapStopWatchWidget/NapStopComplication.swift. If this ever changes,
    /// change it in all three places.
    /// `nonisolated` because it's read from didReceiveApplicationContext
    /// below, which runs off the main actor — same fix pattern as
    /// EntitlementManager.TierChangeObserver's `shared`/`init` earlier.
    private nonisolated static let storageKey = "watchAlarms"

    private var defaults: UserDefaults {
        UserDefaults(suiteName: Self.suiteName) ?? .standard
    }

    // MARK: - Init

    override init() {
        super.init()
        loadFromDefaults()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
        UNUserNotificationCenter.current().delegate = self
        requestNotificationAuthorizationIfNeeded()
    }

    // MARK: - Persistence

    private func loadFromDefaults() {
        guard let data = defaults.data(forKey: Self.storageKey),
              let decoded = try? JSONDecoder().decode([WatchAlarmPayload].self, from: data)
        else { return }
        alarms = decoded
    }

    private func persist(_ payloads: [WatchAlarmPayload]) {
        let previous = alarms
        alarms = payloads
        if let data = try? JSONEncoder().encode(payloads) {
            defaults.set(data, forKey: Self.storageKey)
        }
        // Reload all complications so they pick up the new data immediately.
        WidgetCenter.shared.reloadAllTimelines()

        alertForNewlyTriggeredAlarms(previous: previous, current: payloads)
    }

    // MARK: - Proactive alert on new trigger

    /// Compares old vs. new payload snapshots and alerts (haptic + local
    /// notification) for any alarm whose `triggerCount` just went UP.
    ///
    /// Originally this compared `state` (not-triggered → triggered), but
    /// that misses a real-world case: a repeating alarm — or a Simulate
    /// Trigger re-fire — that's already sitting in the "triggered" state
    /// when it fires again. `state` doesn't change in that case, so no
    /// transition is detected even though a genuine new fire happened.
    /// `triggerCount` increments on every single fire regardless of the
    /// alarm's current state, so it's the correct signal to diff against.
    /// Fixed 2026-07-11 after exactly this was observed on a real device
    /// test — see NapStopWatch Watch App/WATCH_SETUP.md.
    ///
    /// Comparing against `previous` — rather than just checking `payloads`
    /// for any triggered entry — is what prevents a re-alert every time the
    /// app relaunches and re-syncs an alarm that was already triggered
    /// before (loadFromDefaults() seeds `alarms` from persisted state
    /// before the first applicationContext of a session ever arrives). An
    /// alarm with no matching entry in `previous` (first-ever sync) is
    /// intentionally NOT alerted for the same reason.
    private func alertForNewlyTriggeredAlarms(previous: [WatchAlarmPayload], current: [WatchAlarmPayload]) {
        let previousCounts = Dictionary(uniqueKeysWithValues: previous.map { ($0.id, $0.triggerCount) })
        let newlyTriggered = current.filter { alarm in
            guard let previousCount = previousCounts[alarm.id] else { return false }
            return alarm.triggerCount > previousCount
        }
        guard !newlyTriggered.isEmpty else { return }

        WKInterfaceDevice.current().play(.notification)

        for alarm in newlyTriggered {
            let content = UNMutableNotificationContent()
            content.title = "GeoNap Alarm"
            content.body = alarm.name
            content.sound = .default
            let request = UNNotificationRequest(
                identifier: "geonap-trigger-\(alarm.id)",
                content: content,
                trigger: nil // nil trigger = deliver immediately
            )
            UNUserNotificationCenter.current().add(request)
        }
    }

    private func requestNotificationAuthorizationIfNeeded() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error {
                print("⌚ Notification authorization error: \(error.localizedDescription)")
            } else {
                print("⌚ Notification authorization granted: \(granted)")
            }
        }
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension WatchAlarmStore: UNUserNotificationCenterDelegate {

    /// Without this, UNUserNotificationCenter suppresses the banner/sound
    /// for any notification delivered while GeoNapWatch is the foreground
    /// app — which is exactly the case Bob hit testing in Simulator with
    /// NearestAlarmView already open. Opting in to .banner/.list/.sound
    /// here is what makes the alert actually show up regardless of whether
    /// the Watch app is currently open. Added 2026-07-11 alongside the
    /// triggerCount fix above — this is a second, independent reason the
    /// notification wasn't visible.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }
}

// MARK: - WCSessionDelegate

extension WatchAlarmStore: WCSessionDelegate {

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith state: WCSessionActivationState,
        error: Error?
    ) {}

    /// Called when iPhone pushes a new applicationContext.
    nonisolated func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        guard let data = applicationContext[Self.storageKey] as? Data,
              let payloads = try? JSONDecoder().decode([WatchAlarmPayload].self, from: data)
        else { return }

        Task { @MainActor in
            self.persist(payloads)
        }
    }
}
