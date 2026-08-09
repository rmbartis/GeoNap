// Copyright © 2026 Robert Bartis. All rights reserved.

// TierGatedModifier.swift
// Reusable "visible but disabled" pattern for tier-gated controls, added
// 2026-07-11 per Bob's explicit policy: a control that requires a higher
// tier than the device currently has stays VISIBLE and shows what it needs,
// rather than being hidden. (Superseded an earlier decision on Run Shortcut
// on Alarm — see monetization-tier-pricing memory — where the field was left
// fully enabled with only a Help-text disclosure; that approach is retired
// in favor of this one.)
//
// First (and, as of this writing, only) consumer: the Run Shortcut on Alarm
// field in AddAlarmView.swift and TransitAlarmView.swift. When more features
// get real per-tier gates, apply `.tierGated(minimumTier:)` to them too
// rather than inventing a second pattern.
//
// Extended 2026-07-22 with an `enabledIf` parameter so a control can be
// gated on BOTH tier entitlement AND an in-form condition without stacking a
// second, independent `.disabled(_:)` next to this modifier. Two chained
// `.disabled(_:)` calls don't AND together the way you'd expect — SwiftUI's
// `isEnabled` environment value is simply overwritten by whichever modifier
// sits closest to the actual control, so a plain `.disabled(!isRepeating)`
// placed next to `.tierGated(...)` would silently make one of the two gates
// a no-op depending on ordering. Routing the extra condition through this
// modifier's own single `.disabled(_:)` call sidesteps that entirely.
// First consumer: Active Days in AddAlarmView.swift / TransitAlarmView.swift,
// which must additionally require the Repeat toggle to be on (Bob reported
// Active Days was interactable with Repeat off, which made no sense — a
// day-of-week restriction only means anything for a repeating alarm).
//
// Re-render note (corrected 2026-07-11, second pass): this DOES live-update
// now. The first version of this comment claimed a same-screen tier change
// (e.g. Settings' Tier Simulation picker changing tier while a gated
// control on that same screen is visible) would never happen and so wasn't
// worth handling — that was wrong. Auto-SMS hands-free, Calendar Scanning,
// and GTFS cache all live in SettingsView.swift right alongside the picker
// itself, and stayed visually enabled after switching tiers until this was
// fixed. Fixed by observing `TierChangeObserver` (in EntitlementManager.swift),
// which both `EntitlementManager.testOverride`'s `didSet` (DEBUG) and
// `EntitlementManager.verifiedTier`'s `didSet` (real StoreKit entitlement
// changes, any build) notify on every change — so every `.tierGated` view
// anywhere re-renders immediately, regardless of which screen or mechanism
// changed the tier. (An earlier attempt added `.id(simulatedTier)` to
// SettingsView's Form instead — removed once this more general, less
// fragile fix landed; per-screen `.id()` hacks would have needed
// re-deriving for every future screen that mixes a tier-changing control
// with a gated one.)
//
// Unconditional as of 2026-08-08 (item 9): this used to only observe
// TierChangeObserver in DEBUG, because RELEASE hardcoded `.platinum` for
// everyone and tier never changed at runtime there. Now that real
// StoreKit/IAP is wired in, RELEASE tier CAN change mid-session (a purchase
// completing, a restore, a subscription renewal) — so this needs to
// re-render in RELEASE too, not just DEBUG.

import SwiftUI

struct TierGated: ViewModifier {
    let minimumTier: AppTier
    /// Extra non-tier condition that must ALSO be true for the control to be
    /// enabled (e.g. "Repeat is on"). Defaults to true so existing call
    /// sites that only care about tier are unaffected. Deliberately does NOT
    /// affect the lock badge below — that badge specifically communicates
    /// "your tier is insufficient," which stays accurate regardless of
    /// `enabledIf`; the `enabledIf`-only-false case (tier is fine, the other
    /// condition isn't met) is expected to be explained by the caller via
    /// its own footer/hint text instead, since there's nothing tier-related
    /// to show a lock for.
    var enabledIf: Bool = true

    // Makes this modifier re-render whenever the tier changes, anywhere in
    // the app (simulated in DEBUG, or a real StoreKit entitlement change in
    // any build) — see the file-header note above and TierChangeObserver's
    // doc comment in EntitlementManager.swift.
    @ObservedObject private var tierChangeObserver = TierChangeObserver.shared

    /// Presents PaywallView (item 10) when the lock badge is tapped. Kept as
    /// an `.onTapGesture` on the existing `Label` rather than converting it
    /// to a real `Button` — a `Button` would change the element's underlying
    /// accessibility type, which would break `TierGatingUITests
    /// .lockBadgeExists(tier:)`'s existing staticTexts/otherElements/images
    /// query (see that test's own comment on why it doesn't check
    /// `app.buttons`). Same pattern SoundPickerSection.swift already uses
    /// for its own manual lock badge.
    @State private var showPaywall = false

    private var isEntitled: Bool { EntitlementManager.isEntitled(to: minimumTier) }
    private var isFullyEnabled: Bool { isEntitled && enabledIf }

    func body(content: Content) -> some View {
        HStack(spacing: 8) {
            content
                .disabled(!isFullyEnabled)
                .opacity(isFullyEnabled ? 1.0 : 0.5)

            if !isEntitled {
                Spacer(minLength: 4)
                Label(minimumTier.description, systemImage: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .labelStyle(.titleAndIcon)
                    .fixedSize()
                    .contentShape(Rectangle())
                    .onTapGesture { showPaywall = true }
                    .accessibilityLabel("Requires \(minimumTier.description) tier — tap to see plans")
                    .accessibilityIdentifier("tierGatedLock.\(minimumTier.description.lowercased())")
            }
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
    }
}

extension View {
    /// Disables this view and shows a lock + required-tier badge when the
    /// current device tier is below `minimumTier`. See TierGatedModifier.swift.
    ///
    /// `enabledIf` lets a caller AND in an additional, non-tier condition
    /// (e.g. Active Days requiring Repeat to be on) without stacking a
    /// second `.disabled(_:)` next to this call — see the file header for
    /// why that doesn't compose the way you'd expect.
    func tierGated(minimumTier: AppTier, enabledIf: Bool = true) -> some View {
        modifier(TierGated(minimumTier: minimumTier, enabledIf: enabledIf))
    }
}
