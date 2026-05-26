// AddAlarmView.swift
// Form for creating or editing a geo-location alarm.

import SwiftUI
import CoreLocation
import MapKit

struct AddAlarmView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var alarmManager: AlarmManager
    @StateObject private var viewModel = AlarmViewModel()
    @StateObject private var searchService = LocationSearchService()

    @AppStorage(AppStorageKey.distanceUnit) private var distanceUnitRaw  = DistanceUnit.metric.rawValue
    @AppStorage(AppStorageKey.timeFormat)   private var timeFormatRaw    = TimeFormat.twelveHour.rawValue
    private var distanceUnit: DistanceUnit { DistanceUnit(rawValue: distanceUnitRaw) ?? .metric }
    private var timeFormat:   TimeFormat   { TimeFormat(rawValue: timeFormatRaw)     ?? .twelveHour }

    /// Slider binding in the user's chosen unit; viewModel.radius always stores metres.
    private var radiusInUnit: Binding<Double> {
        Binding(
            get: { distanceUnit.fromMeters(viewModel.radius) },
            set: { viewModel.radius = distanceUnit.toMeters($0) }
        )
    }

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

                // Address search field
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search address or place…", text: $searchService.query)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    if searchService.isSearching {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else if !searchService.query.isEmpty {
                        Button {
                            searchService.clear()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }

                // Autocomplete results
                if !searchService.completions.isEmpty {
                    ForEach(searchService.completions, id: \.self) { completion in
                        Button {
                            Task {
                                if let coord = await searchService.resolve(completion) {
                                    viewModel.latitude  = coord.latitude
                                    viewModel.longitude = coord.longitude
                                    // Pre-fill name only if it's still empty
                                    if viewModel.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                        viewModel.name = completion.title
                                    }
                                }
                                searchService.clear()
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(completion.title)
                                    .font(.body)
                                    .foregroundColor(.primary)
                                if !completion.subtitle.isEmpty {
                                    Text(completion.subtitle)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }

                MapPickerView(
                    latitude: $viewModel.latitude,
                    longitude: $viewModel.longitude
                )
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))

                if viewModel.hasLocation {
                    LabeledContent("Latitude",  value: String(format: "%.5f", viewModel.latitude))
                    LabeledContent("Longitude", value: String(format: "%.5f", viewModel.longitude))
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: "mappin.slash")
                            .foregroundColor(.secondary)
                        Text("Search above or tap the map to set a location")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
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
                        Text(distanceUnit.formatted(meters: viewModel.radius))
                            .foregroundColor(.secondary)
                    }
                    Slider(value: radiusInUnit,
                           in: distanceUnit.sliderRange,
                           step: distanceUnit.sliderStep)
                }
            }

            // MARK: Sound / Vibrate
            SoundPickerSection(selection: $viewModel.notificationSound)

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

                // MARK: Time Window
                Toggle(isOn: $viewModel.hasTimeWindow) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Active time window")
                            .font(.body)
                        Text("Only fire within a set time range")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                if viewModel.hasTimeWindow {
                    DatePicker(
                        "From",
                        selection: $viewModel.windowStart,
                        displayedComponents: .hourAndMinute
                    )
                    .datePickerStyle(.compact)
                    .environment(\.locale, timeFormat.pickerLocale)
                    DatePicker(
                        "Until",
                        selection: $viewModel.windowEnd,
                        displayedComponents: .hourAndMinute
                    )
                    .datePickerStyle(.compact)
                    .environment(\.locale, timeFormat.pickerLocale)

                    // Summary label — shows duration and whether it's overnight
                    let isOvernight: Bool = {
                        let cal = Calendar.current
                        let s = cal.component(.hour, from: viewModel.windowStart) * 60
                              + cal.component(.minute, from: viewModel.windowStart)
                        let e = cal.component(.hour, from: viewModel.windowEnd) * 60
                              + cal.component(.minute, from: viewModel.windowEnd)
                        return s > e
                    }()

                    HStack(spacing: 6) {
                        Image(systemName: isOvernight ? "moon.stars" : "checkmark.circle")
                            .foregroundColor(isOvernight ? .orange : .green)
                            .font(.caption)
                        Text(windowSummary)
                            .font(.caption)
                            .foregroundColor(isOvernight ? .orange : .secondary)
                    }

                    if isOvernight {
                        HStack(spacing: 8) {
                            Image(systemName: "info.circle")
                                .foregroundColor(.blue)
                            Text("Overnight span — active from \(timeFormat.formatTime(viewModel.windowStart)) through midnight until \(timeFormat.formatTime(viewModel.windowEnd)). If still in the region when the window closes, the alarm deactivates automatically.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

            // MARK: Active Days
            Section("Active Days") {
                HStack(spacing: 4) {
                    ForEach(Array(zip(1...7, ["Su","Mo","Tu","We","Th","Fr","Sa"])), id: \.0) { weekday, label in
                        let isOn = viewModel.activeDays.contains(weekday)
                        Button {
                            toggleDay(weekday)
                        } label: {
                            Text(label)
                                .font(.caption2.weight(.semibold))
                                .frame(maxWidth: .infinity, minHeight: 36)
                                .background(isOn ? Color.accentColor : Color(.systemGray5))
                                .foregroundColor(isOn ? .white : .secondary)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                    }
                }
                HStack(spacing: 6) {
                    Image(systemName: viewModel.activeDays == Set(1...7) ? "checkmark.circle" : "calendar")
                        .foregroundColor(viewModel.activeDays == Set(1...7) ? .green : .accentColor)
                    Text(activeDaysLabel)
                }
                .font(.caption)
                .foregroundColor(.secondary)
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

    // MARK: - Time window summary

    /// Plain-English description of the active duration, shown below the pickers.
    private var windowSummary: String {
        let cal = Calendar.current
        let startMins = cal.component(.hour,   from: viewModel.windowStart) * 60
                      + cal.component(.minute, from: viewModel.windowStart)
        let endMins   = cal.component(.hour,   from: viewModel.windowEnd)   * 60
                      + cal.component(.minute, from: viewModel.windowEnd)

        guard startMins != endMins else { return "Active all day" }

        let isOvernight  = startMins > endMins
        let durationMins = isOvernight
            ? (24 * 60 - startMins) + endMins
            : endMins - startMins

        let hrs  = durationMins / 60
        let mins = durationMins % 60
        let durationStr: String = {
            switch (hrs, mins) {
            case (0, let m): return "\(m) min"
            case (let h, 0): return "\(h) hr"
            default:         return "\(hrs) hr \(mins) min"
            }
        }()

        let startStr = timeFormat.formatTime(viewModel.windowStart)
        let endStr   = timeFormat.formatTime(viewModel.windowEnd)

        return isOvernight
            ? "Active \(durationStr) · \(startStr) → \(endStr) next day"
            : "Active \(durationStr) · \(startStr) – \(endStr)"
    }

    // MARK: - Active days helpers

    private var activeDaysLabel: String {
        let days = viewModel.activeDays
        if days == Set(1...7) { return "Every day" }
        let weekdays: Set<Int> = [2, 3, 4, 5, 6]
        let weekend:  Set<Int> = [1, 7]
        if days == weekdays { return "Weekdays only" }
        if days == weekend  { return "Weekends only" }
        let symbols = ["Su","Mo","Tu","We","Th","Fr","Sa"]
        return days.sorted().map { symbols[$0 - 1] }.joined(separator: " ")
    }

    private func toggleDay(_ weekday: Int) {
        if viewModel.activeDays.contains(weekday) {
            guard viewModel.activeDays.count > 1 else { return }
            viewModel.activeDays.remove(weekday)
        } else {
            viewModel.activeDays.insert(weekday)
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
