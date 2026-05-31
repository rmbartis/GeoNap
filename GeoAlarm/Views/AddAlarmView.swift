// AddAlarmView.swift
// Form for creating or editing a geo-location alarm.

import SwiftUI
import CoreLocation
import MapKit
import MessageUI

struct AddAlarmView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.languageBundle) private var bundle
    @EnvironmentObject var alarmManager: AlarmManager
    @StateObject private var viewModel = AlarmViewModel()
    @StateObject private var searchService = LocationSearchService()
    @State private var showContactPicker  = false
    @State private var showManualEntry    = false
    @State private var showNoMailAlert    = false

    @AppStorage(AppStorageKey.distanceUnit) private var distanceUnitRaw  = DistanceUnit.imperial.rawValue
    @AppStorage(AppStorageKey.timeFormat)   private var timeFormatRaw    = TimeFormat.twelveHour.rawValue
    @AppStorage(AppStorageKey.coordFormat)  private var coordFormatRaw   = CoordFormat.dd.rawValue
    private var distanceUnit: DistanceUnit { DistanceUnit(rawValue: distanceUnitRaw) ?? .imperial }
    private var timeFormat:   TimeFormat   { TimeFormat(rawValue: timeFormatRaw)     ?? .twelveHour }
    private var coordFormat:  CoordFormat  { CoordFormat(rawValue: coordFormatRaw)   ?? .dd }

    // Manual coordinate entry state
    @State private var coordLatEntry   = ""
    @State private var coordLonEntry   = ""
    @State private var coordEntryError: String? = nil
    @State private var showCoordEntry  = false

    /// Slider binding in the user's chosen unit; viewModel.radius always stores metres.
    private var radiusInUnit: Binding<Double> {
        Binding(
            get: { distanceUnit.fromMeters(viewModel.radius) },
            set: { viewModel.radius = distanceUnit.toMeters($0) }
        )
    }

    var existingAlarm: NapAlarm?
    private var isEditing: Bool { existingAlarm != nil }

    var body: some View {
        Form {

            // MARK: Name & Note
            Section {
                TextField(NSLocalizedString("Name (e.g. Penn Station)", bundle: bundle, comment: ""), text: $viewModel.name)
                    .autocorrectionDisabled()
                TextField(NSLocalizedString("Note (shown in notification)", bundle: bundle, comment: ""), text: $viewModel.note)
            } header: {
                Text("Alarm Details", bundle: bundle)
            }

            // MARK: Location
            Section {

                // Address search field
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField(NSLocalizedString("Search address or place…", bundle: bundle, comment: ""), text: $searchService.query)
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
                    longitude: $viewModel.longitude,
                    radius: $viewModel.radius
                )
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))

                // MARK: Manual coordinate entry
                DisclosureGroup(
                    isExpanded: $showCoordEntry,
                    content: {
                        VStack(alignment: .leading, spacing: 10) {
                            // Format display
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 4) {
                                    Text("Format:", bundle: bundle)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text(NSLocalizedString(coordFormat.fullLabel, bundle: bundle, comment: ""))
                                        .font(.caption.bold())
                                        .foregroundColor(.accentColor)
                                }
                                Text("(Change format in Settings)", bundle: bundle)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }

                            // Latitude field
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Latitude", bundle: bundle)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                TextField(coordFormat.latPlaceholder, text: $coordLatEntry)
                                    .keyboardType(.decimalPad)
                                    .font(.system(.body, design: .monospaced))
                                    .autocorrectionDisabled()
                                    .textInputAutocapitalization(.characters)
                                    .padding(8)
                                    .background(Color(.systemGray6))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }

                            // Longitude field
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Longitude", bundle: bundle)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                TextField(coordFormat.lonPlaceholder, text: $coordLonEntry)
                                    .keyboardType(.decimalPad)
                                    .font(.system(.body, design: .monospaced))
                                    .autocorrectionDisabled()
                                    .textInputAutocapitalization(.characters)
                                    .padding(8)
                                    .background(Color(.systemGray6))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }

                            // Error message
                            if let err = coordEntryError {
                                HStack(spacing: 6) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(.red)
                                        .font(.caption)
                                    Text(err)
                                        .font(.caption)
                                        .foregroundColor(.red)
                                }
                            }

                            // Apply button
                            Button {
                                applyCoordinates()
                            } label: {
                                Label {
                                    Text("Apply Coordinates", bundle: bundle)
                                } icon: {
                                    Image(systemName: "checkmark.circle.fill")
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(coordLatEntry.isEmpty || coordLonEntry.isEmpty)
                        }
                        .padding(.vertical, 6)
                    },
                    label: {
                        Label {
                            Text("Manual Coordinates Entry", bundle: bundle)
                        } icon: {
                            Image(systemName: "number.circle")
                        }
                        .font(.body)
                    }
                )

                if viewModel.hasLocation {
                    LabeledContent(NSLocalizedString("Latitude", bundle: bundle, comment: ""),
                                   value: CoordinateParser.format(latitude: viewModel.latitude, format: coordFormat))
                    LabeledContent(NSLocalizedString("Longitude", bundle: bundle, comment: ""),
                                   value: CoordinateParser.format(longitude: viewModel.longitude, format: coordFormat))
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: "mappin.slash")
                            .foregroundColor(.secondary)
                        Text("Search above or tap the map to set a location", bundle: bundle)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            } header: {
                Text("Location", bundle: bundle)
            }

            // MARK: Trigger
            Section {
                Picker(selection: $viewModel.regionEvent) {
                    ForEach(RegionEvent.allCases, id: \.self) { event in
                        Text(NSLocalizedString(event.rawValue, bundle: bundle, comment: "")).tag(event)
                    }
                } label: {
                    Text("Event", bundle: bundle)
                }
                .pickerStyle(.segmented)

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Radius", bundle: bundle)
                        Spacer()
                        Text(distanceUnit.formatted(meters: viewModel.radius))
                            .foregroundColor(.secondary)
                    }
                    Slider(value: radiusInUnit,
                           in: distanceUnit.sliderRange,
                           step: distanceUnit.sliderStep)
                }
            } header: {
                Text("Trigger", bundle: bundle)
            }

            // MARK: Sound / Vibrate
            SoundPickerSection(selection: $viewModel.notificationSound)

            // MARK: Repeat (hysteresis)
            Section {
                Toggle(isOn: $viewModel.isRepeating) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Repeat", bundle: bundle)
                            .font(.body)
                        Text("Auto-resets after you leave — fires again every trip", bundle: bundle)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                if viewModel.isRepeating {
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle")
                            .foregroundColor(.blue)
                        Text("Hysteresis: alarm won't re-trigger until you've fully exited and re-entered the region.", bundle: bundle)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                // MARK: Time Window
                Toggle(isOn: $viewModel.hasTimeWindow) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Active time window", bundle: bundle)
                            .font(.body)
                        Text("Only fire within a set time range", bundle: bundle)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                if viewModel.hasTimeWindow {
                    DatePicker(
                        selection: $viewModel.windowStart,
                        displayedComponents: .hourAndMinute
                    ) {
                        Text("From", bundle: bundle)
                    }
                    .datePickerStyle(.compact)
                    .environment(\.locale, timeFormat.pickerLocale)
                    DatePicker(
                        selection: $viewModel.windowEnd,
                        displayedComponents: .hourAndMinute
                    ) {
                        Text("Until", bundle: bundle)
                    }
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
            } header: {
                Text("Schedule", bundle: bundle)
            }

            // MARK: Active Days
            Section {
                HStack(spacing: 4) {
                    let dayKeys = ["day.su", "day.mo", "day.tu", "day.we", "day.th", "day.fr", "day.sa"]
                    ForEach(Array(zip(1...7, dayKeys)), id: \.0) { weekday, key in
                        let isOn = viewModel.activeDays.contains(weekday)
                        Button {
                            toggleDay(weekday)
                        } label: {
                            Text(NSLocalizedString(key, bundle: bundle, comment: ""))
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
            } header: {
                Text("Active Days", bundle: bundle)
            }

            // MARK: Auto-Notify Contacts
            Section {
                Toggle(isOn: $viewModel.notifyContact) {
                    Label {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Auto-Notify", bundle: bundle)
                                .font(.body)
                            Text("Share your location when this alarm fires",
                                 bundle: bundle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "bell.badge")
                    }
                }

                if viewModel.notifyContact {
                    // Existing contacts — swipe to delete
                    ForEach(viewModel.notifyContactList) { contact in
                        contactRow(contact)
                    }
                    .onDelete { offsets in
                        viewModel.notifyContactList.remove(atOffsets: offsets)
                    }

                    // Add from Contacts app
                    Button {
                        showContactPicker = true
                    } label: {
                        Label("Add from Contacts",
                              systemImage: "person.crop.circle.badge.plus")
                    }

                    // Add manually
                    Button {
                        showManualEntry = true
                    } label: {
                        Label("Add Manually", systemImage: "plus.circle")
                    }

                    if viewModel.notifyContact && viewModel.notifyContactList.isEmpty {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.circle")
                                .foregroundColor(.orange)
                            Text("Add at least one contact to enable Auto-Notify.",
                                 bundle: bundle)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            } header: {
                Text("Auto-Notify", bundle: bundle)
            } footer: {
                Text("Email and SMS contacts both require your approval before the message is sent. The Mail or Messages app will open for confirmation when the alarm fires.",
                     bundle: bundle)
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
                Button {
                    saveAlarm()
                } label: {
                    if isEditing {
                        Text("Update Alarm", bundle: bundle)
                    } else {
                        Text("Save Alarm", bundle: bundle)
                    }
                }
                .frame(maxWidth: .infinity)
                .disabled(!viewModel.isValid)
            }
        }
        .navigationTitle(isEditing
            ? Text("Edit Alarm", bundle: bundle)
            : Text("New Alarm", bundle: bundle))
        .navigationBarTitleDisplayMode(.inline)
        .background(
            ContactPickerView(isPresented: $showContactPicker) { contact in
                addContact(contact)
            }
        )
        .sheet(isPresented: $showManualEntry) {
            AddContactManuallySheet { contact in
                addContact(contact)
            }
        }
        .alert("No Mail Account", isPresented: $showNoMailAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("No mail account is set up on this device. Go to Settings → Mail → Accounts to add one before using email Auto-Notify contacts.")
        }
        .onAppear {
            if let alarm = existingAlarm {
                viewModel.load(alarm: alarm)
                // Pre-fill the coordinate entry fields with the alarm's location
                coordLatEntry = CoordinateParser.format(latitude:  alarm.latitude,  format: coordFormat)
                coordLonEntry = CoordinateParser.format(longitude: alarm.longitude, format: coordFormat)
            }
        }
    }

    // MARK: - Contact helpers

    @ViewBuilder
    private func contactRow(_ contact: NotifyContact) -> some View {
        HStack(spacing: 12) {
            Image(systemName: contact.systemImage)
                .foregroundStyle(.blue)
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

    private func addContact(_ contact: NotifyContact) {
        // Block email contacts when no mail account is configured on the device.
        if contact.isEmail && !MFMailComposeViewController.canSendMail() {
            showNoMailAlert = true
            return
        }
        guard !viewModel.notifyContactList.contains(where: { $0.value == contact.value }) else { return }
        viewModel.notifyContactList.append(contact)
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
        if days == Set(1...7) { return NSLocalizedString("Every day", bundle: bundle, comment: "") }
        let weekdays: Set<Int> = [2, 3, 4, 5, 6]
        let weekend:  Set<Int> = [1, 7]
        if days == weekdays { return NSLocalizedString("Weekdays only", bundle: bundle, comment: "") }
        if days == weekend  { return NSLocalizedString("Weekends only", bundle: bundle, comment: "") }
        let keys = ["day.su", "day.mo", "day.tu", "day.we", "day.th", "day.fr", "day.sa"]
        return days.sorted().map { NSLocalizedString(keys[$0 - 1], bundle: bundle, comment: "") }.joined(separator: " ")
    }

    private func toggleDay(_ weekday: Int) {
        if viewModel.activeDays.contains(weekday) {
            guard viewModel.activeDays.count > 1 else { return }
            viewModel.activeDays.remove(weekday)
        } else {
            viewModel.activeDays.insert(weekday)
        }
    }

    // MARK: - Coordinate entry

    private func applyCoordinates() {
        coordEntryError = nil
        do {
            let coord = try CoordinateParser.parse(
                latString: coordLatEntry,
                lonString: coordLonEntry,
                format: coordFormat
            )
            viewModel.latitude  = coord.latitude
            viewModel.longitude = coord.longitude
            coordEntryError = nil
            showCoordEntry = false
        } catch let err as CoordinateParseError {
            coordEntryError = err.errorDescription
        } catch {
            coordEntryError = error.localizedDescription
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

// MARK: - AddContactManuallySheet

/// Sheet for typing in a contact name and phone number or email address.
struct AddContactManuallySheet: View {

    var onAdd: (NotifyContact) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var name  = ""
    @State private var value = ""

    // MARK: - Validation

    private var trimmedValue: String { value.trimmingCharacters(in: .whitespaces) }

    /// True when the value field contains a valid phone or email.
    private var isValueValid: Bool {
        guard !trimmedValue.isEmpty else { return false }
        return trimmedValue.contains("@") ? isValidEmail(trimmedValue) : isValidPhone(trimmedValue)
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && isValueValid
    }

    /// Inline error shown while the user types — nil when empty or valid.
    private var valueError: String? {
        guard !trimmedValue.isEmpty, !isValueValid else { return nil }
        if trimmedValue.contains("@") {
            return "Invalid email — must be in the form name@example.com"
        } else {
            return "Invalid phone — use digits, spaces, dashes, parentheses, or a leading +"
        }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .textContentType(.name)
                        .autocorrectionDisabled()
                    TextField("Phone or email", text: $value)
                        .keyboardType(.emailAddress)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } footer: {
                    if let error = valueError {
                        Label(error, systemImage: "exclamationmark.circle")
                            .font(.caption)
                            .foregroundStyle(.red)
                    } else {
                        Text("Phone (e.g. +1 555-1234) or email (e.g. name@example.com).")
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Add Contact")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onAdd(NotifyContact(
                            name:  name.trimmingCharacters(in: .whitespaces),
                            value: trimmedValue
                        ))
                        dismiss()
                    }
                    .disabled(!isValid)
                }
            }
        }
    }

    // MARK: - Validators

    /// Phone: optional leading +, then digits/spaces/dashes/parentheses/dots,
    /// with at least 7 digits total (covers most national + international formats).
    private func isValidPhone(_ s: String) -> Bool {
        let allowed = CharacterSet(charactersIn: "+0123456789 ()-.")
        guard s.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return false }
        let digitCount = s.filter(\.isNumber).count
        return digitCount >= 7
    }

    /// Email: local@domain.tld — basic structural check, not RFC 5322 exhaustive.
    private func isValidEmail(_ s: String) -> Bool {
        let parts = s.split(separator: "@", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { return false }
        let local  = String(parts[0])
        let domain = String(parts[1])
        return !local.isEmpty && domain.contains(".") && !domain.hasPrefix(".") && !domain.hasSuffix(".")
    }
}
