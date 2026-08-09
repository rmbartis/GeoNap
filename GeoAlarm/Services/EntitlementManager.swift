// Copyright © 2026 Robert Bartis. All rights reserved.

// EntitlementManager.swift
// Single source of truth for "which tier is this device entitled to."
//
// ═══════════════════════════════════════════════════════════════════════
// THE SINGLE POINT OF CONTROL (Bob, 2026-07-11 — read before adding ANY
// new tier check anywhere in this codebase):
//
// `EntitlementManager.currentTier` (and its `isEntitled(to:)` wrapper) is
// the ONLY place in GeoNap that decides which tier a device has. Every
// gated feature — Run Shortcut, Auto-Notify, Trigger Mode, Transit Alarms,
// GTFS caching, Auto-SMS hands-free, Calendar Scanning, the Free-tier
// alarm cap, the Sound library — calls through this one property/function,
// nothing else. This is deliberate and load-bearing, not incidental:
//   - As of 2026-08-08 (item 9), real StoreKit/IAP is wired in:
//     `PurchaseManager` is the ONLY file that talks to StoreKit directly
//     (loads products, initiates purchases, verifies transactions, listens
//     for `Transaction.updates`), and its job ends at writing the result
//     into `EntitlementManager.verifiedTier` — nothing else reads a
//     `Transaction`, receipt, or product ID directly. Apple's own purchase
//     gate and this app's testing/simulation gate are the SAME control
//     point — `testOverride` (DEBUG-only) just short-circuits the exact
//     same `currentTier` property that `verifiedTier` populates in RELEASE;
//     it is not a parallel or bypassable mechanism.
//   - If you're about to add a new gated feature and find yourself writing
//     `UserDefaults.standard.bool(forKey: AppStorageKey.platinumTierUnlocked)`
//     or any other independent "am I entitled" check, stop — call
//     `EntitlementManager.isEntitled(to:)` instead. A second control point
//     is exactly the loophole StoreKit review (and simple bugs) will find.
//   - Verified 2026-07-11 (still true after the 2026-08-08 StoreKit wiring):
//     grepped the whole target for "StoreKit", "platinumTierUnlocked", and
//     "isEntitled"/"currentTier"/"AppTier." — every real usage funnels
//     through this file. `platinumTierUnlocked` (AppSettings.swift) is
//     superseded dead weight now — see its doc comment — the real writer
//     landed as a new key, `AppStorageKey.verifiedTierRawValue`, since a
//     single Bool can't represent 4 tiers.
// ═══════════════════════════════════════════════════════════════════════
//
// GeoNap's monetization plan (Free/Silver/Gold/Platinum — see the
// monetization-tier-pricing project memory, tagged in git as
// pre-apple-store-and-pricing-tier-support) now has a real StoreKit 2
// implementation (PurchaseManager.swift, added 2026-08-08 — see git tag
// pre-app-store-entitlement-changes for the last commit before this
// landed). This type is the one place gated features check, and RELEASE
// now reflects real entitlements instead of a stub.
//
// Policy as of 2026-08-08 (Bob):
//   - RELEASE (including TestFlight, which archives Release): reports
//     `verifiedTier` — the highest tier PurchaseManager has verified via
//     `Transaction.currentEntitlements`, defaulting to `.free` for a device
//     with no purchase history. `verifiedTier` is seeded at process-launch
//     from its last known value in UserDefaults (`AppStorageKey
//     .verifiedTierRawValue`) so a cold launch doesn't show a false "no
//     entitlement" flash for an existing subscriber before PurchaseManager's
//     async StoreKit check completes a moment later.
//   - DEBUG (Xcode → device/simulator, and `xcodebuild test`): unchanged —
//     `testOverride` if set, else `.platinum` — so ordinary local
//     development still sees every feature unlocked unless a test or the
//     Settings "Tier Simulation" section deliberately dials it down.
//     PurchaseManager still runs and updates `verifiedTier` in DEBUG builds
//     too (so a StoreKit Configuration File test — item 12 — exercises the
//     real code path end to end and you can inspect `verifiedTier` directly
//     if you want to confirm it), but `currentTier` itself ignores
//     `verifiedTier` entirely in DEBUG (its fallback is always `.platinum`,
//     never `verifiedTier`) — this is an intentional carry-over of the
//     pre-existing "DEBUG always looks unlocked" convenience, not an
//     oversight. Real end-to-end "does a purchase actually unlock the
//     feature" testing happens on a RELEASE-config build (TestFlight, or a
//     manually Release-configured local run).
// nonisolated throughout (added 2026-07-11, fixing a Swift 6 build warning):
// both AppTier and EntitlementManager must be callable from RunAlarmShortcutIntent
// .perform() and NotifyContactsIntent.perform(), which run OUTSIDE the main
// actor (AppIntents' perform() is not MainActor-isolated by default). This
// project's default actor isolation setting infers @MainActor onto ordinary
// static members unless told otherwise, which made `EntitlementManager
// .isEntitled(to:)` main-actor-isolated and produced: "Main actor-isolated
// static method 'isEntitled(to:)' cannot be called from outside of the
// actor; this is an error in the Swift 6 language mode." Marked every static
// member individually (rather than the type declarations themselves, to
// stay on syntax that's valid regardless of exact Swift/Xcode version) —
// this is correct, not a workaround: neither type touches UI or any other
// actor-isolated state. `testOverride` is the one piece of shared mutable
// state, marked `nonisolated(unsafe)` since it's DEBUG-only, single-value,
// low-contention (set once by a test's setUp/tearDown, a Settings picker
// change, or one launch-time read — never concurrently written from
// multiple places at once in practice).
import Combine
import Foundation

