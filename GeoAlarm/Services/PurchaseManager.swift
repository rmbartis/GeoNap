// Copyright © 2026 Robert Bartis. All rights reserved.

// PurchaseManager.swift
// StoreKit 2 integration — the ONLY file in GeoNap that talks to StoreKit
// directly: loading products, initiating purchases, verifying transactions,
// and listening for out-of-band updates (renewals, Family Sharing grants,
// Ask to Buy approvals, purchases made on another device). Its job ends at
// writing the resolved tier into `EntitlementManager.verifiedTier` — nothing
// else in the app should ever read a `Transaction`, a receipt, or a product
// ID directly. See EntitlementManager.swift's "single point of control"
// header comment for the full policy this file exists to honor.
//
// Product IDs below must match App Store Connect exactly — see
// docs/app-store-connect-phase2-steps.md (Phase 2, items 3 and 5) and the
// live ASC configuration:
//   Silver:   com.rmbartis.GeoNap.silver.annual   (auto-renewable subscription)
//   Gold:     com.rmbartis.GeoNap.gold.annual     (auto-renewable subscription,
//             ranked ABOVE Silver in the "GeoNap Tiers" subscription group,
//             so upgrade/downgrade proration works correctly)
//   Platinum: com.rmbartis.GeoNap.platinum        (non-consumable, one-time)
//
// Item 9 (2026-08-08): this file's entitlement resolution
// (`updateEntitledTier()`) is live. The purchase UI that actually calls
// `purchase(_:)` doesn't exist yet — that's item 10 (the paywall). Until
// then, this only affects EXISTING entitlements (a device that already
// owns something via Sandbox/TestFlight testing); there's no in-app way for
// a user to buy anything yet.

import Combine
import Foundation
import StoreKit

/// Maps GeoNap's App Store Connect product IDs to the tier each one grants.
enum ProductID {
    static let silverAnnual = "com.rmbartis.GeoNap.silver.annual"
    static let goldAnnual   = "com.rmbartis.GeoNap.gold.annual"
    static let platinum     = "com.rmbartis.GeoNap.platinum"

    static let all: [String] = [silverAnnual, goldAnnual, platinum]

    /// Free has no product ID — it's just the absence of any purchase, so
    /// this returns nil rather than a case for it.
    ///
    /// Marked `nonisolated` because this is a pure lookup with no actor
    /// state — under this project's default main-actor isolation it would
    /// otherwise infer @MainActor, which triggered a build warning when
    /// called from PurchaseManager.resolveHighestTier(from:) (itself
    /// `nonisolated` on purpose, so it stays synchronously unit-testable).
    /// (Bob, 2026-08-09)
    nonisolated static func tier(for productID: String) -> AppTier? {
        switch productID {
        case platinum:     return .platinum
        case goldAnnual:   return .gold
        case silverAnnual: return .silver
        default:           return nil
        }
    }
}

enum PurchaseError: Error {
    case failedVerification
    case userCancelled
    case pending
    case unknown
}

@MainActor
final class PurchaseManager: ObservableObject {

    static let shared = PurchaseManager()

    @Published private(set) var products: [Product] = []
    @Published private(set) var purchasedProductIDs: Set<String> = []
    @Published private(set) var isLoadingProducts = false
    /// True once this launch's first `Transaction.currentEntitlements` pass
    /// has completed. The future paywall (item 10) should use this to show
    /// a brief loading state rather than treating "haven't checked yet" the
    /// same as "confirmed owns nothing."
    @Published private(set) var hasCompletedInitialEntitlementCheck = false

    private var transactionListenerTask: Task<Void, Never>?

    private init() {}

    /// Call once at app launch. Starts the long-running `Transaction.updates`
    /// listener (idempotent — a second call won't start a duplicate
    /// listener) and kicks off the first product load + entitlement check.
    func start() {
        if transactionListenerTask == nil {
            transactionListenerTask = Task(priority: .background) { [weak self] in
                await self?.listenForTransactionUpdates()
            }
        }
        Task {
            await loadProducts()
            await updateEntitledTier()
        }
    }

    deinit {
        transactionListenerTask?.cancel()
    }

    // MARK: - Loading products

    /// Fetches the three products' current metadata (localized price,
    /// display name, etc.) from the App Store. Needed by the future paywall
    /// (item 10) to render prices; not required for entitlement resolution
    /// itself, which works from `Transaction.currentEntitlements` alone.
    func loadProducts() async {
        isLoadingProducts = true
        defer { isLoadingProducts = false }
        do {
            products = try await Product.products(for: ProductID.all)
        } catch {
            CrashReporter.record(error, context: "PurchaseManager.loadProducts failed")
            products = []
        }
    }

    // MARK: - Purchasing

