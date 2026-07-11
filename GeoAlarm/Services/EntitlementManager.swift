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
//   - When real StoreKit/IAP lands, `Transaction.currentEntitlements` (or
//     whatever the actual purchase-verification call ends up being) gets
//     wired into `currentTier`'s RELEASE branch — and ONLY that branch.
//     No other file should ever read a receipt, a product ID, or
//     `AppStorageKey.goldTierUnlocked` directly. Apple's own purchase gate
//     and this app's testing/simulation gate are the SAME control point —
//     testOverride (DEBUG-only) just short-circuits the exact same
//     `currentTier` property that the real StoreKit check will eventually
//     populate; it is not a parallel or bypassable mechanism.
//   - If you're about to add a new gated feature and find yourself writing
//     `UserDefaults.standard.bool(forKey: AppStorageKey.goldTierUnlocked)`
//     or any other independent "am I entitled" check, stop — call
//     `EntitlementManager.isEntitled(to:)` instead. A second control point
//     is exactly the loophole StoreKit review (and simple bugs) will find.
//   - Verified 2026-07-11: grepped the whole target for "StoreKit",
//     "goldTierUnlocked", and "isEntitled"/"currentTier"/"AppTier." —
//     every real usage funnels through this file; `goldTierUnlocked` is
//     defined in AppSettings.swift but not read by anything yet (reserved
//     for the future StoreKit writer, see TODO(StoreKit) below).
// ═══════════════════════════════════════════════════════════════════════
//
// GeoNap's monetization plan (Free/Standard/Silver/Gold — see the
// monetization-tier-pricing project memory, tagged in git as
// pre-apple-store-and-pricing-tier-support) has NO StoreKit/IAP
// implementation yet. This type exists so gated features have exactly one
// place to check, ready to be swapped for a real entitlement check —
// StoreKit 2 `Transaction.currentEntitlements`, receipt validation, etc. —
// without touching every call site again.
//
// Policy as of 2026-07-11 (Bob): distribution builds report `.gold` for
// EVERY user, unconditionally, until real StoreKit/IAP lands — there's no
// purchase flow yet, so locking real users out of Gold with no way to buy it
// would just be a broken experience, not a paywall. `AppStorageKey
// .goldTierUnlocked` is reserved for the future purchase/restore writer
// (see TODO(StoreKit) below) but is NOT read here right now — don't
// resurrect the old "RELEASE reads UserDefaults, defaults locked" behavior
// by accident; that was superseded by this instruction.
//
// This means `currentTier` is a stub everywhere today:
//   - RELEASE (including TestFlight, which archives Release): always `.gold`.
//   - DEBUG (Xcode → device/simulator, and `xcodebuild test`): `testOverride`
//     if set, else `.gold` — so ordinary local development still sees every
//     feature unlocked unless a test or the Settings "Tier Simulation"
//     section deliberately dials it down.
//
// TODO(StoreKit): once a real purchase/restore flow exists, replace the
// RELEASE branch below with actual entitlement verification (and give
// `AppStorageKey.goldTierUnlocked` a real writer), rather than the
// unconditional `.gold`. When that lands, keep the DEBUG bypass — it's still
// useful for local development — but audit every call site that currently
// assumes "RELEASE == everyone is Gold" no longer holds.
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
#if DEBUG
import Combine
import Foundation

/// Notifies every SwiftUI view using `.tierGated(minimumTier:)` whenever
/// `EntitlementManager.testOverride` changes, so gated controls re-render
/// immediately — regardless of whether the control that changed the tier
/// (Settings' Tier Simulation picker, most commonly) lives on a different
/// screen or the SAME screen as the gated control. Plain SwiftUI view
/// identity/re-render rules only guarantee a fresh render when NAVIGATING
/// to a screen after the tier changed elsewhere — they do nothing for a
/// gated control sitting on the very screen where the tier just changed,
/// which is exactly the bug this fixes (see monetization-tier-pricing
/// memory: the Auto-SMS hands-free toggle, Calendar Scanning row, and GTFS
/// cache toggle all live in SettingsView.swift alongside the Tier
/// Simulation picker itself, and stayed stuck showing the wrong
/// enabled/disabled state until this was added).
///
/// DEBUG-only, like `testOverride` itself: RELEASE builds never change tier
/// at runtime (`currentTier` is hardcoded `.gold`), so there's nothing to
/// observe there, and `TierGatedModifier.swift` only references this type
/// inside a matching `#if DEBUG` block.
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
    /// SwiftUI/Combine contract that expects that, and `testOverride` could
    /// in principle be set from a background thread (e.g. an XCTest running
    /// off-main), even though every real call site today — the Settings
    /// picker, NapStopApp.init()'s launch-argument parsing — is main-thread.
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
#endif

enum AppTier: Int, Comparable, CaseIterable, Hashable, CustomStringConvertible {
    case free = 0
    case standard = 1
    case silver = 2
    case gold = 3

    nonisolated static func < (lhs: AppTier, rhs: AppTier) -> Bool { lhs.rawValue < rhs.rawValue }

    nonisolated var description: String {
        switch self {
        case .free:     return "Free"
        case .standard: return "Standard"
        case .silver:   return "Silver"
        case .gold:     return "Gold"
        }
    }
}

enum EntitlementManager {

    #if DEBUG
    /// Test/QA override. When non-nil, short-circuits the `.gold` DEBUG
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

    nonisolated static var currentTier: AppTier {
        #if DEBUG
        return testOverride ?? .gold
        #else
        return .gold
        #endif
    }

    /// True when the current tier is `tier` or higher — tiers are additive
    /// (Gold includes everything Silver includes, etc.), so this is a
    /// `>=` comparison against `AppTier`'s raw-value ordering, not equality.
    nonisolated static func isEntitled(to tier: AppTier) -> Bool {
        currentTier >= tier
    }

    /// Convenience for the one gate that exists today (Run Shortcut on
    /// Alarm). Equivalent to `isEntitled(to: .gold)`. New gates against a
    /// different tier should call `isEntitled(to:)` directly so the call
    /// site documents which tier it requires.
    nonisolated static var isGoldTier: Bool { isEntitled(to: .gold) }

    #if DEBUG
    /// Parses a `--uitesting-tier <name>` pair out of launch arguments
    /// (case-insensitive tier name — "free", "Standard", "GOLD", etc.).
    /// Returns nil if the flag isn't present or the value doesn't match a
    /// known tier, in which case the caller should leave `testOverride`
    /// untouched (falls back to the ordinary `.gold` DEBUG default).
    nonisolated static func parseTierLaunchArgument(from arguments: [String]) -> AppTier? {
        guard let flagIndex = arguments.firstIndex(of: "--uitesting-tier"),
              arguments.indices.contains(flagIndex + 1) else { return nil }
        let raw = arguments[flagIndex + 1].lowercased()
        return AppTier.allCases.first { $0.description.lowercased() == raw }
    }
    #endif
}
