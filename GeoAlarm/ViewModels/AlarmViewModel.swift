// AlarmViewModel.swift
// Drives the Add/Edit alarm screen.
// Holds form state and validates before committing to AlarmManager.

import Foundation
internal import CoreLocation
import Combine

final class AlarmViewModel: ObservableObject {

    // MARK: - Form fields (bound to the Add/Edit view)
    @Published var name: String = ""
    @Published var note: String = ""
    @Published var latitude: Double = 0
    @Published var longitude: Double = 0
    @Published var radius: Double = 200
    @Published var regionEvent: RegionEvent = .onEntry

    // MARK: - Validation
    @Published private(set) var validationError: String?

    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        radius >= 50 &&
        CLLocationCoordinate2DIsValid(CLLocationCoordinate2D(latitude: latitude, longitude: longitude))
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    // MARK: - Editing support

    private var editingID: UUID?

    /// Populate form fields for editing an existing alarm.
    func load(alarm: GeoAlarm) {
        editingID    = alarm.id
        name         = alarm.name
        note         = alarm.note
        latitude     = alarm.latitude
        longitude    = alarm.longitude
        radius       = alarm.radius
        regionEvent  = alarm.regionEvent
    }

    // MARK: - Build model

    /// Validate and build a GeoAlarm from current form state.
    /// Returns nil and sets validationError if invalid.
    func buildAlarm() -> GeoAlarm? {
        validationError = nil

        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else {
            validationError = "Please enter a name for this alarm."
            return nil
        }
        guard radius >= 50 else {
            validationError = "Radius must be at least 50 metres."
            return nil
        }
        guard CLLocationCoordinate2DIsValid(coordinate) else {
            validationError = "Please pick a valid location on the map."
            return nil
        }

        return GeoAlarm(
            id: editingID ?? UUID(),
            name: trimmedName,
            latitude: latitude,
            longitude: longitude,
            radius: radius,
            regionEvent: regionEvent,
            state: .active,
            note: note
        )
    }

    // MARK: - Helpers

    func setCoordinate(_ coordinate: CLLocationCoordinate2D) {
        latitude  = coordinate.latitude
        longitude = coordinate.longitude
    }

    func reset() {
        editingID    = nil
        name         = ""
        note         = ""
        latitude     = 0
        longitude    = 0
        radius       = 200
        regionEvent  = .onEntry
        validationError = nil
    }
}
