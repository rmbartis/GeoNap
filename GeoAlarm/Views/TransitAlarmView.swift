// TransitAlarmView.swift
// 4-step wizard for creating a transit stop alarm using a GTFS feed.
//  Step 1 — Agency (pick from curated list or enter custom URL)
//  Step 2 — Route   (filter by type, search by name)
//  Step 3 — Stop    (search + sort by proximity to current location)
//  Step 4 — Confirm (alarm name, radius, on-arrival vs on-departure)

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

    var onSave:   (GeoAlarm) -> Void
    var onCancel: () -> Void

    @EnvironmentObject var locationManager: LocationManager

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

    // Step 4 — Alarm details
    @State private var alarmName:         String = ""
    @State private var radius:            Double = 200
    @State private var regionEvent:       RegionEvent = .onEntry
    @State private var isRepeating:       Bool = false
    @State private var notificationSound: NotificationSound = .default

    @StateObject private var service = GTFSService()

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
            .navigationTitle(step.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                if step != .agency {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button { goBack() } label: {
                            Label("Back", systemImage: "chevron.left")
                        }
                    }
                }
            }
        }
    }

    // MARK: - Step 1: Agency

    private var agencyStep: some View {
        List {
            // Curated feeds grouped by country — each country is collapsible.
            // Groups auto-expand while a search is active.
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

            // Custom URL entry
            Section {
                if showCustomURL {
                    TextField("https://example.com/gtfs.zip", text: $customURL)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                    Button("Use this URL") {
                        guard !customURL.isEmpty else { return }
                        let model = GTFSFeedModel(name: "Custom Feed", feedURL: customURL)
                        startDownload(feed: model)
                    }
                    .disabled(customURL.isEmpty)
                } else {
                    Button("Enter custom GTFS URL…") {
                        withAnimation { showCustomURL = true }
                    }
                }
            } header: {
                Text("Custom Agency")
            } footer: {
                Text("Any public GTFS ZIP feed URL from Transitland, OpenMobilityData, or your local transit authority.")
                    .font(.caption)
            }
        }
        .searchable(text: $agencyFilter, prompt: "Search agencies")
        .overlay {
            if service.isLoading {
                downloadOverlay
            }
        }
        .alert(
            "\(selectedFeed?.name ?? "Agency") — Download Failed",
            isPresented: Binding(
                get: { service.errorMessage != nil },
                set: { if !$0 { service.errorMessage = nil } }
            )
        ) {
            Button("Try Another") { service.errorMessage = nil }
            Button("Cancel", role: .cancel) {
                service.errorMessage = nil
                onCancel()
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
                                Text(route.fullLabel)
                                    .foregroundColor(.primary)
                                Text(route.type.label)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .searchable(text: $routeFilter, prompt: "Search routes")
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
                                    let dist = stop.distance(from: loc)
                                    Text(distanceString(dist))
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
        .searchable(text: $stopFilter, prompt: "Search stops")
    }

    // MARK: - Step 4: Confirm

    private var confirmStep: some View {
        Form {
            if let stop = selectedStop, let route = selectedRoute {
                Section("Transit Details") {
                    LabeledContent("Agency", value: selectedFeed?.name ?? "Custom")
                    LabeledContent("Route", value: route.fullLabel)
                    LabeledContent("Stop",  value: stop.name)
                }
            }

            Section("Alarm") {
                TextField("Alarm name", text: $alarmName)
                if alarmName.trimmingCharacters(in: .whitespaces).isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.circle")
                            .foregroundColor(.secondary)
                        Text("A name is required before the alarm can be saved")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Picker("Trigger", selection: $regionEvent) {
                    Text("On Arrival").tag(RegionEvent.onEntry)
                    Text("On Departure").tag(RegionEvent.onExit)
                }
                .pickerStyle(.segmented)

                HStack {
                    Text("Radius")
                    Spacer()
                    Text("\(Int(radius)) m")
                        .foregroundColor(.secondary)
                }
                Slider(value: $radius, in: 50...500, step: 50)

                Toggle("Repeat (re-arm after each trip)", isOn: $isRepeating)
            }

            SoundPickerSection(selection: $notificationSound)

            Section {
                Button("Create Alarm") {
                    saveAlarm()
                }
                .disabled(alarmName.trimmingCharacters(in: .whitespaces).isEmpty)
                .frame(maxWidth: .infinity, alignment: .center)
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
                Button("Cancel") { service.cancel() }
                    .foregroundColor(.white)
                    .padding(.top, 4)
            }
            .padding(24)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
    }

    // MARK: - Helpers

    private enum WizardStep {
        case agency, route, stop, confirm
        var title: String {
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
            $0.shortName.lowercased().contains(q) ||
            $0.longName.lowercased().contains(q)
        }
        return base.sorted { $0.displayName < $1.displayName }
    }

    private var filteredStops: [GTFSStop] {
        let q = stopFilter.lowercased()
        let base: [GTFSStop]
        if q.isEmpty {
            base = service.stops
        } else {
            base = service.stops.filter { $0.name.lowercased().contains(q) }
        }
        // Sort by proximity when location is available, otherwise alphabetical
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
            // Navigate regardless of route count — routeStep shows
            // "No routes found" if parsing returned nothing.
            // Only stay on agency screen if there was a hard download error.
            if service.errorMessage == nil {
                step = .route
            }
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
        if alarmName.isEmpty {
            alarmName = stop.name
        }
    }

    private func saveAlarm() {
        guard let stop = selectedStop else { return }
        let alarm = GeoAlarm(
            name: alarmName.trimmingCharacters(in: .whitespaces),
            latitude: stop.latitude,
            longitude: stop.longitude,
            radius: radius,
            regionEvent: regionEvent,
            isRepeating: isRepeating,
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
        if meters < 1000 {
            return String(format: "%.0f m away", meters)
        } else {
            return String(format: "%.1f km away", meters / 1000)
        }
    }
}
