// AlarmListView.swift
// Displays all saved geo-alarms with swipe actions and repeat indicator.

import SwiftUI

struct AlarmListView: View {
    @EnvironmentObject var alarmManager: AlarmManager
    @EnvironmentObject var locationManager: LocationManager
    @Environment(\.languageBundle) private var bundle

    var body: some View {
        Group {
            if alarmManager.alarms.isEmpty {
                emptyState
            } else {
                List {
                    // MARK: Region limit warning
                    if alarmManager.isAtRegionLimit {
                        RegionLimitBanner(isFull: true)
                            .listRowBackground(Color.red.opacity(0.08))
                            .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                    } else if alarmManager.isNearRegionLimit {
                        RegionLimitBanner(isFull: false)
                            .listRowBackground(Color.orange.opacity(0.08))
                            .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                    }

                    ForEach(alarmManager.alarms) { alarm in
                        NavigationLink(destination: AlarmDetailView(alarm: alarm)) {
                            AlarmRowView(alarm: alarm)
                        }
                        // Leading edge: enable / disable
                        .swipeActions(edge: .leading) {
                            Button {
                                alarmManager.toggleActive(alarm)
                            } label: {
                                Label {
                                    Text(alarm.isActive
                                         ? NSLocalizedString("Disable", bundle: bundle, comment: "")
                                         : NSLocalizedString("Enable", bundle: bundle, comment: ""))
                                } icon: {
                                    Image(systemName: alarm.isActive ? "pause.circle" : "play.circle")
                                }
                            }
                            .tint(alarm.isActive ? .orange : .green)
                        }
                        // Trailing edge: delete — explicit so the label uses our bundle,
                        // not the system's current locale string.
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                alarmManager.delete(alarm: alarm)
                            } label: {
                                Label(NSLocalizedString("Delete", bundle: bundle, comment: ""),
                                      systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "location.circle")
                .font(.system(size: 64))
                .foregroundColor(.secondary)
            Text("No NapStop Alarms Yet", bundle: bundle)
                .font(.title2.bold())
            Text("Tap + to create your first alarm.\nYou'll be notified when you arrive at or leave any saved location.", bundle: bundle)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Alarm Row

struct AlarmRowView: View {
    let alarm: NapAlarm

    @Environment(\.languageBundle) private var bundle
    @AppStorage(AppStorageKey.distanceUnit) private var distanceUnitRaw = DistanceUnit.imperial.rawValue
    @AppStorage(AppStorageKey.timeFormat)   private var timeFormatRaw   = TimeFormat.twelveHour.rawValue
    private var distanceUnit: DistanceUnit { DistanceUnit(rawValue: distanceUnitRaw) ?? .imperial }
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
                    Text(NSLocalizedString(alarm.regionEvent.rawValue, bundle: bundle, comment: ""))
                }
                .font(.caption)
                .foregroundColor(.secondary)

                // Row 2: optional badges — only shown when at least one is set
                if alarm.isRepeating || alarm.hasTimeWindow || alarm.isTransitAlarm || !alarm.isEveryDay {
                    HStack(spacing: 10) {
                        if alarm.isTransitAlarm, let rt = alarm.transitRouteType {
                            Image(systemName: rt.systemImage)
                                .foregroundColor(.teal)
                        }
                        if alarm.isRepeating {
                            Image(systemName: "repeat")
                                .foregroundColor(.blue)
                        }
                        if let window = alarm.windowLabel(using: timeFormat) {
                            Text(window)
                                .foregroundColor(.purple)
                        }
                        if let daysLabel = alarm.activeDaysLabel {
                            HStack(spacing: 3) {
                                Image(systemName: "calendar")
                                Text(daysLabel)
                            }
                            .foregroundColor(.orange)
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

// MARK: - Region Limit Banner

private struct RegionLimitBanner: View {
    let isFull: Bool
    @Environment(\.languageBundle) private var bundle

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isFull ? "exclamationmark.octagon.fill" : "exclamationmark.triangle.fill")
                .foregroundColor(isFull ? .red : .orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(isFull
                     ? NSLocalizedString("Alarm limit reached", bundle: bundle, comment: "")
                     : NSLocalizedString("Approaching alarm limit", bundle: bundle, comment: ""))
                    .font(.caption.bold())
                Text(isFull
                     ? NSLocalizedString("iOS allows 20 active alarms. Disable one before adding another.", bundle: bundle, comment: "")
                     : NSLocalizedString("iOS allows 20 active alarms. You're close to the limit.", bundle: bundle, comment: ""))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationStack {
        AlarmListView()
            .navigationTitle("NapStop")
    }
    .environmentObject(AlarmManager())
    .environmentObject(LocationManager())
}