/// Notifies every SwiftUI view using `.tierGated(minimumTier:)` whenever the
/// device's tier changes, so gated controls re-render immediately —
/// regardless of whether the control that changed the tier (Settings' Tier
/// Simulation picker in DEBUG, or a real purchase/restore/renewal completing
/// in any build) lives on a different screen or the SAME screen as the gated
/// control. Plain SwiftUI view identity/re-render rules only guarantee a
/// fresh render when NAVIGATING to a screen after the tier changed
/// elsewhere — they do nothing for a gated control sitting on the very
/// screen where the tier just changed, which is exactly the bug this fixes
/// (see monetization-tier-pricing memory: the Auto-SMS hands-free toggle,
/// Calendar Scanning row, and GTFS cache toggle all live in
/// SettingsView.swift alongside the Tier Simulation picker itself, and
/// stayed stuck showing the wrong enabled/disabled state until this was
/// added).
///
/// Originally DEBUG-only (RELEASE used to hardcode `.platinum` for
/// everyone, so tier never changed at runtime there). As of the real
/// StoreKit integration (2026-08-08, item 9), RELEASE tier CAN change at
/// runtime too — `PurchaseManager` calls `EntitlementManager.verifiedTier =`
/// after a purchase, a restore, or an out-of-band `Transaction.updates`
/// event (renewal, Family Sharing grant, Ask to Buy approval) — so this type
/// and `TierGatedModifier.swift`'s observation of it are both unconditional
/// now, not `#if DEBUG`.
final class TierChangeObserver: ObservableObject {
    // nonisolated (added after a build failure): this project's default
    // actor isolation setting infers @MainActor onto ordinary members the
    // same way it did for AppTier/EntitlementManager (see the file-header
    // note above) — including `shared` and `notifyChange()` here, since
    // neither was marked otherwise. That broke the call from
    // EntitlementManager.testOverride's `didSet`, which runs in a
    // `nonisolated(unsafe)` context (two errors: "'shared' can not be
    // referenced from a nonisolated context" and "Call to main
    // actor-isolated instance method 'notifyChange()'"). Marked both
    // `nonisolated`, consistent with the rest of this file. `objectWillChange`
    // itself (Combine's synthesized default for ObservableObject) is
    // unaffected — it's supplied by Combine's own protocol extension, not a
    // declaration in this file, so it isn't subject to this project's
    // default-isolation inference and stays callable from a nonisolated
    // context.
    nonisolated static let shared = TierChangeObserver()
    private nonisolated init() {}

    /// Always publishes on the main thread — `objectWillChange.send()` is a
    /// SwiftUI/Combine contract that expects that, and both `testOverride`
    /// and `verifiedTier` could in principle be set from a background thread
    /// (an XCTest running off-main, or PurchaseManager's transaction
    /// listener task), even though the most common real call sites — the
    /// Settings picker, NapStopApp.init()'s launch-argument parsing — are
    /// main-thread.
    nonisolated func notifyChange() {
        if Thread.isMainThread {
            objectWillChange.send()
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.objectWillChange.send()
            }
        }
    }
}

enum AppTier: Int, Comparable, CaseIterable, Hashable, CustomStringConvertible {
    case free = 0
    case silver = 1
    case gold = 2
    case platinum = 3

    nonisolated static func < (lhs: AppTier, rhs: AppTier) -> Bool { lhs.rawValue < rhs.rawValue }

    nonisolated var description: String {
        switch self {
        case .free:     return "Free"
        case .silver: return "Silver"
        case .gold:   return "Gold"
        case .platinum:     return "Platinum"
        }
    }
}

enum EntitlementManager {

