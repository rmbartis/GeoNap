// GeoAlarmScheduler.swift
// AlarmKit-based alerting layer (iOS 26+).
//
// MIGRATION NOTE — this replaces the legacy alerting engine (local notification +
// looping AVAudioPlayer + background-audio keep-alive + CarPlay repeat
// notifications). The geofence TRIGGER stays in LocationManager / AlarmManager;
// this module only owns PRESENTING the alarm once a region event fires.
//
// AlarmKit advantages over the old engine:
//   • The alert cuts through silent mode and Focus with no Critical Alerts
//     entitlement, so we no longer need the AVAudioPlayer loop / keep-alive
//     session / CarPlay-only audio-repeat workarounds.
//   • The OS draws the full-screen Stop / Snooze lock-screen UI (and Dynamic
//     Island), so AlarmFiringView becomes redundant.
//
// IMPORTANT — naming: AlarmKit ships its own `AlarmManager`, which COLLIDES with
// this app's `AlarmManager` class. Every AlarmKit manager reference below is
// fully qualified as `AlarmKit.AlarmManager` on purpose. Do not "simplify" it.
//
// ⚠️ Must be built in Xcode (no iOS SDK in the authoring environment) and
//    verified ON A REAL DEVICE — in particular: (1) scheduling from the brief
//    background wake-up a geofence grants, and (2) the exact AlarmKit initializer
//    signatures, which shifted between iOS 26.0 and 26.1 (e.g. `stopButton` was
//    deprecated in 26.1). See inline TODOs.

import Foundation
import AlarmKit
import SwiftUI   // Color for tintColor / button colors

/// Metadata attached to every geo-alarm. AlarmKit requires a concrete
/// `AlarmMetadata` type even when empty; the generic can't be inferred without it.
/// Marked `nonisolated` so it satisfies the protocol under Xcode 26's default
/// MainActor isolation.
nonisolated struct GeoAlarmMetadata: AlarmMetadata {
    // Intentionally empty for now. Future: carry stop/arrival context so a Live
    // Activity or custom intent can show richer info.
}

/// Thin async wrapper around `AlarmKit.AlarmManager` for presenting and
/// cancelling geo-triggered alarms. All methods take Sendable primitives (never
/// the SwiftData `NapAlarm` model) so they can be called across actor boundaries.
enum GeoAlarmScheduler {

    /// Default snooze length, in minutes, for the alert's secondary button.
    static let defaultSnoozeMinutes = 10

    // MARK: - Authorization

    /// Ensures AlarmKit is authorized, prompting once if undetermined.
    /// Safe to call repeatedly (e.g. at launch and lazily before each fire).
    @discardableResult
    static func ensureAuthorized() async -> Bool {
        let manager = AlarmKit.AlarmManager.shared
        switch manager.authorizationState {
        case .authorized:
            return true
        case .denied:
            DebugLogger.shared.log("AlarmKit authorization denied", category: "AlarmKit")
            return false
        case .notDetermined:
            do {
                let state = try await manager.requestAuthorization()
                return state == .authorized
            } catch {
                DebugLogger.shared.log("AlarmKit authorization error: \(error.localizedDescription)", category: "AlarmKit")
                return false
            }
        @unknown default:
            return false
        }
    }

    // MARK: - Fire

    /// Presents an alarm that alerts essentially immediately — used the moment a
    /// geofence region event fires. Uses the alarm's own UUID as the AlarmKit id
    /// so it can be cancelled later via `cancel(id:)`.
    ///
    /// - Parameters:
    ///   - id: the NapAlarm's UUID (reused as the AlarmKit alarm id).
    ///   - title: short alarm name shown on the lock screen (keep it brief — the
    ///            compact banner truncates long titles).
    ///   - snoozeMinutes: how long the Snooze (secondary) button postpones the alarm.
    static func fire(id: UUID,
                     title: String,
                     snoozeMinutes: Int = defaultSnoozeMinutes) async {
        guard await ensureAuthorized() else {
            DebugLogger.shared.log("AlarmKit not authorized — alarm '\(title)' not presented", category: "AlarmKit")
            return
        }

        // Stop button. NOTE: `stopButton` was deprecated in iOS 26.1 (Stop became
        // a slide-to-stop gesture). It still compiles and is required by the 26.0
        // initializer, so we keep providing it. TODO(26.1): migrate to the newer
        // AlarmPresentation.Alert initializer once the project drops 26.0 support.
        let stopButton = AlarmButton(
            text: "Stop",
            textColor: .white,
            systemImageName: "stop.fill"
        )
        // Snooze via the secondary button with `.countdown` behavior: AlarmKit
        // re-arms the alarm after `countdownDuration.postAlert` with no app code.
        // (A secondary button WITHOUT a behavior throws at schedule time.)
        let snoozeButton = AlarmButton(
            text: "Snooze",
            textColor: .white,
            systemImageName: "zzz"
        )

        let alert = AlarmPresentation.Alert(
            title: LocalizedStringResource(stringLiteral: title),
            stopButton: stopButton,
            secondaryButton: snoozeButton,
            secondaryButtonBehavior: .countdown
        )

        let attributes = AlarmAttributes<GeoAlarmMetadata>(
            presentation: AlarmPresentation(alert: alert),
            metadata: GeoAlarmMetadata(),
            tintColor: .accentColor
        )

        // Schedule a fixed alarm 1 second out so it alerts right away. (A past or
        // exact-now date can be rejected; +1s is a safe "immediate".)
        // TODO(device): confirm this fires reliably when scheduled from the brief
        // background execution window a CLRegion event grants.
        let configuration = AlarmKit.AlarmManager.AlarmConfiguration(
            schedule: .fixed(Date().addingTimeInterval(1)),
            attributes: attributes,
            // TODO(sound): AlarmKit AlertSound rejects .aiff and reportedly the
            // bundled .wav files may not load; .mp3 works. Using the system default
            // for now — wire custom NotificationSound files in once converted/verified.
            sound: .default,
            countdownDuration: .init(preAlert: nil,
                                     postAlert: TimeInterval(snoozeMinutes * 60))
        )

        do {
            _ = try await AlarmKit.AlarmManager.shared.schedule(id: id, configuration: configuration)
            DebugLogger.shared.log("AlarmKit alarm presented: '\(title)' (id=\(id))", category: "AlarmKit")
        } catch {
            DebugLogger.shared.log("AlarmKit schedule FAILED for '\(title)': \(error.localizedDescription)", category: "AlarmKit")
        }
    }

    // MARK: - Cancel

    /// Cancels a presented/scheduled alarm by id. Call when the user stops or
    /// deletes the alarm, or when a repeating alarm re-arms.
    /// (AlarmKit has no cancel-all; cancel each id individually.)
    static func cancel(id: UUID) {
        do {
            try AlarmKit.AlarmManager.shared.cancel(id: id)
            DebugLogger.shared.log("AlarmKit alarm cancelled (id=\(id))", category: "AlarmKit")
        } catch {
            DebugLogger.shared.log("AlarmKit cancel failed (id=\(id)): \(error.localizedDescription)", category: "AlarmKit")
        }
    }
}
