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
// Re-render note (corrected 2026-07-11, second pass): this DOES live-update
// now. The first version of this comment claimed a same-screen tier change
// (e.g. Settings' Tier Simulation picker changing tier while a gated
// control on that same screen is visible) would never happen and so wasn't
// worth handling — that was wrong. Auto-SMS hands-free, Calendar Scanning,
// and GTFS cache all live in SettingsView.swift right alongside the picker
// itself, and stayed visually enabled after switching tiers until this was
// fixed. Fixed by observing `TierChangeObserver` (in EntitlementManager.swift,
// DEBUG-only), which `EntitlementManager.testOverride`'s `didSet` notifies on
// every change — so every `.tierGated` view anywhere re-renders immediately,
// regardless of which screen changed the tier. (An earlier attempt added
// `.id(simulatedTier)` to SettingsView's Form instead — removed once this
// more general, less fragile fix landed; per-screen `.id()` hacks would have
// needed re-deriving for every future screen that mixes a tier-changing
// control with a gated one.)

import SwiftUI

struct TierGated: ViewModifier {
    let minimumTier: AppTier

    #if DEBUG
    // Makes this modifier re-render whenever the simulated tier changes,
    // anywhere in the app — see the file-header note above and
    // TierChangeObserver's doc comment in EntitlementManager.swift.
    // RELEASE builds never change tier at runtime, so there's nothing to
    // observe there and this is compiled out entirely.
    @ObservedObject private var tierChangeObserver = TierChangeObserver.shared
    #endif

    private var isEntitled: Bool { EntitlementManager.isEntitled(to: minimumTier) }

    func body(content: Content) -> some View {
        HStack(spacing: 8) {
            content
                .disabled(!isEntitled)
                .opacity(isEntitled ? 1.0 : 0.5)

            if !isEntitled {
                Spacer(minLength: 4)
                Label(minimumTier.description, systemImage: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .labelStyle(.titleAndIcon)
                    .fixedSize()
                    .accessibilityLabel("Requires \(minimumTier.description) tier")
                    .accessibilityIdentifier("tierGatedLock.\(minimumTier.description.lowercased())")
            }
        }
    }
}

extension View {
    /// Disables this view and shows a lock + required-tier badge when the
    /// current device tier is below `minimumTier`. See TierGatedModifier.swift.
    func tierGated(minimumTier: AppTier) -> some View {
        modifier(TierGated(minimumTier: minimumTier))
    }
}
