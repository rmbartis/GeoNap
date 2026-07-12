// Copyright © 2026 Robert Bartis. All rights reserved.

// TierGatingFeatureTests.swift
// Per-tier unit tests for the 2026-07-11 full-app tier gating pass — added
// after Run Shortcut on Alarm (Platinum) was the only gated feature, per Bob's
// explicit request for "a CI test suite for each tier control that should
// be enabled ... while controls that should be disabled ... [are]."
//
// Covers, per AppTier where applicable:
//   - AlarmManager.isAtFreeTierLimit / add(alarm:) — Free's 1-active-alarm cap
//   - TriggerMode.allowed(requested:tier:) — Time-based requires Gold+
//   - AlarmManager.queueAutoNotify — Free gets nothing, Silver gets prompted
//     only, Gold+ can additionally go hands-free (mirrors
//     NotifyContactsIntent.perform()'s own Gold gate, which — like
//     RunAlarmShortcutIntent.perform() — is not called directly by any test;
//     see AutoSMSFreshnessTests.swift's header for why)
//
// Deliberately NOT covered here (no testable pure-function surface to hook
// into without a larger refactor — covered by TierGatingUITests.swift
// instead):
//   - SoundPickerSection's per-row lock logic (private to that View)
//   - ContentView's Transit Alarm menu row disabled state (private to that View)
//   - The tierGated() modifier's visual output in general
//
// NOTE: like the rest of this suite, these require an Xcode build + simulator
// run to execute — not run in this authoring environment.

import XCTest
@testable import GeoNap

// MARK: - Free-tier alarm cap

@MainActor
final class FreeTierAlarmCapTests: XCTestCase {

    var sut: AlarmManager!

    override func setUp() {
        super.setUp()
        sut = AlarmManager()
    }

    override func tearDown() {
        EntitlementManager.testOverride = nil
        sut = nil
        super.tearDown()
    }

    private func makeAlarm(name: String = "Amandas") -> NapAlarm {
        NapAlarm(name: name, latitude: 36.5073961, longitude: -87.3142547, regionEvent: .onEntry)
    }

    func test_freeTier_noAlarms_notAtLimit() {
        EntitlementManager.testOverride = .free
        XCTAssertFalse(sut.isAtFreeTierLimit)
    }

    func test_freeTier_oneActiveAlarm_isAtLimit() {
        EntitlementManager.testOverride = .free
        sut.add(alarm: makeAlarm())
        XCTAssertTrue(sut.isAtFreeTierLimit,
            "Free tier's cap is one active alarm — the second must be blocked.")
    }

    func test_freeTier_secondAlarm_insertedInactive() {
        EntitlementManager.testOverride = .free
        sut.add(alarm: makeAlarm(name: "First"))
        sut.add(alarm: makeAlarm(name: "Second"))

        let second = sut.alarms.first { $0.name == "Second" }
        XCTAssertEqual(second?.state, .inactive,
            "A second alarm on Free tier must be saved but inserted inactive, not silently dropped.")
    }

    func test_silverTierAndAbove_noCapApplies() {
        for tier: AppTier in [.silver, .gold, .platinum] {
            EntitlementManager.testOverride = tier
            let localSut = AlarmManager()
            localSut.add(alarm: makeAlarm(name: "One"))
            localSut.add(alarm: makeAlarm(name: "Two"))
            localSut.add(alarm: makeAlarm(name: "Three"))
            XCTAssertFalse(localSut.isAtFreeTierLimit, "\(tier) must not be capped at one alarm.")
            XCTAssertEqual(localSut.alarms.filter { $0.state == .active }.count, 3,
                "\(tier) must allow all three alarms to stay active.")
        }
    }
}

// MARK: - Trigger Mode gate (Time-based requires Gold+)

final class TriggerModeGateTests: XCTestCase {

    func test_distanceRequested_alwaysAllowed_everyTier() {
        for tier in AppTier.allCases {
            XCTAssertEqual(TriggerMode.allowed(requested: .distance, tier: tier), .distance,
                "Distance mode has no tier requirement — must pass through unchanged at \(tier).")
        }
    }

    func test_timeRequested_belowGold_clampsToDistance() {
        for tier: AppTier in [.free, .silver] {
            XCTAssertEqual(TriggerMode.allowed(requested: .time, tier: tier), .distance,
                "\(tier) must not get Time-based trigger mode — clamp to Distance.")
        }
    }

    func test_timeRequested_goldAndAbove_allowed() {
        for tier: AppTier in [.gold, .platinum] {
            XCTAssertEqual(TriggerMode.allowed(requested: .time, tier: tier), .time,
                "\(tier) must be allowed Time-based trigger mode.")
        }
    }
}

// MARK: - Auto-Notify per-tier gate (queueAutoNotify)

@MainActor
final class AutoNotifyTierGateTests: XCTestCase {

    var sut: AlarmManager!

