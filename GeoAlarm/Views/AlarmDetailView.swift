// AlarmDetailView.swift
// Read-only summary of a saved alarm: mini-map with accurate radius circle,
// history, and metadata. Provides navigation to AddAlarmView for editing.

import SwiftUI
import MapKit

struct AlarmDetailView: View {
    let alarm: GeoAlarm

    @EnvironmentObject var alarmManager: AlarmManager
    @AppStorage(AppStorageKey.distanceUnit) private var distanceUnitRaw = DistanceUnit.metric.rawValue
    @AppStorage(AppStorageKey.timeFormat)   private var timeFormatRaw   = TimeFormat.twelveHour.rawValue
    private var distanceUnit: DistanceUnit { DistanceUnit(rawValue: distanceUnitRaw) ?? .metric }
    private var timeFormat:   TimeFormat   { TimeFormat(rawValue: timeFormatRaw)     ?? .twelveHour }

    // Camera shows the alarm circle filling roughly half the map frame.
    // Span = diameter × 2 so the circle occupies ~50% of the view.
    private var initialCamera: MapCameraPosition {
        .region(MKCoordinateRegion(
            center: alarm.coordinate,
            latitudinalMeters:  alarm.radius * 4,
            longitudinalMeters: alarm.radius * 4
        ))
    }

    var body: some View {
        List {

            // MARK: Mini-map
            Section {
                Map(initialPosition: initialCamera, interactionModes: []) {
                    // Accurate geofence circle at real-world scale
                    MapCircle(center: alarm.coordinate, radius: alarm.radius)
                        .foregroundStyle(stateColor.opacity(0.15))
                        .stroke(stateColor.opacity(0.8), lineWidth: 2)

                    // Centre pin
                    Annotation(alarm.name, coordinate: alarm.coordinate) {
                        Image(systemName: "mappin.circle.fill")
                            .font(.title2)
                            .foregroundStyle(stateColor)
                    }
                }
                .mapStyle(.standard(elevation: .flat))
                .mapControls { }
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
            }

            // MARK: Transit Details (only for transit alarms)
            if alarm.isTransitAlarm {
                Section("Transit") {
                    if let agency = alarm.transitAgencyName {
                        LabeledContent("Agency") { Text(agency) }
                    }
                    if let route = alarm.transitRouteName {
                        LabeledContent("Route") {
                            HStack(spacing: 6) {
                                if let rt = alarm.transitRouteType {
                                    Image(systemName: rt.systemImage)
                                        .foregroundColor(.teal)
                                }
                                Text(route)
                            }
                        }
                    }
                    if let stop = alarm.transitStopName {
                        LabeledContent("Stop") { Text(stop) }
                    }
                }
            }

            // MARK: Status
            Section("Status") {
                LabeledContent("State") {
                    HStack(spacing: 6) {
                        Circle().fill(stateColor).frame(width: 10, height: 10)
                        Text(alarm.state.rawValue.capitalized)
                    }
                }
                LabeledContent("Trigger") { Text(alarm.regionEvent.rawValue) }
                LabeledContent("Radius")  { Text(distanceUnit.formatted(meters: alarm.radius)) }
                if alarm.isRepeating {
                    LabeledContent("Repeat") { Text("On") }
                }
                if let window = alarm.windowLabel(using: timeFormat) {
                    LabeledContent("Time window") { Text(window) }
                }
                if let daysLabel = alarm.activeDaysLabel {
                    LabeledContent("Active days") { Text(daysLabel) }
                }
            }

            // MARK: History
            Section("History") {
                LabeledContent("Times triggered") {
                    Text(alarm.triggerCount == 0 ? "Never" : "\(alarm.triggerCount)")
                }
                if let last = alarm.lastTriggeredAt {
                    LabeledContent("Last triggered") {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(last, style: .relative)
                                .foregroundStyle(.secondary)
                            Text(last, style: .date)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                if !alarm.note.isEmpty {
                    LabeledContent("Note") { Text(alarm.note) }
                }
            }

            // MARK: Actions
            Section {
                NavigationLink("Edit Alarm") {
                    AddAlarmView(existingAlarm: alarm)
                }
                Button(alarm.isActive ? "Disable alarm" : "Enable alarm") {
                    alarmManager.toggleActive(alarm)
                }
                .foregroundColor(alarm.isActive ? .orange : .green)

                ShareLink(item: shareURLString) {
                    Label("Share location", systemImage: "square.and.arrow.up")
                }
            }
        }
        .navigationTitle(alarm.name)
        .navigationBarTitleDisplayMode(.large)
    }

    // MARK: - Helpers

    /// Apple Maps URL string for sharing — plain String so Copy puts the URL text
    /// directly on the clipboard regardless of share destination.
    private var shareURLString: String {
        let name = alarm.name
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? alarm.name
        return "https://maps.apple.com/?ll=\(alarm.latitude),\(alarm.longitude)&q=\(name)"
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
        AlarmDetailView(alarm: GeoAlarm.preview)
    }
    .environmentObject(AlarmManager())
}
