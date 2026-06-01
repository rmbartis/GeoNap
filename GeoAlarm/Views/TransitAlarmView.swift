// TransitAlarmView.swift
// 4-step wizard for creating a transit stop alarm using a GTFS feed.
//  Step 1 — Agency (pick from curated list or enter custom URL)
//  Step 2 — Route   (filter by type, search by name)
//  Step 3 — Stop    (search + sort by proximity to current location)
//  Step 4 — Confirm (identical options to Location alarm; name/location pre-populated)

import SwiftUI
import SwiftData
import CoreLocation

// MARK: - Sheet wrapper

struct TransitAlarmSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var alarmManager: AlarmManager
    @EnvironmentObject var locationManager: LocationManager

    var body: some View {
        TransitAlarmView(
            onSave: { alarm in
                alarmManager.add(alarm: alarm)
                dismiss()
            },
            onCancel: { dismiss() }
        )
    }
}

// MARK: - Main wizard

struct TransitAlarmView: View {

    var onSave:   (NapAlarm) -> Void
    var onCancel: () -> Void

    @EnvironmentObject var locationManager: LocationManager
    @Environment(\.languageBundle) private var bundle

    // User preferences (mirrors AddAlarmView)
    @AppStorage(AppStorageKey.distanceUnit) private var distanceUnitRaw = DistanceUnit.imperial.rawValue
    @AppStorage(AppStorageKey.timeFormat)   private var timeFormatRaw   = TimeFormat.twelveHour.rawValue
    private var distanceUnit: DistanceUnit { DistanceUnit(rawValue: distanceUnitRaw) ?? .imperial }
    private var timeFormat:   TimeFormat   { TimeFormat(rawValue: timeFormatRaw)     ?? .twelveHour }

    // Wizard step
    @State private var step: WizardStep = .agency

    // Step 1 — Agency
    @State private var selectedFeed:  GTFSFeedModel? = nil
    @State private var customURL:     String = ""
    @State private var agencyFilter:  String = ""
    @State private var showCustomURL: Bool   = false

    // Step 2 — Route
    @State private var selectedRoute: GTFSRoute? = nil
    @State private var routeFilter:   String = ""

    // Step 3 — Stop
    @State private var selectedStop: GTFSStop? = nil
    @State private var stopFilter:   String = ""

    // Agency list — which country groups are open
    @State private var expandedRegions: Set<String> = []

    // Step 4 — Alarm details (mirrors AddAlarmView / AlarmViewModel fields)
    @State private var alarmName:         String = ""
    @State private var note:              String = ""
    @State private var radius:            Double = 200
    @State private var regionEvent:       RegionEvent = .onEntry
    @State private var isRepeating:       Bool = false
    @State private var notificationSound: NotificationSound = .default

    // Time window
    @State private var hasTimeWindow: Bool  = false
    @State private var windowStart:   Date  = Calendar.current.date(bySettingHour: 8,  minute: 0, second: 0, of: Date()) ?? Date()
    @State private var windowEnd:     Date  = Calendar.current.date(bySettingHour: 22, minute: 0, second: 0, of: Date()) ?? Date()

    // Active days (1 = Sun … 7 = Sat)
    @State private var activeDays: Set<Int> = Set(1...7)

    // Auto-Notify contacts
    @State private var notifyContact:     Bool             = false
    @State private var notifyContactList: [NotifyContact]  = []
    @State private var showContactPicker: Bool             = false
    @State private var showManualEntry:   Bool             = false

    @StateObject private var service = GTFSService()

