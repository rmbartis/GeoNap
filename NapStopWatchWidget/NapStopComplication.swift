// NapStopComplication.swift
// WidgetKit complication for watchOS — shows the nearest active NapAlarm.
// Supports four complication families:
//   • accessoryCircular    — small circle: icon + count
//   • accessoryRectangular — wide band: name + trigger type + overflow count
//   • accessoryInline      — single line of text in watch faces
//   • accessoryCorner      — corner gauge with icon

import WidgetKit
import SwiftUI

// MARK: - Shared storage key (must match WatchAlarmStore)

private let suiteName  = "group.com.rmbartis.NapAlarm"
private let storageKey = "watchAlarms"      // WatchConnectivityManager.alarmsKey

// MARK: - Timeline Entry

struct AlarmEntry: TimelineEntry {
    let date: Date
    let featuredName: String?   // name of first (nearest) alarm, nil = no active alarms
    let activeCount: Int
    let isTriggered: Bool
}

// MARK: - Provider

struct AlarmProvider: TimelineProvider {

    func placeholder(in context: Context) -> AlarmEntry {
        AlarmEntry(date: Date(), featuredName: "Penn Station",
                   activeCount: 1, isTriggered: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (AlarmEntry) -> Void) {
        completion(makeEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<AlarmEntry>) -> Void) {
        let entry = makeEntry()
        // Refresh every 15 minutes as a safety net; WatchAlarmStore also calls
        // WidgetCenter.reloadAllTimelines() whenever new data arrives from the iPhone.
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date()
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }

    // MARK: - Helpers

    private func loadAlarms() -> [WatchAlarmPayload] {
        guard let defaults = UserDefaults(suiteName: suiteName),
              let data    = defaults.data(forKey: storageKey),
              let alarms  = try? JSONDecoder().decode([WatchAlarmPayload].self, from: data)
        else { return [] }
        return alarms
    }

    private func makeEntry() -> AlarmEntry {
        let alarms = loadAlarms()
        let first  = alarms.first
        return AlarmEntry(
            date: Date(),
            featuredName: first?.name,
            activeCount: alarms.count,
            isTriggered: first?.state == "triggered"
        )
    }
}

// MARK: - Complication Views

struct AlarmComplicationView: View {
    let entry: AlarmEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryCircular:    circularView
        case .accessoryRectangular: rectangularView
        case .accessoryInline:      inlineView
        case .accessoryCorner:      cornerView
        default:                    circularView
        }
    }

    // ── Circular ─────────────────────────────────────────────────────────────
    // Icon in the centre; a red badge when an alarm has fired.

    private var circularView: some View {
        ZStack {
            if entry.activeCount == 0 {
                Image(systemName: "location.slash")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 1) {
                    Image(systemName: entry.isTriggered ? "bell.badge.fill" : "location.fill")
                        .font(.callout.bold())
                        .foregroundStyle(entry.isTriggered ? .red : .green)
                    Text("\(entry.activeCount)")
                        .font(.caption2.bold())
                        .foregroundStyle(entry.isTriggered ? .red : .primary)
                }
            }
        }
    }

    // ── Rectangular ───────────────────────────────────────────────────────────
    // Header row + alarm name + optional overflow count.

    private var rectangularView: some View {
        VStack(alignment: .leading, spacing: 3) {
            // Header
            HStack(spacing: 4) {
                Image(systemName: entry.isTriggered ? "bell.badge.fill" : "location.fill")
                    .font(.caption2.bold())
                    .foregroundStyle(entry.isTriggered ? .red : .green)
                Text(entry.isTriggered ? "Alarm fired!" : "NapAlarm")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            // Featured alarm name
            if let name = entry.featuredName {
                Text(name)
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            } else {
                Text("No active alarms")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            // Overflow count
            if entry.activeCount > 1 {
                Text("+ \(entry.activeCount - 1) more")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // ── Inline ────────────────────────────────────────────────────────────────
    // One line of text; used in watch faces that show a single data line.

    private var inlineView: some View {
        Label(
            entry.featuredName ?? "No alarms",
            systemImage: entry.isTriggered ? "bell.badge.fill" : "location.fill"
        )
    }

    // ── Corner ────────────────────────────────────────────────────────────────
    // Small icon with a text label curving around the corner.

    private var cornerView: some View {
        Image(systemName: entry.isTriggered ? "bell.badge.fill" : "location.fill")
            .foregroundStyle(entry.isTriggered ? .red : .green)
            .widgetLabel(entry.featuredName ?? "NapAlarm")
    }
}

// MARK: - Widget Definition

@main
struct NapStopComplication: Widget {
    let kind = "GeoNapComplication"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: AlarmProvider()) { entry in
            AlarmComplicationView(entry: entry)
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("NapAlarm")
        .description("Shows your nearest active alarm.")
        .supportedFamilies([
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline,
            .accessoryCorner
        ])
    }
}

// MARK: - Preview

#Preview(as: .accessoryRectangular) {
    NapStopComplication()
} timeline: {
    AlarmEntry(date: .now, featuredName: "Penn Station", activeCount: 2, isTriggered: false)
    AlarmEntry(date: .now, featuredName: "Penn Station", activeCount: 1, isTriggered: true)
    AlarmEntry(date: .now, featuredName: nil,            activeCount: 0, isTriggered: false)
}