    override func setUp() {
        super.setUp()
        sut = AlarmManager()
        UserDefaults.standard.removeObject(forKey: AutoNotifyDefaultsKey.pendingBody)
        UserDefaults.standard.removeObject(forKey: AutoNotifyDefaultsKey.pendingPhones)
        UserDefaults.standard.removeObject(forKey: AutoNotifyDefaultsKey.pendingBodyTimestamp)
        UserDefaults.standard.removeObject(forKey: AppStorageKey.autoSMSAutomationEnabled)
    }

    override func tearDown() {
        EntitlementManager.testOverride = nil
        UserDefaults.standard.removeObject(forKey: AutoNotifyDefaultsKey.pendingBody)
        UserDefaults.standard.removeObject(forKey: AutoNotifyDefaultsKey.pendingPhones)
        UserDefaults.standard.removeObject(forKey: AutoNotifyDefaultsKey.pendingBodyTimestamp)
        UserDefaults.standard.removeObject(forKey: AppStorageKey.autoSMSAutomationEnabled)
        sut = nil
        super.tearDown()
    }

    private func makeNotifyAlarm() -> NapAlarm {
        NapAlarm(name: "Amandas", latitude: 36.5073961, longitude: -87.3142547,
                 regionEvent: .onEntry,
                 notifyContact: true,
                 notifyContactsJSON: [NotifyContact(name: "Bob", value: "+15551234567")].toJSON())
    }

    func test_freeTier_noContactNotify_nothingQueued() {
        EntitlementManager.testOverride = .free
        sut.add(alarm: makeNotifyAlarm())
        sut.simulateRegionEntered(regionID: sut.alarms.first!.id.uuidString)

        XCTAssertNil(sut.pendingContactMessage, "Free tier must not queue a compose-sheet message.")
        XCTAssertNil(UserDefaults.standard.string(forKey: AutoNotifyDefaultsKey.pendingBody),
            "Free tier must not write pending body/phones for the Shortcuts automation either.")
    }

    func test_silverTier_promptedComposeSheet_queued() {
        EntitlementManager.testOverride = .silver
        sut.add(alarm: makeNotifyAlarm())
        sut.simulateRegionEntered(regionID: sut.alarms.first!.id.uuidString)

        XCTAssertNotNil(sut.pendingContactMessage, "Silver tier must queue the prompted compose sheet.")
    }

    func test_silverTier_handsFreeToggleTrue_stillPromptsAndDoesNotSuppress() {
        // Defense in depth: even if autoSMSAutomationEnabled is somehow true
        // on a Silver-tier device (stale value from a simulated downgrade
        // — the toggle itself is tierGated(minimumTier: .gold) in
        // SettingsView, so this shouldn't happen via normal use), Silver
        // must still fall back to the compose sheet rather than silently
        // suppressing it with nothing to replace it.
        EntitlementManager.testOverride = .silver
        UserDefaults.standard.set(true, forKey: AppStorageKey.autoSMSAutomationEnabled)
        sut.add(alarm: makeNotifyAlarm())
        sut.simulateRegionEntered(regionID: sut.alarms.first!.id.uuidString)

        XCTAssertNotNil(sut.pendingContactMessage,
            "Silver tier must never suppress the compose sheet, even if the hands-free flag is stale-true.")
    }

    func test_goldTier_handsFreeToggleTrue_suppressesComposeSheet() {
        EntitlementManager.testOverride = .gold
        UserDefaults.standard.set(true, forKey: AppStorageKey.autoSMSAutomationEnabled)
        sut.add(alarm: makeNotifyAlarm())
        sut.simulateRegionEntered(regionID: sut.alarms.first!.id.uuidString)

        XCTAssertNil(sut.pendingContactMessage,
            "Gold tier with hands-free enabled must suppress the compose sheet — the Shortcuts automation handles delivery instead.")
        XCTAssertEqual(UserDefaults.standard.string(forKey: AutoNotifyDefaultsKey.pendingBody)?.isEmpty, false,
            "The pending body must still be written for NotifyContactsIntent to pick up.")
    }

    func test_goldTier_handsFreeToggleFalse_stillPrompts() {
        EntitlementManager.testOverride = .gold
        UserDefaults.standard.set(false, forKey: AppStorageKey.autoSMSAutomationEnabled)
        sut.add(alarm: makeNotifyAlarm())
        sut.simulateRegionEntered(regionID: sut.alarms.first!.id.uuidString)

        XCTAssertNotNil(sut.pendingContactMessage,
            "Gold tier with hands-free OFF must still use the prompted compose sheet.")
    }

    func test_platinumTier_handsFreeToggleTrue_suppressesComposeSheet() {
        EntitlementManager.testOverride = .platinum
        UserDefaults.standard.set(true, forKey: AppStorageKey.autoSMSAutomationEnabled)
        sut.add(alarm: makeNotifyAlarm())
        sut.simulateRegionEntered(regionID: sut.alarms.first!.id.uuidString)

        XCTAssertNil(sut.pendingContactMessage, "Platinum includes Gold's hands-free capability.")
    }
}
