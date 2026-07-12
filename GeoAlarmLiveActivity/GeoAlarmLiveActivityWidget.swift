// Copyright © 2026 Robert Bartis. All rights reserved.

// GeoAlarmLiveActivityWidget.swift
// Renders the Gold-tier Live Activity started/updated/ended by
// LiveActivityManager.swift (main app target) — Lock Screen banner +
// Dynamic Island compact/minimal/expanded presentations.
//
// This file belongs in a NEW Widget Extension target that does not exist in
// the Xcode project yet — see LIVE_ACTIVITY_SETUP.md in this folder for the
// one-time manual Xcode steps (mirrors NapStopWatch/WATCH_SETUP.md, same
// reasoning: target creation isn't something that can be done safely by
// hand-editing project.pbxproj). All Swift source is written and ready.
//
// GeoAlarm/Models/GeoAlarmActivityAttributes.swift must be added to this
// target's membership too (shared with the main app target).

import ActivityKit
import WidgetKit
import SwiftUI

// @main lives on GeoAlarmLiveActivityBundle.swift's WidgetBundle — a target
// can only have one @main type, and the bundle is the entry point that
// composes whichever individual widgets/activities this extension ships.
struct GeoAlarmLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: GeoAlarmActivityAttributes.self) { context in
            // Lock Screen / banner presentation.
            LockScreenView(context: context)
                .activityBackgroundTint(Color(red: 0.102, green: 0.227, blue: 0.322))   // matches the app's navy (1A3A52, see marketing deck)
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: iconName(context: context))
                        .foregroundStyle(.yellow)
                        .font(.title2)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ProgressReadout(state: context.state, triggerModeRaw: context.attributes.triggerModeRaw)
                        .font(.title3.monospacedDigit())
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.alarmName)
                        .font(.headline)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(verbLabel(context: context))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } compactLeading: {
                Image(systemName: iconName(context: context))
                    .foregroundStyle(.yellow)
            } compactTrailing: {
                ProgressReadout(state: context.state, triggerModeRaw: context.attributes.triggerModeRaw)
                    .font(.caption2.monospacedDigit())
            } minimal: {
                Image(systemName: iconName(context: context))
                    .foregroundStyle(.yellow)
            }
        }
    }

    private func iconName(context: ActivityViewContext<GeoAlarmActivityAttributes>) -> String {
        context.attributes.regionEventRaw == "onEntry" ? "mappin.circle.fill" : "figure.walk.circle.fill"
    }

    private func verbLabel(context: ActivityViewContext<GeoAlarmActivityAttributes>) -> String {
        context.attributes.regionEventRaw == "onEntry" ? "Arriving at" : "Leaving"
    }
}

// MARK: - Lock Screen

private struct LockScreenView: View {
    let context: ActivityViewContext<GeoAlarmActivityAttributes>

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: context.attributes.regionEventRaw == "onEntry" ? "mappin.circle.fill" : "figure.walk.circle.fill")
                .font(.largeTitle)
                .foregroundStyle(.yellow)

            VStack(alignment: .leading, spacing: 3) {
                Text(context.attributes.alarmName)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(context.attributes.regionEventRaw == "onEntry" ? "Arriving soon" : "Leaving soon")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
            }

            Spacer()

            ProgressReadout(state: context.state, triggerModeRaw: context.attributes.triggerModeRaw)
                .font(.title2.monospacedDigit())
                .foregroundStyle(.white)
        }
        .padding(16)
    }
}

// MARK: - Shared distance/ETA readout

/// Formats whichever of distance/ETA is meaningful for this alarm's trigger
/// mode. Time-mode alarms show the ETA countdown (that's the whole point of
/// "Time before arrival"); distance-mode alarms show distance remaining.
/// Falls back to "—" before the first GPS fix arrives, never blank.
private struct ProgressReadout: View {
    let state: GeoAlarmActivityAttributes.ContentState
    let triggerModeRaw: String

    var body: some View {
        Text(text)
    }

    private var text: String {
        if triggerModeRaw == "time", let eta = state.etaSeconds {
            return Self.formatETA(eta)
        }
        if let distance = state.distanceRemaining {
            return Self.formatDistance(distance)
        }
        return "—"
    }

    private static func formatETA(_ seconds: Double) -> String {
        let minutes = max(0, Int(seconds.rounded()) / 60)
        return minutes < 1 ? "<1 min" : "\(minutes) min"
    }

    private static func formatDistance(_ meters: Double) -> String {
        // Matches the app's own DistanceUnit formatting intent (see
        // DistanceUnit.formatted(meters:) in the main target) without
        // depending on @AppStorage, which isn't meaningfully available to a
        // widget extension process — a simple metric/imperial-agnostic
        // readout is fine here since the Live Activity is a glance, not the
        // full alarm detail screen.
        if meters >= 1000 {
            return String(format: "%.1f km", meters / 1000)
        }
        return "\(Int(meters.rounded())) m"
    }
}

#Preview("Lock Screen", as: .content, using: GeoAlarmActivityAttributes(
    alarmID: UUID().uuidString,
    alarmName: "Penn Station",
    triggerModeRaw: "distance",
    regionEventRaw: "onEntry"
)) {
    GeoAlarmLiveActivityWidget()
} contentStates: {
    GeoAlarmActivityAttributes.ContentState(distanceRemaining: 850, etaSeconds: nil, lastUpdated: Date())
    GeoAlarmActivityAttributes.ContentState(distanceRemaining: 120, etaSeconds: nil, lastUpdated: Date())
}
