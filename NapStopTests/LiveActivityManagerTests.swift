// Copyright © 2026 Robert Bartis. All rights reserved.

// LiveActivityManagerTests.swift
// Covers the tier-gating decision in LiveActivityManager.start(for:) — added
// alongside the Platinum-tier Live Activity / Dynamic Island countdown feature,
// 2026-07-11 (see LiveActivityManager.swift / GeoAlarmActivityAttributes.swift).
//
// Deliberately narrow scope: this does NOT exercise the real
// Activity<GeoAlarmActivityAttributes>.request(...) call — that requires
// genuine OS-level Live Activity authorization/entitlements that aren't
// present in a plain XCTest host process, the same reason
// RunAlarmShortcutIntent.perform() and NotifyContactsIntent.perform() aren't
// invoked directly by tests either (see AutoSMSFreshnessTests.swift's header).
// What IS deterministically testable without a real device/simulator run is
// the tier gate itself: start(for:) must return false, and must never reach
// ActivityKit at all, below Platinum — that guard clause is pure and doesn't
// depend on anything OS-provided.
//
// NOTE: like the rest of this suite, requires an Xcode build to execute —
// not run in this authoring environment.

import XCTest
@testable import GeoNap

@MainActor
final class LiveActivityManagerTests: XCTestCase {

    override func tearDown() {
        EntitlementManager.testOverride = nil
        super.tearDown()
    }

    private func makeAlarm(name: String = "Test Alarm") -> NapAlarm {
        NapAlarm(name: name, latitude: 36.5073961, longitude: -87.3142547, regionEvent: .onEntry)
    }

    func test_start_freeTier_returnsFalse() {
        EntitlementManager.testOverride = .free
        XCTAssertFalse(LiveActivityManager.shared.start(for: makeAlarm()))
    }

    func test_start_silverTier_returnsFalse() {
        EntitlementManager.testOverride = .silver
        XCTAssertFalse(LiveActivityManager.shared.start(for: makeAlarm()))
    }

    func test_start_goldTier_returnsFalse() {
        EntitlementManager.testOverride = .gold
        XCTAssertFalse(LiveActivityManager.shared.start(for: makeAlarm()))
    }

    // MARK: - Safe no-ops

    func test_end_forAlarmWithNoRunningActivity_doesNotCrash() {
        // Whether or not Platinum tier successfully started a real Activity in
        // this process (environment-dependent, see header), ending an id
        // that was never started must always be a harmless no-op — every
        // AlarmManager call site (stopMonitoring, both fire paths) calls
        // this unconditionally without checking first.
        LiveActivityManager.shared.end(alarmID: UUID())
    }

    func test_endAll_withNothingRunning_doesNotCrash() {
        LiveActivityManager.shared.endAll()
    }

    func test_update_forAlarmWithNoRunningActivity_doesNotCrash() {
        LiveActivityManager.shared.update(alarmID: UUID(), distanceRemaining: 500, etaSeconds: nil)
    }
}