    /// Initiates a purchase for `product`. Throws `PurchaseError` on
    /// cancellation, a pending purchase (Ask to Buy), or verification
    /// failure. On success, `EntitlementManager.verifiedTier` has already
    /// been updated before this returns.
    ///
    /// Not called from anywhere yet — the paywall (item 10) is the intended
    /// caller once it exists.
    @discardableResult
    func purchase(_ product: Product) async throws -> Transaction {
        let result = try await product.purchase()

        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            await updateEntitledTier()
            await transaction.finish()
            return transaction
        case .userCancelled:
            throw PurchaseError.userCancelled
        case .pending:
            throw PurchaseError.pending
        @unknown default:
            throw PurchaseError.unknown
        }
    }

    /// Syncs with the App Store and re-checks entitlements — backs the
    /// "Restore Purchases" button Apple requires on the paywall (item 10).
    func restorePurchases() async throws {
        try await AppStore.sync()
        await updateEntitledTier()
    }

    // MARK: - Entitlement resolution

    /// The single place this file writes to EntitlementManager. Walks every
    /// current, verified entitlement — subscriptions AND non-consumables —
    /// and collects the owned product IDs; `resolveHighestTier(from:)` below
    /// does the actual tier-mapping/max logic. Platinum's non-consumable and
    /// an active Gold/Silver subscription aren't mutually exclusive (a
    /// customer could own Platinum with no active subscription, or vice
    /// versa), so this always reflects the best tier currently owned, not
    /// just the most recent purchase.
    func updateEntitledTier() async {
        var owned = await currentEntitlementProductIDs()
        var resolvedTier = Self.resolveHighestTier(from: owned)

        // Cold-launch guard, added 2026-08-24 after a user report: a
        // Platinum purchase silently reverted to Free after a phone
        // restart — with no refund, cancellation, or new purchase
        // involved, at the same moment a separate bug was independently
        // wiping the alarm list (see ModelContainerFactory.swift's
        // history). Same root shape as that bug: `Transaction
        // .currentEntitlements` reads StoreKit's on-device transaction
        // cache, which — like CloudKit — can plausibly come back empty in
        // the first moments after a reboot, before storekitd has finished
        // warming up, not because the entitlement was actually lost.
        // Without this guard, `verifiedTier`'s `didSet` immediately
        // persists the wrongly-downgraded tier back to UserDefaults too,
        // so even the seed for the NEXT cold launch is corrupted — the
        // downgrade sticks instead of self-correcting on the next launch.
        //
        // Only kicks in for the FIRST check of a launch, and only when the
        // fresh result would DOWNGRADE below what's already cached (a
        // brand-new install resolving to .free, or a genuine upgrade,
        // applies immediately with no delay). A later, real revocation —
        // `Transaction.updates` firing for a refund/cancellation, or any
        // later call to this method in the same session — is trusted
        // immediately too, since by then StoreKit has clearly finished
        // warming up.
        if !hasCompletedInitialEntitlementCheck {
            let cachedTier = EntitlementManager.verifiedTier
            let maxAttempts = 3
            var attempt = 1
            while resolvedTier < cachedTier && attempt <= maxAttempts {
                DebugLogger.shared.log("PurchaseManager: cold-launch entitlement check resolved to \(resolvedTier) but cached tier was \(cachedTier) — retry \(attempt)/\(maxAttempts)", category: "Purchase")
                try? await Task.sleep(nanoseconds: 750_000_000)
                owned = await currentEntitlementProductIDs()
                resolvedTier = Self.resolveHighestTier(from: owned)
                attempt += 1
            }
            if resolvedTier < cachedTier {
                DebugLogger.shared.log("PurchaseManager: entitlement check still resolved below cached tier (\(resolvedTier) < \(cachedTier)) after \(maxAttempts) attempts — accepting downgrade", category: "Purchase")
            }
        }

        purchasedProductIDs = owned
        EntitlementManager.verifiedTier = resolvedTier
        hasCompletedInitialEntitlementCheck = true
    }

    /// One pass over `Transaction.currentEntitlements`, collecting verified
    /// product IDs. Split out of `updateEntitledTier()` so the cold-launch
    /// retry loop above can re-run just this part without duplicating it.
    private func currentEntitlementProductIDs() async -> Set<String> {
        var owned: Set<String> = []
        for await result in Transaction.currentEntitlements {
            guard let transaction = try? checkVerified(result) else { continue }
            owned.insert(transaction.productID)
        }
        return owned
    }

    /// Pure tier-resolution logic, split out of `updateEntitledTier()` so it's
    /// unit-testable without mocking StoreKit's `Transaction`/
    /// `VerificationResult` (which have no public initializers). Maps each
    /// owned product ID to the tier it grants via `ProductID.tier(for:)` and
    /// returns the highest; an unrecognized product ID is ignored rather than
    /// treated as an error, since a future product this build doesn't know
    /// about yet should degrade gracefully, not crash or block the rest of
    /// the entitlement check (Bob, 2026-08-09).
    nonisolated static func resolveHighestTier(from productIDs: some Sequence<String>) -> AppTier {
        var highest: AppTier = .free
        for id in productIDs {
            if let tier = ProductID.tier(for: id), tier > highest {
                highest = tier
            }
        }
        return highest
    }

    // MARK: - Transaction updates listener

    /// Long-running loop (started once from `start()`, runs for the life of
    /// the app) that picks up transactions arriving OUTSIDE an explicit
    /// `purchase(_:)` call in this session — a subscription renewal, a
    /// Family Sharing grant/revoke, an Ask to Buy approval landing, or a
    /// purchase made on another device syncing in.
    private func listenForTransactionUpdates() async {
        for await result in Transaction.updates {
            guard let transaction = try? checkVerified(result) else { continue }
            await updateEntitledTier()
            await transaction.finish()
        }
    }

    // MARK: - Verification

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw PurchaseError.failedVerification
        case .verified(let safe):
            return safe
        }
    }
}
