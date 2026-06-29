// AlarmDetailView.swift
// Read-only summary of a saved alarm: mini-map with accurate radius circle,
// history, and metadata. Provides navigation to AddAlarmView for editing.

import SwiftUI
import MapKit

struct AlarmDetailView: View {
    let alarm: NapAlarm

    @EnvironmentObject var alarmManager: AlarmManager
    @Environment(\.languageBundle) private var bundle
    // Declared unconditionally — @State inside #if blocks can prevent SwiftUI
    // from registering the property wrapper, making the whole section disappear.
    // Only used by the #if targetEnvironment(simulator) section below.
    @State private var simulatorCountdown: Int? = nil
    @AppStorage(AppStorageKey.distanceUnit) private var distanceUnitRaw = DistanceUnit.imperial.rawValue
    @AppStorage(AppStorageKey.timeFormat)   private var timeFormatRaw   = TimeFormat.twelveHour.rawValue
    private var distanceUnit: DistanceUnit { DistanceUnit(rawValue: distanceUnitRaw) ?? .imperial }
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
                Section {
                    if let agency = alarm.transitAgencyName {
                        LabeledContent(NSLocalizedString("Agency", bundle: bundle, comment: "")) { Text(agency) }
                    }
                    if let route = alarm.transitRouteName {
                        LabeledContent(NSLocalizedString("Route", bundle: bundle, comment: "")) {
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
                        LabeledContent(NSLocalizedString("Stop", bundle: bundle, comment: "")) { Text(stop) }
                    }
                } header: {
                    Text("Transit", bundle: bundle)
                }
            }

            // MARK: Status
            Section {
                LabeledContent(NSLocalizedString("State", bundle: bundle, comment: "")) {
                    HStack(spacing: 6) {
                        Circle().fill(stateColor).frame(width: 10, height: 10)
                        Text(alarm.state.rawValue.capitalized)
                    }
                }
                LabeledContent(NSLocalizedString("Trigger", bundle: bundle, comment: "")) {
                    Text(NSLocalizedString(alarm.regionEvent.rawValue, bundle: bundle, comment: ""))
                }
                if alarm.triggerMode == .time {
                    LabeledContent(NSLocalizedString("trigger.leadTime.label", bundle: bundle, comment: "")) {
                        Text(String(format: NSLocalizedString("trigger.leadTime.value", bundle: bundle, comment: ""),
                                    alarm.leadTimeMinutes))
                    }
                } else {
                    LabeledContent(NSLocalizedString("Radius", bundle: bundle, comment: "")) {
                        Text(distanceUnit.formatted(meters: alarm.radius))
                    }
                }
                if alarm.isRepeating {
                    LabeledContent(NSLocalizedString("Repeat", bundle: bundle, comment: "")) {
                        Text("On", bundle: bundle)
                    }
                }
                if let window = alarm.windowLabel(using: timeFormat) {
                    LabeledContent(NSLocalizedString("Time window", bundle: bundle, comment: "")) {
                        Text(window)
                    }
                }
                if let daysLabel = alarm.activeDaysLabel(locale: Locale(identifier: LanguageManager.shared.currentLanguage.rawValue), bundle: bundle) {
                    LabeledContent(NSLocalizedString("Active days", bundle: bundle, comment: "")) {
                        Text(daysLabel)
                    }
                }
                if alarm.notificationSound == .vibrate {
                    LabeledContent(NSLocalizedString("Sound", bundle: bundle, comment: "")) {
                        Image(systemName: "bell.slash.fill")
                            .foregroundStyle(Color.secondary)
                    }
                }
            } header: {
                Text("Status", bundle: bundle)
            }

            // MARK: Auto-Notify
            if alarm.notifyContact {
                Section {
                    if alarm.notifyContactList.isEmpty {
                        Text("No contacts saved for this alarm.", bundle: bundle)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(alarm.notifyContactList) { contact in
                            HStack(spacing: 12) {
                                Image(systemName: contact.systemImage)
                                    .foregroundStyle(.green)
                                    .frame(width: 20)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(contact.name)
                                        .font(.body)
                                    Text(contact.value)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                } header: {
                    Label("Auto-Notify", systemImage: "megaphone.fill")
                }
            }

            // MARK: History
            Section {
                LabeledContent(NSLocalizedString("Times triggered", bundle: bundle, comment: "")) {
                    Text(alarm.triggerCount == 0
                         ? NSLocalizedString("Never", bundle: bundle, comment: "")
                         : "\(alarm.triggerCount)")
                }
                if let last = alarm.lastTriggeredAt {
                    LabeledContent(NSLocalizedString("Last triggered", bundle: bundle, comment: "")) {
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
                    LabeledContent(NSLocalizedString("Note", bundle: bundle, comment: "")) {
                        Text(alarm.note)
                    }
                }
            } header: {
                Text("History", bundle: bundle)
            }

            // MARK: Simulator-only trigger — stripped from device builds at compile time
            #if targetEnvironment(simulator)
            Section {
                Button {
                    simulatorCountdown = 5
                    NotificationSound.installBundledSoundsIfNeeded()
                    Task {
                        for remaining in stride(from: 5, through: 1, by: -1) {
                            simulatorCountdown = remaining
                            try? await Task.sleep(for: .seconds(1))
                        }
                        simulatorCountdown = nil
                        alarmManager.handleRegionEvent(
                            regionID: alarm.id.uuidString,
                            event: alarm.regionEvent
                        )
                    }
                } label: {
                    if let remaining = simulatorCountdown {
                        Label("Firing in \(remaining)…", systemImage: "timer")
                    } else {
                        Label("Simulate Trigger Now", systemImage: "location.fill.viewfinder")
                    }
                }
                .foregroundStyle(alarm.isActive && simulatorCountdown == nil ? Color.red : Color.secondary)
                .disabled(!alarm.isActive || simulatorCountdown != nil)

                Text("Press, then lock the Simulator (⌘L) — the alarm fires after 5 seconds.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Label("Simulator Testing", systemImage: "hammer.fill")
            }
            #endif

            // MARK: Actions
            Section {
                NavigationLink {
                    AddAlarmView(existingAlarm: alarm)
                } label: {
                    Text("Edit Alarm", bundle: bundle)
                }
                Button {
                    alarmManager.toggleActive(alarm)
                } label: {
                    Text(alarm.isActive
                         ? NSLocalizedString("Disable alarm", bundle: bundle, comment: "")
                         : NSLocalizedString("Enable alarm", bundle: bundle, comment: ""))
                }
                .foregroundColor(alarm.isActive ? .orange : .green)

                ShareLink(item: shareURLString) {
                    Label {
                        Text("Share Alarm Location", bundle: bundle)
                    } icon: {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
                .simultaneousGesture(TapGesture().onEnded {
                    DebugLogger.shared.log("Share Alarm Location tapped: '\(alarm.name)' lat=\(alarm.latitude) lon=\(alarm.longitude)", category: "UI")
                })
            }
        }
        .navigationTitle(alarm.name)
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            DebugLogger.shared.log("Alarm detail viewed: '\(alarm.name)' state=\(alarm.state.rawValue) triggerCount=\(alarm.triggerCount)", category: "UI")
        }
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
        AlarmDetailView(alarm: NapAlarm.preview)
    }
    .environmentObject(AlarmManager())
}