    /// Radius binding in the user's chosen unit; radius always stores metres.
    private var radiusInUnit: Binding<Double> {
        Binding(
            get: { distanceUnit.fromMeters(radius) },
            set: { radius = distanceUnit.toMeters($0) }
        )
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .agency:  agencyStep
                case .route:   routeStep
                case .stop:    stopStep
                case .confirm: confirmStep
                }
            }
            .navigationTitle(Text(LocalizedStringKey(step.titleKey), bundle: bundle))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { onCancel() } label: {
                        Text("Cancel", bundle: bundle)
                    }
                }
                if step != .agency {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button { goBack() } label: {
                            Label {
                                Text("Back", bundle: bundle)
                            } icon: {
                                Image(systemName: "chevron.left")
                            }
                        }
                    }
                }
            }
            // Contact picker sheets at NavigationStack level to avoid
            // first-presentation white-screen issue with Section-level sheets.
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
        }
        // Pre-populate contact list from global defaults when Auto-Notify is first enabled.
        .onChange(of: notifyContact) { _, isOn in
            if isOn && notifyContactList.isEmpty {
                notifyContactList = [NotifyContact].loadGlobalDefaults()
            }
        }
    }

    // MARK: - Step 1: Agency

    private var agencyStep: some View {
        List {
            let regions = CuratedFeeds.regions
            let isSearching = !agencyFilter.isEmpty
            ForEach(regions, id: \.self) { region in
                let feeds = CuratedFeeds.all.filter {
                    $0.region.hasPrefix(region)
                }.filter {
                    agencyFilter.isEmpty ||
                    $0.name.localizedCaseInsensitiveContains(agencyFilter) ||
                    $0.region.localizedCaseInsensitiveContains(agencyFilter)
                }
                if !feeds.isEmpty {
                    DisclosureGroup(
                        isExpanded: Binding(
                            get: { isSearching || expandedRegions.contains(region) },
                            set: { open in
                                if open { expandedRegions.insert(region) }
                                else    { expandedRegions.remove(region) }
                            }
                        )
                    ) {
                        ForEach(feeds) { feed in
                            Button {
                                pickCuratedFeed(feed)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(feed.name).foregroundColor(.primary)
                                    let city = feed.region
                                        .components(separatedBy: " · ")
                                        .dropFirst()
                                        .joined(separator: " · ")
                                    Text(city.isEmpty ? feed.routeTypes : "\(city) · \(feed.routeTypes)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    } label: {
                        Text(region)
                            .font(.headline)
                            .foregroundColor(.primary)
                    }
                }
            }

            Section {
                if showCustomURL {
                    TextField("https://example.com/gtfs.zip", text: $customURL)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                    Button {
                        guard !customURL.isEmpty else { return }
                        let model = GTFSFeedModel(name: "Custom Feed", feedURL: customURL)
                        startDownload(feed: model)
                    } label: {
                        Text("Use this URL", bundle: bundle)
                    }
                    .disabled(customURL.isEmpty)
                } else {
                    Button {
                        withAnimation { showCustomURL = true }
                    } label: {
                        Text("Enter custom GTFS URL…", bundle: bundle)
                    }
                }
            } header: {
                Text("Custom Agency", bundle: bundle)
            } footer: {
                Text("Any public GTFS ZIP feed URL from Transitland, OpenMobilityData, or your local transit authority.", bundle: bundle)
                    .font(.caption)
            }
        }
        .searchable(text: $agencyFilter,
                    prompt: NSLocalizedString("Search agencies", bundle: bundle, comment: ""))
        .overlay {
            if service.isLoading { downloadOverlay }
        }
        .alert(
            "\(selectedFeed?.name ?? "Agency") — Download Failed",
            isPresented: Binding(
                get: { service.errorMessage != nil },
                set: { if !$0 { service.errorMessage = nil } }
            )
        ) {
            Button { service.errorMessage = nil } label: {
                Text("Try Another", bundle: bundle)
            }
            Button(role: .cancel) {
                service.errorMessage = nil
                onCancel()
            } label: {
                Text("Cancel", bundle: bundle)
            }
        } message: {
            Text(service.errorMessage ?? "")
        }
    }

    // MARK: - Step 2: Route

    private var routeStep: some View {
        let filtered = filteredRoutes
        let agencyName = selectedFeed?.name ?? "This agency"
        return List {
            if filtered.isEmpty {
                if routeFilter.isEmpty {
                    ContentUnavailableView(
                        "No Routes Found",
                        systemImage: "tram.fill",
                        description: Text("\(agencyName) returned no routes in this feed."))
                } else {
                    ContentUnavailableView(
                        "No Routes Found",
                        systemImage: "tram.fill",
                        description: Text("No \(agencyName) routes match '\(routeFilter)'."))
                }
            } else {
                ForEach(filtered) { route in
                    Button {
                        selectedRoute = route
                        step = .stop
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: route.type.systemImage)
                                .foregroundColor(route.routeColor)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(route.fullLabel).foregroundColor(.primary)
                                Text(route.type.label)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .searchable(text: $routeFilter,
                    prompt: NSLocalizedString("Search routes", bundle: bundle, comment: ""))
    }

    // MARK: - Step 3: Stop

    private var stopStep: some View {
        let filtered = filteredStops
        let agencyName = selectedFeed?.name ?? "This agency"
        return List {
            if filtered.isEmpty {
                if stopFilter.isEmpty {
                    ContentUnavailableView(
                        "No Stops Found",
                        systemImage: "mappin.slash",
                        description: Text("\(agencyName) returned no stops in this feed."))
                } else {
                    ContentUnavailableView(
                        "No Stops Found",
                        systemImage: "mappin.slash",
                        description: Text("No \(agencyName) stops match '\(stopFilter)'."))
                }
            } else {
                ForEach(filtered) { stop in
                    Button {
                        selectedStop = stop
                        prefillAlarmName(from: stop)
                        step = .confirm
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(stop.name).foregroundColor(.primary)
                                if let loc = locationManager.currentLocation {
                                    Text(distanceString(stop.distance(from: loc)))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                    }
                }
            }
        }
        .searchable(text: $stopFilter,
                    prompt: NSLocalizedString("Search stops", bundle: bundle, comment: ""))
    }

    // MARK: - Step 4: Confirm

    private var confirmStep: some View {
        Form {

            // MARK: Transit summary (pre-populated, read-only)
            if let stop = selectedStop, let route = selectedRoute {
                Section {
                    LabeledContent(NSLocalizedString("Agency", bundle: bundle, comment: ""),
                                   value: selectedFeed?.name ?? "Custom")
                    LabeledContent(NSLocalizedString("Route", bundle: bundle, comment: ""),
                                   value: route.fullLabel)
                    LabeledContent(NSLocalizedString("Stop", bundle: bundle, comment: ""),
                                   value: stop.name)
                } header: {
                    Text("Transit Details", bundle: bundle)
                }
            }

            // MARK: Alarm Details
            Section {
                TextField(NSLocalizedString("Name (e.g. Penn Station)", bundle: bundle, comment: ""),
                          text: $alarmName)
                    .autocorrectionDisabled()
                TextField(NSLocalizedString("Note (shown in notification)", bundle: bundle, comment: ""),
                          text: $note)
            } header: {
                Text("Alarm Details", bundle: bundle)
            }

            // MARK: Trigger
            Section {
                Picker(selection: $regionEvent) {
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
                        Text(distanceUnit.formatted(meters: radius))
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
            SoundPickerSection(selection: $notificationSound)

            // MARK: Schedule
            Section {
                Toggle(isOn: $isRepeating) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Repeat", bundle: bundle)
                            .font(.body)
                        Text("Auto-resets after you leave — fires again every trip", bundle: bundle)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                if isRepeating {
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle").foregroundColor(.blue)
                        Text("Hysteresis: alarm won't re-trigger until you've fully exited and re-entered the region.", bundle: bundle)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Toggle(isOn: $hasTimeWindow) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Active time window", bundle: bundle)
                            .font(.body)
                        Text("Only fire within a set time range", bundle: bundle)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                if hasTimeWindow {
                    DatePicker(selection: $windowStart, displayedComponents: .hourAndMinute) {
                        Text("From", bundle: bundle)
                    }
                    .datePickerStyle(.compact)
                    .environment(\.locale, timeFormat.pickerLocale)

                    DatePicker(selection: $windowEnd, displayedComponents: .hourAndMinute) {
                        Text("Until", bundle: bundle)
                    }
                    .datePickerStyle(.compact)
                    .environment(\.locale, timeFormat.pickerLocale)

                    let isOvernight: Bool = {
                        let cal = Calendar.current
                        let s = cal.component(.hour, from: windowStart) * 60
                              + cal.component(.minute, from: windowStart)
                        let e = cal.component(.hour, from: windowEnd) * 60
                              + cal.component(.minute, from: windowEnd)
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
                            Image(systemName: "info.circle").foregroundColor(.blue)
                            Text("Overnight span — active from \(timeFormat.formatTime(windowStart)) through midnight until \(timeFormat.formatTime(windowEnd)).", bundle: bundle)
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
                        let isOn = activeDays.contains(weekday)
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
                    Image(systemName: activeDays == Set(1...7) ? "checkmark.circle" : "calendar")
                        .foregroundColor(activeDays == Set(1...7) ? .green : .accentColor)
                    Text(activeDaysLabel)
                }
                .font(.caption)
                .foregroundColor(.secondary)
            } header: {
                Text("Active Days", bundle: bundle)
            }

            // MARK: Auto-Notify Contacts
            Section {
                Toggle(isOn: $notifyContact) {
                    Label {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Auto-Notify", bundle: bundle)
                                .font(.body)
                            Text("Share your location when this alarm fires", bundle: bundle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "bell.badge")
                    }
                }

                if notifyContact {
                    ForEach(notifyContactList) { contact in
                        contactRow(contact)
                    }
                    .onDelete { offsets in
                        notifyContactList.remove(atOffsets: offsets)
                    }

                    Button { showContactPicker = true } label: {
                        Label("Add from Contacts",
                              systemImage: "person.crop.circle.badge.plus")
                    }

                    Button { showManualEntry = true } label: {
                        Label("Add Manually", systemImage: "plus.circle")
                    }

                    if notifyContactList.isEmpty {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.circle")
                                .foregroundColor(.orange)
                            Text("Add at least one contact to enable Auto-Notify.", bundle: bundle)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            } header: {
                Text("Auto-Notify", bundle: bundle)
            } footer: {
                Text("When this alarm fires, a message with your location will be sent to all listed contacts automatically.", bundle: bundle)
            }

            // MARK: Validation error
            if alarmName.trimmingCharacters(in: .whitespaces).isEmpty {
                Section {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.circle")
                            .foregroundColor(.secondary)
                        Text("A name is required before the alarm can be saved", bundle: bundle)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            // MARK: Save
            Section {
                Button {
                    saveAlarm()
                } label: {
                    Text("Create Alarm", bundle: bundle)
                        .frame(maxWidth: .infinity)
                }
                .disabled(alarmName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    // MARK: - Download overlay

    private var downloadOverlay: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()
            VStack(spacing: 16) {
                ProgressView(value: service.downloadProgress)
                    .progressViewStyle(.linear)
                    .frame(width: 220)
                Text(service.downloadProgress < 0.9
                    ? "Downloading \(selectedFeed?.name ?? "feed")…"
                    : "Parsing \(selectedFeed?.name ?? "feed") stops…")
                    .font(.subheadline)
                    .foregroundColor(.white)
                if service.downloadAttempt > 1 {
                    Text("Attempt \(service.downloadAttempt) of \(service.maxDownloadAttempts)")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.75))
                }
                Button { service.cancel() } label: {
                    Text("Cancel", bundle: bundle)
                }
                .foregroundColor(.white)
                .padding(.top, 4)
            }
            .padding(24)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
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
                Text(contact.name).font(.body)
                Text(contact.value).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func addContact(_ contact: NotifyContact) {
        guard !notifyContactList.contains(where: { $0.value == contact.value }) else { return }
        notifyContactList.append(contact)
    }

    // MARK: - Window summary

    private var windowSummary: String {
        let cal = Calendar.current
        let startMins = cal.component(.hour,   from: windowStart) * 60
                      + cal.component(.minute, from: windowStart)
        let endMins   = cal.component(.hour,   from: windowEnd)   * 60
                      + cal.component(.minute, from: windowEnd)
        guard startMins != endMins else { return "Active all day" }
        let isOvernight  = startMins > endMins
        let durationMins = isOvernight ? (24 * 60 - startMins) + endMins : endMins - startMins
        let hrs = durationMins / 60; let mins = durationMins % 60
        let dur: String = {
            switch (hrs, mins) {
            case (0, let m): return "\(m) min"
            case (let h, 0): return "\(h) hr"
            default:         return "\(hrs) hr \(mins) min"
            }
        }()
        let s = timeFormat.formatTime(windowStart)
        let e = timeFormat.formatTime(windowEnd)
        return isOvernight
            ? "Active \(dur) · \(s) → \(e) next day"
            : "Active \(dur) · \(s) – \(e)"
    }

    // MARK: - Active days helpers

    private var activeDaysLabel: String {
        if activeDays == Set(1...7) { return NSLocalizedString("Every day", bundle: bundle, comment: "") }
        let weekdays: Set<Int> = [2, 3, 4, 5, 6]
        let weekend:  Set<Int> = [1, 7]
        if activeDays == weekdays { return NSLocalizedString("Weekdays only", bundle: bundle, comment: "") }
        if activeDays == weekend  { return NSLocalizedString("Weekends only", bundle: bundle, comment: "") }
        let keys = ["day.su","day.mo","day.tu","day.we","day.th","day.fr","day.sa"]
        return activeDays.sorted().map { NSLocalizedString(keys[$0 - 1], bundle: bundle, comment: "") }.joined(separator: " ")
    }

    private func toggleDay(_ weekday: Int) {
        if activeDays.contains(weekday) {
            guard activeDays.count > 1 else { return }
            activeDays.remove(weekday)
        } else {
            activeDays.insert(weekday)
        }
    }

    // MARK: - Wizard helpers

    private enum WizardStep {
        case agency, route, stop, confirm
        var titleKey: String {
            switch self {
            case .agency:  return "Choose Agency"
            case .route:   return "Choose Route"
            case .stop:    return "Choose Stop"
            case .confirm: return "New Transit Alarm"
            }
        }
    }

    private var filteredRoutes: [GTFSRoute] {
        let q = routeFilter.lowercased()
        let base = q.isEmpty ? service.routes : service.routes.filter {
            $0.shortName.lowercased().contains(q) || $0.longName.lowercased().contains(q)
        }
        return base.sorted { $0.displayName < $1.displayName }
    }

    private var filteredStops: [GTFSStop] {
        let q = stopFilter.lowercased()
        let base = q.isEmpty ? service.stops : service.stops.filter { $0.name.lowercased().contains(q) }
        if let loc = locationManager.currentLocation {
            return base.sorted { $0.distance(from: loc) < $1.distance(from: loc) }
        }
        return base.sorted { $0.name < $1.name }
    }

    private func pickCuratedFeed(_ curated: CuratedFeed) {
        let model = GTFSFeedModel(
            name: curated.name,
            feedURL: curated.feedURL,
            regionLabel: curated.region
        )
        startDownload(feed: model)
    }

    private func startDownload(feed: GTFSFeedModel) {
        selectedFeed = feed
        Task {
            await service.load(feed: feed)
            if service.errorMessage == nil { step = .route }
        }
    }

    private func goBack() {
        switch step {
        case .agency:  break
        case .route:   step = .agency
        case .stop:    step = .route
        case .confirm: step = .stop
        }
    }

    private func prefillAlarmName(from stop: GTFSStop) {
        if alarmName.isEmpty { alarmName = stop.name }
    }

    private func saveAlarm() {
        guard let stop = selectedStop else { return }
        let alarm = NapAlarm(
            name: alarmName.trimmingCharacters(in: .whitespaces),
            latitude: stop.latitude,
            longitude: stop.longitude,
            radius: radius,
            regionEvent: regionEvent,
            note: note,
            isRepeating: isRepeating,
            hasTimeWindow: hasTimeWindow,
            windowStart: hasTimeWindow ? windowStart : nil,
            windowEnd:   hasTimeWindow ? windowEnd   : nil,
            activeDays: activeDays,
            notifyContact: notifyContact,
            notifyContactsJSON: notifyContact ? notifyContactList.toJSON() : "",
            isTransitAlarm: true,
            transitAgencyName: selectedFeed?.name,
            transitRouteName: selectedRoute?.fullLabel,
            transitStopName: stop.name,
            transitRouteType: selectedRoute?.type,
            notificationSound: notificationSound
        )
        onSave(alarm)
    }

    private func distanceString(_ meters: CLLocationDistance) -> String {
        meters < 1000
            ? String(format: "%.0f m away", meters)
            : String(format: "%.1f km away", meters / 1000)
    }
}
