// CreateAlarmIntent.swift
// "Hey Siri, create a NapAlarm" — geocodes an address and saves a new alarm.

import AppIntents
import CoreLocation
import SwiftData

struct CreateAlarmIntent: AppIntent {

    static var title: LocalizedStringResource = "Create NapAlarm"
    static var description = IntentDescription(
        "Creates a new location alarm that fires when you arrive at or leave a place.",
        categoryName: "Create"
    )

    // Run silently in the background — no need to open the app.
    static var openAppWhenRun: Bool = false

    // MARK: - Parameters

    @Parameter(title: "Alarm Name",
               description: "A label for this alarm, e.g. Penn Station")
    var name: String

    @Parameter(title: "Location",
               description: "Address or place name, e.g. 1 Penn Plaza New York")
    var locationQuery: String

    @Parameter(title: "Trigger on Arrival",
               description: "On means fire on arrival; Off means fire on departure",
               default: true)
    var onArrival: Bool

    @Parameter(title: "Radius (metres)",
               description: "How close you need to be before the alarm fires (50–2000)",
               default: 200)
    var radius: Int

    // MARK: - Perform

    func perform() async throws -> some IntentResult & ProvidesDialog {

        // 1. Geocode the location string
        let geocoder   = CLGeocoder()
        let placemarks = try await geocoder.geocodeAddressString(locationQuery)

        guard let placemark = placemarks.first,
              let location  = placemark.location else {
            throw $locationQuery.needsValueError(
                "Couldn't find that location. Try a more specific address."
            )
        }

        // 2. Save to SwiftData (ModelContainer.init is @MainActor)
        let container = try await MainActor.run { try IntentModelContainer.make() }
        let context   = ModelContext(container)

        let alarm = NapAlarm(
            name: name,
            latitude:  location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            radius:    Double(radius),
            regionEvent: onArrival ? .onEntry : .onExit,
            state: .active
        )
        context.insert(alarm)
        try context.save()

        let trigger = onArrival ? "arrival" : "departure"
        return .result(
            dialog: "Done — \(name) will alert you on \(trigger)."
        )
    }
}
