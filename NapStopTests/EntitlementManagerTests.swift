// Copyright © 2026 Robert Bartis. All rights reserved.

// EntitlementManagerTests.swift
// Added 2026-07-11 alongside gating Run Shortcut on Alarm (Gold tier) inside
// RunAlarmShortcutIntent.perform() and AlarmManager.runShortcutIfConfigured.
// Extended the same day to cover the full AppTier model (Free/Standard/
// Silver/Gold) once EntitlementManager moved from a Bool isGoldTier stub to
// a proper Comparable tier.
//
// `xcodebuild test` builds and runs the test target in a DEBUG configuration,
// so without help `EntitlementManager.currentTier` would always report
// `.gold` — meaning no locked path could ever be exercised by CI.
// EntitlementManager.testOverride (DEBUG-only) closes that gap: setting it
// forces currentTier to report exactly that tier, regardless of the DEBUG
// default. Every test here resets it to nil in tearDown so one test's
// override can never leak into another.
//
// Policy note: distribution (RELEASE) builds report `.gold` unconditionally
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

    func test_debugBuildsDefaultToGold() {
        XCTAssertNil(EntitlementManager.testOverride, "Precondition: no override set yet.")
        XCTAssertEqual(EntitlementManager.currentTier, .gold,
            "DEBUG builds default to Gold when no override is set — see EntitlementManager.swift.")
    }

    // MARK: - Override forces an exact tier

    func test_override_freeTier() {
        EntitlementManager.testOverride = .free
        XCTAssertEqual(EntitlementManager.currentTier, .free)
    }

    func test_override_standardTier() {
        EntitlementManager.testOverride = .standard
        XCTAssertEqual(EntitlementManager.currentTier, .standard)
    }

    func test_override_silverTier() {
        EntitlementManager.testOverride = .silver
        XCTAssertEqual(EntitlementManager.currentTier, .silver)
    }

    func test_override_goldTier() {
        EntitlementManager.testOverride = .gold
        XCTAssertEqual(EntitlementManager.currentTier, .gold)
    }

    func test_overrideNil_fallsBackToDebugDefault() {
        EntitlementManager.testOverride = .free
        EntitlementManager.testOverride = nil
        XCTAssertEqual(EntitlementManager.currentTier, .gold,
            "Clearing the override must fall back to the ordinary DEBUG default, not stay stuck on the last override.")
    }

    // MARK: - isEntitled(to:) — additive-tier comparison

    func test_isEntitled_higherCurrentTier_meetsLowerRequirement() {
        EntitlementManager.testOverride = .gold
        XCTAssertTrue(EntitlementManager.isEntitled(to: .free))
        XCTAssertTrue(EntitlementManager.isEntitled(to: .standard))
        XCTAssertTrue(EntitlementManager.isEntitled(to: .silver))
        XCTAssertTrue(EntitlementManager.isEntitled(to: .gold))
    }

    func test_isEntitled_lowerCurrentTier_failsHigherRequirement() {
        EntitlementManager.testOverride = .standard
        XCTAssertTrue(EntitlementManager.isEntitled(to: .free))
        XCTAssertTrue(EntitlementManager.isEntitled(to: .standard))
        XCTAssertFalse(EntitlementManager.isEntitled(to: .silver))
        XCTAssertFalse(EntitlementManager.isEntitled(to: .gold))
    }

    func test_isEntitled_exactMatch_meetsRequirement() {
        EntitlementManager.testOverride = .silver
        XCTAssertTrue(EntitlementManager.isEntitled(to: .silver),
            "A tier meets its own requirement exactly, not just strictly-higher tiers.")
    }

    func test_isGoldTier_matchesIsEntitledToGold() {
        for tier in AppTier.allCases {
            EntitlementManager.testOverride = tier
            XCTAssertEqual(EntitlementManager.isGoldTier, EntitlementManager.isEntitled(to: .gold),
                "isGoldTier is documented as a convenience alias for isEntitled(to: .gold) — must never drift from it.")
        }
    }

    // MARK: - AppTier ordering

    func test_appTier_ordersFreeLowestGoldHighest() {
        XCTAssertLessThan(AppTier.free, AppTier.standard)
        XCTAssertLessThan(AppTier.standard, AppTier.silver)
        XCTAssertLessThan(AppTier.silver, AppTier.gold)
    }

    // MARK: - Launch-argument parsing (XCUITest → EntitlementManager.testOverride)

    func test_parseTierLaunchArgument_recognizesEachTierCaseInsensitively() {
        XCTAssertEqual(EntitlementManager.parseTierLaunchArgument(from: ["--uitesting-tier", "free"]), .free)
        XCTAssertEqual(EntitlementManager.parseTierLaunchArgument(from: ["--uitesting-tier", "Standard"]), .standard)
        XCTAssertEqual(EntitlementManager.parseTierLaunchArgument(from: ["--uitesting-tier", "SILVER"]), .silver)
        XCTAssertEqual(EntitlementManager.parseTierLaunchArgument(from: ["--uitesting-tier", "Gold"]), .gold)
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
