// AddAlarmView.swift
// Form for creating or editing a geo-location alarm.
// Embeds MapPickerView for coordinate selection.

internal import SwiftUI
internal import CoreLocation

struct AddAlarmView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var alarmManager: AlarmManager
    @StateObject private var viewModel = AlarmViewModel()

    /// Pass an existing alarm to switch to Edit mode.
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

            // MARK: Trigger settings
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

            // MARK: Validation error
            if let error = viewModel.validationError {
                Section {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.footnote)
                }
            }

            // MARK: Save button
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
            if let alarm = existingAlarm {
                viewModel.load(alarm: alarm)
            }
        }
    }

    // MARK: - Save
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
