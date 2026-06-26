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
// ⚠️ ENTITLEMENT: in addition to NSAlarmKitUsageDescription, AlarmKit needs the
//    "AlarmKit" capability added in the target's Signing & Capabilities. Some
//    sources report Apple also gates it behind an entitlement request in the
//    Developer portal; without it, the APIs below can throw authorization errors
//    even after the user taps Allow. Verify this in Xcode before assuming a
//    silent failure is a code bug.
enum GeoAlarmScheduler {

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
    ///
    /// - Parameters:
    ///   - soundName: filename of a bundled `.wav` (e.g. "Train Horn.wav") that
    ///     `installBundledSoundsIfNeeded()` copied into Library/Sounds. `nil` for
    ///     system presets (vibrate/default) → the default alarm sound.
    ///   - snoozeMinutes: how long the Snooze button postpones the alarm
    ///     (AlarmKit re-arms after `countdownDuration.postAlert`).
    ///
    /// ⚠️ FIRST-BUILD FIXUP POINTS (can't compile here; verify against the SDK):
    ///   • `secondaryButtonBehavior: .countdown` is the documented snooze mechanism
    ///     (re-arm after postAlert). If the SDK names it `.snooze`, change it.
    ///   • `AlertConfiguration.AlertSound` — some sources reference it bare as
    ///     `AlertSound`. If "cannot find AlertConfiguration", drop the prefix.
    ///   • `sound:` and `countdownDuration:` are extra labeled params on the
    ///     AlarmConfiguration initializer.
    ///   • WAV playback: AlarmKit reliably plays `.caf`/`.mp3`; `.wav` support is
    ///     unconfirmed. If a bundled tone is silent ON DEVICE, convert it to `.caf`
    ///     (and pass that filename) — the rest of the pipeline is unchanged.
    static func fire(id: UUID,
                     title: String,
                     soundName: String? = nil,
                     snoozeMinutes: Int = 10) async {
        guard await ensureAuthorized() else {
            DebugLogger.shared.log("AlarmKit not authorized — alarm '\(title)' not presented", category: "AlarmKit")
            return
        }

        let stopButton = AlarmButton(
            text: "Stop",
            textColor: .white,
            systemImageName: "stop.fill"
        )
        let snoozeButton = AlarmButton(
            text: "Snooze",
            textColor: .white,
            systemImageName: "zzz"
        )

        let alert = AlarmPresentation.Alert(
            title: LocalizedStringResource(stringLiteral: title),
            stopButton: stopButton,
            secondaryButton: snoozeButton,
            secondaryButtonBehavior: .countdown   // re-arms the alarm after postAlert (snooze)
        )

        let attributes = AlarmAttributes<GeoAlarmMetadata>(
            presentation: AlarmPresentation(alert: alert),
            tintColor: .accentColor
        )

        // User-selected sound. A bundled .wav lives in Library/Sounds (installed at
        // launch); system presets fall back to the default alarm sound.
        // (Sound type is the bare AlarmKit `AlertSound`, not `AlertConfiguration.AlertSound`.)
        let alertSound: AlertSound = soundName.map { .named($0) } ?? .default

        // Fixed alarm 1 second out so it alerts right away. (An exact-now or past
        // date can be rejected; +1s is a safe "immediate".) Config type is the
        // NESTED AlarmKit.AlarmManager.AlarmConfiguration; schedule needs its
        // explicit Alarm.Schedule base so `.fixed` resolves. Initializer argument
        // order is countdownDuration → schedule → attributes → sound.
        let schedule: Alarm.Schedule = .fixed(Date().addingTimeInterval(1))
        let configuration = AlarmKit.AlarmManager.AlarmConfiguration(
            countdownDuration: Alarm.CountdownDuration(
                preAlert: nil,
                postAlert: TimeInterval(snoozeMinutes * 60)
            ),
            schedule: schedule,
            attributes: attributes,
            sound: alertSound
        )

        do {
            _ = try await AlarmKit.AlarmManager.shared.schedule(id: id, configuration: configuration)
            DebugLogger.shared.log("AlarmKit alarm presented: '\(title)' sound=\(soundName ?? "default") (id=\(id))", category: "AlarmKit")
        } catch {
            DebugLogger.shared.log("AlarmKit schedule FAILED for '\(title)': \(error.localizedDescription)", category: "AlarmKit")
        }
    }

    // MARK: - Cancel

    /// Cancels a presented/scheduled alarm by id. Call when the user stops or
    /// deletes the alarm, or when a repeating alarm re-arms.
    /// (AlarmKit has no cancel-all; cancel each id individually.)
    ///
    /// `cancel(id:)` is synchronous and throwing in the iOS 26 SDK.
    static func cancel(id: UUID) {
        do {
            try AlarmKit.AlarmManager.shared.cancel(id: id)
            DebugLogger.shared.log("AlarmKit alarm cancelled (id=\(id))", category: "AlarmKit")
        } catch {
            DebugLogger.shared.log("AlarmKit cancel failed (id=\(id)): \(error.localizedDescription)", category: "AlarmKit")
        }
    }
}