    #if DEBUG
    /// Test/QA override. When non-nil, short-circuits the `.platinum` DEBUG
    /// default below with this exact tier. Three callers:
    ///   - XCTest cases set this to exercise a specific tier deterministically
    ///     (see EntitlementManagerTests.swift, RunAlarmShortcutTests.swift).
    ///     Reset to nil in tearDown().
    ///   - The "Tier Simulation" section in SettingsView (DEBUG-only) sets
    ///     this from a Settings picker, so Bob can see the locked-feature UX
    ///     on a simulator/device without hand-editing this file and
    ///     rebuilding.
    ///   - NapStopApp.init() sets this from a `--uitesting-tier <name>`
    ///     launch argument, so XCUITest (which runs as a separate process
    ///     and can't call Swift APIs directly) can select a tier before a UI
    ///     test's assertions run. See parseTierLaunchArgument(from:) below.
    /// Compiled out entirely in RELEASE — see the #if DEBUG guard around
    /// this whole block — so there's no code path in a shipped build that
    /// could read or set it, however it's exposed. `nonisolated(unsafe)` —
    /// see the file-header note above for why this mutable shared state is
    /// nonisolated without real synchronization, as an accepted tradeoff.
    ///
    /// `didSet` notifies `TierChangeObserver` (below) on every assignment —
    /// not just from the Settings picker — so any SwiftUI view using
    /// `.tierGated(minimumTier:)` re-renders immediately regardless of
    /// which screen changed the tier. Added 2026-07-11 after the first fix
    /// attempt (a `.id(simulatedTier)` on SettingsView's Form) turned out
    /// insufficient — see monetization-tier-pricing memory for the full
    /// story of why relying on a Form's identity change wasn't the right
    /// mechanism.
    nonisolated(unsafe) static var testOverride: AppTier? {
        didSet { TierChangeObserver.shared.notifyChange() }
    }
    #endif

    /// The real, StoreKit-verified tier — the highest tier PurchaseManager
    /// has confirmed via `Transaction.currentEntitlements`, or `.free` for a
    /// device with no purchase history. This is what RELEASE's
    /// `currentTier` reports (see below).
    ///
    /// Seeded synchronously from its last known value in UserDefaults
    /// (`AppStorageKey.verifiedTierRawValue`) rather than starting at
    /// `.free` every launch — PurchaseManager's real StoreKit check is
    /// async and takes a moment even though it's normally fast, and without
    /// this seed an existing subscriber would see every gated feature
    /// flash locked for that brief window on every cold launch, including
    /// offline. `didSet` writes the fresh value back to UserDefaults (so the
    /// NEXT cold launch has an up-to-date seed) and notifies
    /// `TierChangeObserver` so any visible `.tierGated` control re-renders
    /// immediately — the same mechanism `testOverride` already used, now
    /// shared by the real entitlement path too.
    ///
    /// `nonisolated(unsafe)`, matching `testOverride` above: PurchaseManager
    /// writes this from `@MainActor` call sites in practice (its transaction
    /// listener loop and its `@MainActor` class), but `currentTier` must
    /// stay callable from non-MainActor contexts (App Intents' `perform()`),
    /// so the property itself can't be actor-isolated.
    nonisolated(unsafe) static var verifiedTier: AppTier = {
        let raw = UserDefaults.standard.integer(forKey: AppStorageKey.verifiedTierRawValue)
        return AppTier(rawValue: raw) ?? .free
    }() {
        didSet {
            UserDefaults.standard.set(verifiedTier.rawValue, forKey: AppStorageKey.verifiedTierRawValue)
            TierChangeObserver.shared.notifyChange()
        }
    }

    nonisolated static var currentTier: AppTier {
        #if DEBUG
        return testOverride ?? .platinum
        #else
        return verifiedTier
        #endif
    }

    /// True when the current tier is `tier` or higher — tiers are additive
    /// (Platinum includes everything Gold includes, etc.), so this is a
    /// `>=` comparison against `AppTier`'s raw-value ordering, not equality.
    nonisolated static func isEntitled(to tier: AppTier) -> Bool {
        currentTier >= tier
    }

    /// Convenience for the one gate that exists today (Run Shortcut on
    /// Alarm). Equivalent to `isEntitled(to: .platinum)`. New gates against a
    /// different tier should call `isEntitled(to:)` directly so the call
    /// site documents which tier it requires.
    nonisolated static var isPlatinumTier: Bool { isEntitled(to: .platinum) }

    #if DEBUG
    /// Parses a `--uitesting-tier <name>` pair out of launch arguments
    /// (case-insensitive tier name — "free", "Silver", "PLATINUM", etc.).
    /// Returns nil if the flag isn't present or the value doesn't match a
    /// known tier, in which case the caller should leave `testOverride`
    /// untouched (falls back to the ordinary `.platinum` DEBUG default).
    nonisolated static func parseTierLaunchArgument(from arguments: [String]) -> AppTier? {
        guard let flagIndex = arguments.firstIndex(of: "--uitesting-tier"),
              arguments.indices.contains(flagIndex + 1) else { return nil }
        let raw = arguments[flagIndex + 1].lowercased()
        return AppTier.allCases.first { $0.description.lowercased() == raw }
    }
    #endif
}
