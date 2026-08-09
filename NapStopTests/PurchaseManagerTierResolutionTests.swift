// Copyright © 2026 Robert Bartis. All rights reserved.

// PurchaseManagerTierResolutionTests.swift
// Coverage for PurchaseManager.resolveHighestTier(from:) — the pure
// product-IDs → highest-owned-tier mapping extracted out of
// updateEntitledTier() on 2026-08-09. This is the one piece of
// PurchaseManager's entitlement logic that's actually testable without
// mocking StoreKit's Transaction/VerificationResult types, which have no
// public initializers and can only be produced by a real purchase or a
// local .storekit test session — everything else in PurchaseManager
// (purchase(_:), restorePurchases(), the Transaction.updates listener)
// still has no automated coverage; see docs/app-store-release-checklist.md
// Phase 5 notes for that known gap.
//
// Added alongside a StoreKit Sandbox test pass that surfaced zero existing
// coverage for this file at all (Bob, 2026-08-09) — Silver/Gold/Platinum
// purchases, upgrade/downgrade, and Restore Purchases were all verified
// manually in that pass, but nothing regression-guards the tier-mapping
// logic itself.

import XCTest
@testable import GeoNap

final class PurchaseManagerTierResolutionTests: XCTestCase {

    // MARK: - No entitlements

    func test_noOwnedProducts_resolvesToFree() {
        XCTAssertEqual(PurchaseManager.resolveHighestTier(from: []), .free)
    }

    // MARK: - Single entitlement per tier

    func test_ownsSilverOnly_resolvesToSilver() {
        XCTAssertEqual(
            PurchaseManager.resolveHighestTier(from: [ProductID.silverAnnual]),
            .silver
        )
    }

    func test_ownsGoldOnly_resolvesToGold() {
        XCTAssertEqual(
            PurchaseManager.resolveHighestTier(from: [ProductID.goldAnnual]),
            .gold
        )
    }

    func test_ownsPlatinumOnly_resolvesToPlatinum() {
        XCTAssertEqual(
            PurchaseManager.resolveHighestTier(from: [ProductID.platinum]),
            .platinum
        )
    }

    // MARK: - Multiple simultaneous entitlements

    func test_ownsSilverAndGold_resolvesToHigherGold() {
        // Shouldn't normally happen inside the same subscription group (Gold
        // and Silver are mutually exclusive there), but the resolver must not
        // assume that invariant — it just takes the max of whatever
        // Transaction.currentEntitlements actually reports.
        XCTAssertEqual(
            PurchaseManager.resolveHighestTier(from: [ProductID.silverAnnual, ProductID.goldAnnual]),
            .gold
        )
    }

    func test_ownsSilverAndPlatinum_resolvesToPlatinum() {
        // Platinum (non-consumable) and a subscription are NOT mutually
        // exclusive — a customer can own both. Highest must win regardless
        // of purchase order.
        XCTAssertEqual(
            PurchaseManager.resolveHighestTier(from: [ProductID.silverAnnual, ProductID.platinum]),
            .platinum
        )
    }

    func test_ownsAllThree_resolvesToPlatinum() {
        XCTAssertEqual(
            PurchaseManager.resolveHighestTier(from: [
                ProductID.silverAnnual, ProductID.goldAnnual, ProductID.platinum,
            ]),
            .platinum
        )
    }

    func test_orderOfProductIDsDoesNotAffectResult() {
        let ids: Set<String> = [ProductID.platinum, ProductID.silverAnnual, ProductID.goldAnnual]
        XCTAssertEqual(PurchaseManager.resolveHighestTier(from: ids), .platinum)
        XCTAssertEqual(PurchaseManager.resolveHighestTier(from: Array(ids.reversed())), .platinum)
    }

    // MARK: - Unrecognized product IDs

    func test_unrecognizedProductID_isIgnored_doesNotCrashOrElevateTier() {
        XCTAssertEqual(
            PurchaseManager.resolveHighestTier(from: ["com.rmbartis.GeoNap.some.future.product"]),
            .free,
            "An unmapped product ID must be ignored, not silently granted a tier."
        )
    }

    func test_unrecognizedProductID_mixedWithKnownOne_stillResolvesCorrectly() {
        XCTAssertEqual(
            PurchaseManager.resolveHighestTier(from: [
                "com.rmbartis.GeoNap.some.future.product", ProductID.silverAnnual,
            ]),
            .silver
        )
    }

    func test_duplicateProductIDs_resolvesSameAsSingle() {
        XCTAssertEqual(
            PurchaseManager.resolveHighestTier(from: [ProductID.goldAnnual, ProductID.goldAnnual]),
            .gold
        )
    }
}
