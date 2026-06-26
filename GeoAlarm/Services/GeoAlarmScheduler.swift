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
    /// INCREMENT 1 SCOPE — deliberately minimal to maximize first-build success:
    /// a stop-button-only alert with the default alarm sound and no optional
    /// configuration. Two things are intentionally deferred because sources
    /// disagree on their exact API and they're the most likely compile breakers:
    ///   • Snooze — needs a `secondaryButton` + `secondaryButtonBehavior`, but the
    ///     enum case differs across docs (`.snooze` vs `.countdown`). Add once
    ///     verified against the SDK you build with.
    ///   • Custom sound — `sound:` / `AlertSound.named(...)`; AlarmKit rejects
    ///     .aiff and the bundled .wav files may not load (.mp3 works). Convert and
    ///     wire in later. For now the system default alarm sound plays.
    static func fire(id: UUID, title: String) async {
        guard await ensureAuthorized() else {
            DebugLogger.shared.log("AlarmKit not authorized — alarm '\(title)' not presented", category: "AlarmKit")
            return
        }

        let stopButton = AlarmButton(
            text: "Stop",
            textColor: .white,
            systemImageName: "stop.fill"
        )

        let alert = AlarmPresentation.Alert(
            title: LocalizedStringResource(stringLiteral: title),
            stopButton: stopButton
        )

        let attributes = AlarmAttributes<GeoAlarmMetadata>(
            presentation: AlarmPresentation(alert: alert),
            tintColor: .accentColor
        )

        // Fixed alarm 1 second out so it alerts right away. (An exact-now or past
        // date can be rejected; +1s is a safe "immediate".)
        // TODO(device): confirm this fires reliably when scheduled from the brief
        // background execution window a CLRegion event grants.
        let configuration = AlarmConfiguration(
            schedule: .fixed(Date().addingTimeInterval(1)),
            attributes: attributes
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
    ///
    /// Fire-and-forget on a detached Task: sources disagree on whether
    /// `cancel(id:)` is sync, throwing, and/or async, so `try? await` is used
    /// deliberately — it compiles against all of those shapes (any unused
    /// try/await degrades to a harmless warning, never a build error).
    static func cancel(id: UUID) {
        Task {
            try? await AlarmKit.AlarmManager.shared.cancel(id: id)
            DebugLogger.shared.log("AlarmKit cancel requested (id=\(id))", category: "AlarmKit")
        }
    }
}
