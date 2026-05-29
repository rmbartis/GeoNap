// WatchConnectivityManager.swift
// iOS side: pushes active alarm data to the paired Apple Watch via WCSession.
// Uses applicationContext (background delivery) — no need for the Watch to be
// reachable at the moment of the call; WatchKit delivers the latest context
// the next time the Watch app or complication wakes.

import Foundation
import WatchConnectivity

@MainActor
final class WatchConnectivityManager: NSObject {

    static let shared = WatchConnectivityManager()

    /// Key used in applicationContext and UserDefaults on both sides.
    static let alarmsKey = "watchAlarms"

    override init() {
        super.init()
        guard WCSession.isSupported() else {
            print("⌚ WCSession not supported on this device")
            return
        }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    // MARK: - Push alarms to Watch

    /// Call whenever the alarm list changes (add / update / delete / trigger).
    /// Sends active + triggered alarms; the Watch displays the first entry.
    func updateWatch(with alarms: [NapAlarm]) {
        guard WCSession.isSupported(),
              WCSession.default.activationState == .activated else { return }

        let payloads = alarms
            .filter { $0.isActive || $0.state == .triggered }
            .map { a in
                WatchAlarmPayload(
                    id: a.id.uuidString,
                    name: a.name,
                    regionEvent: a.regionEvent.rawValue,
                    radius: a.radius,
                    state: a.stateRaw,
                    triggerCount: a.triggerCount
                )
            }

        guard let data = try? JSONEncoder().encode(payloads) else { return }

        do {
            try WCSession.default.updateApplicationContext([Self.alarmsKey: data])
            print("⌚ Watch context updated — \(payloads.count) alarm(s)")
        } catch {
            print("⌚ Watch context update failed: \(error.localizedDescription)")
        }
    }
}

// MARK: - WCSessionDelegate (iOS requires three methods)

extension WatchConnectivityManager: WCSessionDelegate {

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith state: WCSessionActivationState,
        error: Error?
    ) {
        if let error { print("⌚ WCSession activation error: \(error.localizedDescription)") }
        else { print("⌚ WCSession activated: \(state.rawValue)") }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        // Re-activate after Watch swap (paired Watch changed)
        WCSession.default.activate()
    }
}
