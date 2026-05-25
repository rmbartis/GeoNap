// SettingsView.swift
// User-facing preferences sheet: distance units and time format.

import SwiftUI

struct SettingsView: View {

    @AppStorage(AppStorageKey.distanceUnit) private var distanceUnitRaw = DistanceUnit.metric.rawValue
    @AppStorage(AppStorageKey.timeFormat)   private var timeFormatRaw   = TimeFormat.twelveHour.rawValue

    @Environment(\.dismiss) private var dismiss

    private var distanceUnit: DistanceUnit {
        DistanceUnit(rawValue: distanceUnitRaw) ?? .metric
    }

    private var timeFormat: TimeFormat {
        TimeFormat(rawValue: timeFormatRaw) ?? .twelveHour
    }

    var body: some View {
        NavigationStack {
            Form {

                // MARK: Units
                Section {
                    Picker("Distance", selection: $distanceUnitRaw) {
                        ForEach(DistanceUnit.allCases) { unit in
                            Text(unit.label).tag(unit.rawValue)
                        }
                    }
                } header: {
                    Text("Units")
                } footer: {
                    Text("Controls how radius is displayed and entered when creating alarms.")
                }

                // MARK: Time
                Section {
                    Picker("Clock", selection: $timeFormatRaw) {
                        ForEach(TimeFormat.allCases) { format in
                            Text(format.label).tag(format.rawValue)
                        }
                    }
                } header: {
                    Text("Time")
                } footer: {
                    Text("Used when displaying and entering alarm time windows.")
                }

                // MARK: Help
                Section {
                    NavigationLink(destination: HelpView()) {
                        Label("Help & User Guide", systemImage: "questionmark.circle")
                    }
                }

                // MARK: Preview
                Section("Preview") {
                    LabeledContent("Sample radius") {
                        Text(distanceUnit.formatted(meters: 500))
                            .foregroundStyle(.secondary)
                    }
                    LabeledContent("Sample time") {
                        Text(timeFormat.formatTime(Date()))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    SettingsView()
}
