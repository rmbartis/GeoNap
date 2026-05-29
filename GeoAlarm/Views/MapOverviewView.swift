// MapOverviewView.swift
// Shows all saved alarms as region circles on a single map.
// Circle colour reflects alarm state. Tap a circle label to open its detail.

import SwiftUI
import MapKit

struct MapOverviewView: View {

    @EnvironmentObject var alarmManager: AlarmManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.languageBundle) private var bundle

    // Start with a wide view; user can pan/zoom freely.
    @State private var cameraPosition: MapCameraPosition = .automatic

    // Alarm selected by tapping an annotation — drives navigation.
    @State private var selectedAlarm: NapAlarm?

    var body: some View {
        NavigationStack {
            Group {
                if alarmManager.alarms.isEmpty {
                    emptyState
                } else {
                    Map(position: $cameraPosition) {
                        ForEach(alarmManager.alarms) { alarm in
                            // Geofence circle at true geographic scale
                            MapCircle(center: alarm.coordinate, radius: alarm.radius)
                                .foregroundStyle(stateColor(alarm).opacity(0.15))
                                .stroke(stateColor(alarm).opacity(0.8), lineWidth: 2)

                            // Tappable annotation — navigates to detail
                            Annotation(alarm.name, coordinate: alarm.coordinate) {
                                Button {
                                    selectedAlarm = alarm
                                } label: {
                                    ZStack {
                                        Circle()
                                            .fill(stateColor(alarm))
                                            .frame(width: 28, height: 28)
                                        Image(systemName: stateIcon(alarm))
                                            .font(.caption.bold())
                                            .foregroundStyle(.white)
                                    }
                                }
                            }
                        }
                    }
                    .mapStyle(.standard(elevation: .flat))
                    .mapControls {
                        MapUserLocationButton()
                        MapCompass()
                        MapScaleView()
                    }
                    .navigationDestination(item: $selectedAlarm) { alarm in
                        AlarmDetailView(alarm: alarm)
                    }
                }
            }
            .navigationTitle(Text("Map Overview", bundle: bundle))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: {
                        Text("Done", bundle: bundle)
                    }
                }
            }
        }
        .onAppear { fitCamera() }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "map")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
            Text("No alarms to show", bundle: bundle)
                .font(.title3.bold())
            Text("Create an alarm first and it will appear here.", bundle: bundle)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Camera fit

    /// Sets the initial camera to frame all alarm circles with padding.
    private func fitCamera() {
        guard !alarmManager.alarms.isEmpty else { return }

        if alarmManager.alarms.count == 1, let alarm = alarmManager.alarms.first {
            cameraPosition = .region(MKCoordinateRegion(
                center: alarm.coordinate,
                latitudinalMeters:  alarm.radius * 6,
                longitudinalMeters: alarm.radius * 6
            ))
            return
        }

        // Build a bounding box that includes every alarm's circle.
        var minLat =  90.0, maxLat = -90.0
        var minLon = 180.0, maxLon = -180.0

        for alarm in alarmManager.alarms {
            let latDelta = alarm.radius / 111_000
            let lonDelta = alarm.radius / (111_000 * cos(alarm.latitude * .pi / 180))
            minLat = min(minLat, alarm.latitude  - latDelta)
            maxLat = max(maxLat, alarm.latitude  + latDelta)
            minLon = min(minLon, alarm.longitude - lonDelta)
            maxLon = max(maxLon, alarm.longitude + lonDelta)
        }

        let centre = CLLocationCoordinate2D(
            latitude:  (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        // Add 40% padding around the bounding box.
        let span = MKCoordinateSpan(
            latitudeDelta:  (maxLat - minLat) * 1.4,
            longitudeDelta: (maxLon - minLon) * 1.4
        )
        cameraPosition = .region(MKCoordinateRegion(center: centre, span: span))
    }

    // MARK: - Helpers

    private func stateColor(_ alarm: NapAlarm) -> Color {
        switch alarm.state {
        case .active:    return .green
        case .triggered: return .red
        case .snoozed:   return .orange
        case .inactive:  return .gray
        }
    }

    private func stateIcon(_ alarm: NapAlarm) -> String {
        switch alarm.state {
        case .active:    return "bell.fill"
        case .triggered: return "bell.badge.fill"
        case .snoozed:   return "moon.zzz.fill"
        case .inactive:  return "bell.slash.fill"
        }
    }
}

#Preview {
    MapOverviewView()
        .environmentObject(AlarmManager())
}
