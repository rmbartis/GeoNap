// NearestAlarmView.swift
// Main watch app view — lists active alarms received from the iPhone.

import SwiftUI

struct NearestAlarmView: View {
    @EnvironmentObject var store: WatchAlarmStore

    var body: some View {
        if store.alarms.isEmpty {
            emptyState
        } else {
            List(store.alarms) { alarm in
                AlarmWatchRow(alarm: alarm)
            }
            .navigationTitle("NapAlarm")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "location.slash")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("No active alarms")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Open NapAlarm on your iPhone to set one up.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
    }
}

// MARK: - Row

private struct AlarmWatchRow: View {
    let alarm: WatchAlarmPayload

    private var isTriggered: Bool { alarm.state == "triggered" }

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(isTriggered ? Color.red : Color.green)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(alarm.name)
                    .font(.headline)
                    .lineLimit(1)
                Text(alarm.regionEvent)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isTriggered {
                Image(systemName: "bell.badge.fill")
                    .foregroundStyle(.red)
                    .font(.caption)
            }
        }
        .padding(.vertical, 2)
    }
}
