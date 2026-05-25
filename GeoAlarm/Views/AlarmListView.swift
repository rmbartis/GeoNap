// AlarmListView.swift
// Displays all saved geo-alarms with swipe actions and repeat indicator.

import SwiftUI

struct AlarmListView: View {
    @EnvironmentObject var alarmManager: AlarmManager
    @EnvironmentObject var locationManager: LocationManager

    var body: some View {
        Group {
            if alarmManager.alarms.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(alarmManager.alarms) { alarm in
                        NavigationLink(destination: AlarmDetailView(alarm: alarm)) {
                            AlarmRowView(alarm: alarm)
                        }
                        .swipeActions(edge: .leading) {
                            Button {
                                alarmManager.toggleActive(alarm)
                            } label: {
                                Label(
                                    alarm.isActive ? "Disable" : "Enable",
                                    systemImage: alarm.isActive ? "pause.circle" : "play.circle"
                                )
                            }
                            .tint(alarm.isActive ? .orange : .green)
                        }
                    }
                    .onDelete { alarmManager.delete(at: $0) }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "location.circle")
                .font(.system(size: 64))
                .foregroundColor(.secondary)
            Text("No Geo Alarms Yet")
                .font(.title2.bold())
            Text("Tap + to create your first alarm.\nYou'll be notified when you arrive at or leave any saved location.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Alarm Row

struct AlarmRowView: View {
    let alarm: GeoAlarm

    @AppStorage(AppStorageKey.distanceUnit) private var distanceUnitRaw = DistanceUnit.metric.rawValue
    @AppStorage(AppStorageKey.timeFormat)   private var timeFormatRaw   = TimeFormat.twelveHour.rawValue
    private var distanceUnit: DistanceUnit { DistanceUnit(rawValue: distanceUnitRaw) ?? .metric }
    private var timeFormat:   TimeFormat   { TimeFormat(rawValue: timeFormatRaw)     ?? .twelveHour }

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(stateColor)
                .frame(width: 12, height: 12)

            VStack(alignment: .leading, spacing: 3) {
                Text(alarm.name)
                    .font(.body.bold())
                    .foregroundColor(alarm.isActive ? .primary : .secondary)

                // Row 1: radius · trigger type
                HStack(spacing: 6) {
                    HStack(spacing: 3) {
                        Text(distanceUnit.formatted(meters: alarm.radius))
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                    }
                    Text("·")
                    Text(alarm.regionEvent.rawValue)
                }
                .font(.caption)
                .foregroundColor(.secondary)

                // Row 2: optional badges — only shown when at least one is set
                if alarm.isRepeating || alarm.hasTimeWindow {
                    HStack(spacing: 10) {
                        if alarm.isRepeating {
                            Image(systemName: "repeat")
                                .foregroundColor(.blue)
                        }
                        if let window = alarm.windowLabel(using: timeFormat) {
                            Text(window)
                                .foregroundColor(.purple)
                        }
                    }
                    .font(.caption)
                }
            }

            Spacer()

            if alarm.state == .triggered {
                Image(systemName: "bell.badge.fill")
                    .foregroundColor(.red)
            } else if alarm.state == .snoozed {
                Image(systemName: "moon.zzz.fill")
                    .foregroundColor(.orange)
            }
        }
        .padding(.vertical, 4)
        .opacity(alarm.isActive || alarm.state == .triggered ? 1.0 : 0.5)
    }

    private var stateColor: Color {
        switch alarm.state {
        case .active:    return .green
        case .triggered: return .red
        case .snoozed:   return .orange
        case .inactive:  return .gray
        }
    }
}

#Preview {
    NavigationStack {
        AlarmListView()
            .navigationTitle("Geo Alarms")
    }
    .environmentObject(AlarmManager())
    .environmentObject(LocationManager())
}
