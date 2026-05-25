// WatchAlarmStore.swift
// Receives alarm data from the iPhone via WCSession and persists it locally
// so the complication extension can also read it from the shared App Group.

import Foundation
import WatchConnectivity
import WidgetKit

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
    private static let suiteName = "group.com.rmbartis.GeoAlarm"
    private static let storageKey = WatchConnectivityManager.alarmsKey

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
    }

    // MARK: - Persistence

    private func loadFromDefaults() {
        guard let data = defaults.data(forKey: Self.storageKey),
              let decoded = try? JSONDecoder().decode([WatchAlarmPayload].self, from: data)
        else { return }
        alarms = decoded
    }

    private func persist(_ payloads: [WatchAlarmPayload]) {
        alarms = payloads
        if let data = try? JSONEncoder().encode(payloads) {
            defaults.set(data, forKey: Self.storageKey)
        }
        // Reload all complications so they pick up the new data immediately.
        WidgetCenter.shared.reloadAllTimelines()
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
        guard let data = applicationContext[WatchConnectivityManager.alarmsKey] as? Data,
              let payloads = try? JSONDecoder().decode([WatchAlarmPayload].self, from: data)
        else { return }

        Task { @MainActor in
            self.persist(payloads)
        }
    }
}
