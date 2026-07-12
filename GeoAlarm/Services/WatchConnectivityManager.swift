// Copyright © 2026 Robert Bartis. All rights reserved.

// WatchConnectivityManager.swift
// iOS side: pushes active alarm data to the paired Apple Watch via WCSession.
// Uses applicationContext (background delivery) — no need for the Watch to be
// reachable at the moment of the call; WatchKit delivers the latest context
// the next time the Watch app or complication wakes.
//
// Logging (2026-07-11): all sync/activation/pairing events route through
// DebugLogger (category "Watch") instead of print(), so a user-submitted
// debug log actually shows what happened on the Watch side — previously
// this was invisible outside of Xcode's console. Pairing status specifically
// is logged in two places: once in DebugLogger's session header (a snapshot
// at the moment logging starts) AND every time it actually CHANGES via
// `sessionWatchStateDidChange`, so a pairing/unpairing/app-install event
// mid-session shows up in the log instead of only being knowable from the
// header's stale snapshot.

import Foundation
import WatchConnectivity

@MainActor
final class WatchConnectivityManager: NSObject {

    static let shared = WatchConnectivityManager()

    /// Key used in applicationContext and UserDefaults on both sides.
    static let alarmsKey = "watchAlarms"

    /// Last pairing/install snapshot we logged, used by `logPairingChangeIfNeeded()`
    /// to log only on actual transitions rather than every delegate callback.
    /// `nil` until the first check, so the very first observation always logs.
    private var lastLoggedPairingDescription: String?

    override init() {
        super.init()
        guard WCSession.isSupported() else {
            DebugLogger.shared.log("WCSession not supported on this device", category: "Watch")
            return
        }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    // MARK: - Pairing status

    /// Human-readable snapshot of Watch pairing/app-install state, e.g.
    /// "paired, GeoNap installed". Safe to call at any time, including
    /// before activation completes (WCSession properties simply read as
    /// false until then). Used both in DebugLogger's session header and by
    /// `logPairingChangeIfNeeded()` below.
    var pairingStatusDescription: String {
        guard WCSession.isSupported() else { return "not supported on this device" }
        let session = WCSession.default
        guard session.isPaired else { return "no Watch paired" }
        return session.isWatchAppInstalled ? "paired, GeoNap installed" : "paired, GeoNap not installed"
    }

    /// Logs a "Watch pairing status changed" entry only when the description
    /// actually differs from the last one we logged — called from every
    /// delegate callback where pairing could plausibly have changed
    /// (activation completing, and `sessionWatchStateDidChange`, which is
    /// the WCSession callback that specifically fires on pairing/app-install
    /// transitions) rather than just once at session-header time.
    ///
    /// Deliberately not `private`: the delegate callbacks that call this are
    /// `nonisolated` (WCSessionDelegate's contract) and hop to this MainActor
    /// method via `Task { @MainActor in ... }`, which is inherently async —
    /// not something a synchronous unit test can await deterministically.
    /// WatchConnectivityManagerTests calls this method directly instead, to
    /// exercise the real change-detection/logging logic without the
    /// thread-hop's timing uncertainty.
    func logPairingChangeIfNeeded() {
        let current = pairingStatusDescription
        guard current != lastLoggedPairingDescription else { return }
        lastLoggedPairingDescription = current
        DebugLogger.shared.log("Watch pairing status changed: \(current)", category: "Watch")
    }

    /// Test-only reset hook. `shared` is a singleton reused across the whole
    /// test process, so without this, whichever test happens to run first
    /// "wins" the one-time first-observation log and every test after it
    /// would see `lastLoggedPairingDescription` already populated.
    func resetPairingStateForTesting() {
        lastLoggedPairingDescription = nil
    }

    // MARK: - Push alarms to Watch

    /// Call whenever the alarm list changes (add / update / delete / trigger).
    /// Sends active + triggered alarms; the Watch displays the first entry.
    func updateWatch(with alarms: [NapAlarm]) {
        guard WCSession.isSupported(),
              WCSession.default.activationState == .activated else {
            DebugLogger.shared.log("Watch sync skipped — session not activated (\(pairingStatusDescription))", category: "Watch")
            return
        }

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

        guard let data = try? JSONEncoder().encode(payloads) else {
            DebugLogger.shared.log("Watch sync failed — could not encode \(payloads.count) alarm(s)", category: "Watch")
            return
        }

        do {
            try WCSession.default.updateApplicationContext([Self.alarmsKey: data])
            DebugLogger.shared.log("Watch context updated — \(payloads.count) alarm(s)", category: "Watch")
        } catch {
            DebugLogger.shared.log("Watch context update failed: \(error.localizedDescription)", category: "Watch")
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
        Task { @MainActor in
            if let error {
                DebugLogger.shared.log("WCSession activation error: \(error.localizedDescription)", category: "Watch")
            } else {
                DebugLogger.shared.log("WCSession activated: \(state.rawValue)", category: "Watch")
            }
            // Activation is also the first point pairing state is knowable —
            // make sure it gets logged even if sessionWatchStateDidChange
            // never fires (e.g. state was already stable before activation).
            self.logPairingChangeIfNeeded()
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {
        Task { @MainActor in
            DebugLogger.shared.log("WCSession became inactive", category: "Watch")
        }
    }

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        Task { @MainActor in
            DebugLogger.shared.log("WCSession deactivated — reactivating (paired Watch changed)", category: "Watch")
        }
        // Re-activate after Watch swap (paired Watch changed)
        WCSession.default.activate()
    }

    /// iOS-only WCSessionDelegate callback: fires whenever isPaired,
    /// isWatchAppInstalled, or isComplicationEnabled changes — i.e. exactly
    /// the moments a pairing state actually changes (new Watch paired,
    /// Watch unpaired, GeoNap installed/removed on the Watch). This is the
    /// hook that satisfies "log any time pairing state changes", as
    /// distinct from the one-time snapshot written to the session header.
    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.logPairingChangeIfNeeded()
        }
    }
}
