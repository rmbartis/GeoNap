// Copyright © 2026 Robert Bartis. All rights reserved.

// EntitlementManagerTests.swift
// Added 2026-07-11 alongside gating Run Shortcut on Alarm (Platinum tier) inside
// RunAlarmShortcutIntent.perform() and AlarmManager.runShortcutIfConfigured.
// Extended the same day to cover the full AppTier model (Free/Silver/
// Gold/Platinum) once EntitlementManager moved from a Bool isPlatinumTier stub to
// a proper Comparable tier.
//
// `xcodebuild test` builds and runs the test target in a DEBUG configuration,
// so without help `EntitlementManager.currentTier` would always report
// `.platinum` — meaning no locked path could ever be exercised by CI.
// EntitlementManager.testOverride (DEBUG-only) closes that gap: setting it
// forces currentTier to report exactly that tier, regardless of the DEBUG
// default. Every test here resets it to nil in tearDown so one test's
// override can never leak into another.
//
// Policy note: distribution (RELEASE) builds report `.platinum` unconditionally
// as of 2026-07-11 — there's no StoreKit/IAP yet, so locking real users out
// with no purchase flow would just be broken, not a paywall. That means
// these tests exercise the OVERRIDE mechanism and downstream consumers
// (AlarmManager, RunAlarmShortcutIntent's isEntitled check indirectly via
// AlarmManager), not real entitlement enforcement — see the TODO(StoreKit)
// comment on EntitlementManager.swift.

import XCTest
@testable import GeoNap

final class EntitlementManagerTests: XCTestCase {

    override func tearDown() {
        EntitlementManager.testOverride = nil
        super.tearDown()
    }

    // MARK: - Default behavior (no override)

    func test_debugBuildsDefaultToPlatinum() {
        XCTAssertNil(EntitlementManager.testOverride, "Precondition: no override set yet.")
        XCTAssertEqual(EntitlementManager.currentTier, .platinum,
            "DEBUG builds default to Platinum when no override is set — see EntitlementManager.swift.")
    }

    // MARK: - Override forces an exact tier

    func test_override_freeTier() {
        EntitlementManager.testOverride = .free
        XCTAssertEqual(EntitlementManager.currentTier, .free)
    }

    func test_override_silverTier() {
        EntitlementManager.testOverride = .silver
        XCTAssertEqual(EntitlementManager.currentTier, .silver)
    }

    func test_override_goldTier() {
        EntitlementManager.testOverride = .gold
        XCTAssertEqual(EntitlementManager.currentTier, .gold)
    }

    func test_override_platinumTier() {
        EntitlementManager.testOverride = .platinum
        XCTAssertEqual(EntitlementManager.currentTier, .platinum)
    }

    func test_overrideNil_fallsBackToDebugDefault() {
        EntitlementManager.testOverride = .free
        EntitlementManager.testOverride = nil
        XCTAssertEqual(EntitlementManager.currentTier, .platinum,
            "Clearing the override must fall back to the ordinary DEBUG default, not stay stuck on the last override.")
    }

    // MARK: - isEntitled(to:) — additive-tier comparison

    func test_isEntitled_higherCurrentTier_meetsLowerRequirement() {
        EntitlementManager.testOverride = .platinum
        XCTAssertTrue(EntitlementManager.isEntitled(to: .free))
        XCTAssertTrue(EntitlementManager.isEntitled(to: .silver))
        XCTAssertTrue(EntitlementManager.isEntitled(to: .gold))
        XCTAssertTrue(EntitlementManager.isEntitled(to: .platinum))
    }

    func test_isEntitled_lowerCurrentTier_failsHigherRequirement() {
        EntitlementManager.testOverride = .silver
        XCTAssertTrue(EntitlementManager.isEntitled(to: .free))
        XCTAssertTrue(EntitlementManager.isEntitled(to: .silver))
        XCTAssertFalse(EntitlementManager.isEntitled(to: .gold))
        XCTAssertFalse(EntitlementManager.isEntitled(to: .platinum))
    }

    func test_isEntitled_exactMatch_meetsRequirement() {
        EntitlementManager.testOverride = .gold
        XCTAssertTrue(EntitlementManager.isEntitled(to: .gold),
            "A tier meets its own requirement exactly, not just strictly-higher tiers.")
    }

    func test_isPlatinumTier_matchesIsEntitledToPlatinum() {
        for tier in AppTier.allCases {
            EntitlementManager.testOverride = tier
            XCTAssertEqual(EntitlementManager.isPlatinumTier, EntitlementManager.isEntitled(to: .platinum),
                "isPlatinumTier is documented as a convenience alias for isEntitled(to: .platinum) — must never drift from it.")
        }
    }

    // MARK: - AppTier ordering

    func test_appTier_ordersFreeLowestPlatinumHighest() {
        XCTAssertLessThan(AppTier.free, AppTier.silver)
        XCTAssertLessThan(AppTier.silver, AppTier.gold)
        XCTAssertLessThan(AppTier.gold, AppTier.platinum)
    }

    // MARK: - Launch-argument parsing (XCUITest → EntitlementManager.testOverride)

    func test_parseTierLaunchArgument_recognizesEachTierCaseInsensitively() {
        XCTAssertEqual(EntitlementManager.parseTierLaunchArgument(from: ["--uitesting-tier", "free"]), .free)
        XCTAssertEqual(EntitlementManager.parseTierLaunchArgument(from: ["--uitesting-tier", "Silver"]), .silver)
        XCTAssertEqual(EntitlementManager.parseTierLaunchArgument(from: ["--uitesting-tier", "GOLD"]), .gold)
        XCTAssertEqual(EntitlementManager.parseTierLaunchArgument(from: ["--uitesting-tier", "Platinum"]), .platinum)
    }

    func test_parseTierLaunchArgument_missingFlag_returnsNil() {
        XCTAssertNil(EntitlementManager.parseTierLaunchArgument(from: ["--uitesting"]))
        XCTAssertNil(EntitlementManager.parseTierLaunchArgument(from: []))
    }

    func test_parseTierLaunchArgument_unknownValue_returnsNil() {
        XCTAssertNil(EntitlementManager.parseTierLaunchArgument(from: ["--uitesting-tier", "Platinum"]))
    }

    func test_parseTierLaunchArgument_flagWithNoValue_returnsNil() {
        XCTAssertNil(EntitlementManager.parseTierLaunchArgument(from: ["--uitesting-tier"]))
    }
}
