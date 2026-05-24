// AddAlarmView.swift
// Form for creating or editing a geo-location alarm.

import SwiftUI
import CoreLocation

struct AddAlarmView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var alarmManager: AlarmManager
    @StateObject private var viewModel = AlarmViewModel()

    var existingAlarm: GeoAlarm?
    private var isEditing: Bool { existingAlarm != nil }

    var body: some View {
        Form {

            // MARK: Name & Note
            Section("Alarm Details") {
                TextField("Name (e.g. Penn Station)", text: $viewModel.name)
                    .autocorrectionDisabled()
                TextField("Note (shown in notification)", text: $viewModel.note)
            }

            // MARK: Location
            Section("Location") {
                MapPickerView(
                    latitude: $viewModel.latitude,
                    longitude: $viewModel.longitude
                )
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))

                if viewModel.latitude != 0 || viewModel.longitude != 0 {
                    LabeledContent("Latitude",  value: String(format: "%.5f", viewModel.latitude))
                    LabeledContent("Longitude", value: String(format: "%.5f", viewModel.longitude))
                }
            }

            // MARK: Trigger
            Section("Trigger") {
                Picker("Event", selection: $viewModel.regionEvent) {
                    ForEach(RegionEvent.allCases, id: \.self) { event in
                        Text(event.rawValue).tag(event)
                    }
                }
                .pickerStyle(.segmented)

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Radius")
                        Spacer()
                        Text("\(Int(viewModel.radius)) m")
                            .foregroundColor(.secondary)
                    }
                    Slider(value: $viewModel.radius, in: 50...2000, step: 50)
                }
            }

            // MARK: Repeat (hysteresis)
            Section("Schedule") {
                Toggle(isOn: $viewModel.isRepeating) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Repeat")
                            .font(.body)
                        Text("Auto-resets after you leave — fires again every trip")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                if viewModel.isRepeating {
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle")
                            .foregroundColor(.blue)
                        Text("Hysteresis: alarm won't re-trigger until you've fully exited and re-entered the region.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            // MARK: Validation error
            if let error = viewModel.validationError {
                Section {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.footnote)
                }
            }

            // MARK: Save
            Section {
                Button(isEditing ? "Update Alarm" : "Save Alarm") {
                    saveAlarm()
                }
                .frame(maxWidth: .infinity)
                .disabled(!viewModel.isValid)
            }
        }
        .navigationTitle(isEditing ? "Edit Alarm" : "New Alarm")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if let alarm = existingAlarm { viewModel.load(alarm: alarm) }
        }
    }

    private func saveAlarm() {
        guard let alarm = viewModel.buildAlarm() else { return }
        if isEditing {
            alarmManager.update(alarm: alarm)
        } else {
            alarmManager.add(alarm: alarm)
        }
        dismiss()
    }
}

#Preview {
    NavigationStack {
        AddAlarmView()
    }
    .environmentObject(AlarmManager())
    .environmentObject(LocationManager())
}
