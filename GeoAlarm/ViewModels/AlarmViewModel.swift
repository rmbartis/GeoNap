// AlarmViewModel.swift
// Drives the Add/Edit alarm screen. Holds form state and validates input.

import Foundation
import CoreLocation
import Combine

final class AlarmViewModel: ObservableObject {

    // MARK: - Form fields
    @Published var name: String = ""
    @Published var note: String = ""
    @Published var latitude: Double = 0
    @Published var longitude: Double = 0
    @Published var radius: Double = 200
    @Published var regionEvent: RegionEvent = .onEntry
    @Published var isRepeating: Bool = false

    // MARK: - Active days (1 = Sun … 7 = Sat, matching Calendar.weekday)
    @Published var activeDays: Set<Int> = Set(1...7)

    // MARK: - Sound
    @Published var notificationSound: NotificationSound = .default

    // MARK: - Contact notification
    @Published var notifyContact: Bool   = false
    @Published var contactName: String   = ""
    @Published var contactPhone: String  = ""

    // MARK: - Time window
    @Published var hasTimeWindow: Bool = false
    @Published var windowStart: Date = AlarmViewModel.defaultWindowStart
    @Published var windowEnd:   Date = AlarmViewModel.defaultWindowEnd

    /// Default start: 08:00 today
    static var defaultWindowStart: Date {
        Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: Date()) ?? Date()
    }
    /// Default end: 22:00 today
    static var defaultWindowEnd: Date {
        Calendar.current.date(bySettingHour: 22, minute: 0, second: 0, of: Date()) ?? Date()
    }

    // MARK: - Validation
    @Published private(set) var validationError: String?

    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        radius >= 50 &&
        (latitude != 0 || longitude != 0) &&
        CLLocationCoordinate2DIsValid(CLLocationCoordinate2D(latitude: latitude, longitude: longitude))
    }

    /// True once the user has explicitly picked a map location (rules out the (0,0) default).
    var hasLocation: Bool { latitude != 0 || longitude != 0 }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    private var editingID: UUID?

    // MARK: - Edit mode

    func load(alarm: GeoAlarm) {
        editingID     = alarm.id
        name          = alarm.name
        note          = alarm.note
        latitude      = alarm.latitude
        longitude     = alarm.longitude
        radius        = alarm.radius
        regionEvent   = alarm.regionEvent
        isRepeating   = alarm.isRepeating
        activeDays        = alarm.activeDays
        hasTimeWindow     = alarm.hasTimeWindow
        windowStart       = alarm.windowStart ?? AlarmViewModel.defaultWindowStart
        windowEnd         = alarm.windowEnd   ?? AlarmViewModel.defaultWindowEnd
        notificationSound = alarm.notificationSound
        notifyContact = alarm.notifyContact
        contactName   = alarm.contactName
        contactPhone  = alarm.contactPhone
    }

    // MARK: - Build model

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
        if hasTimeWindow {
            let startMins = Calendar.current.component(.hour,   from: windowStart) * 60
                          + Calendar.current.component(.minute, from: windowStart)
            let endMins   = Calendar.current.component(.hour,   from: windowEnd)   * 60
                          + Calendar.current.component(.minute, from: windowEnd)
            if startMins == endMins {
                validationError = "Window start and end time cannot be the same."
                return nil
            }
        }

        return GeoAlarm(
            id: editingID ?? UUID(),
            name: trimmedName,
            latitude: latitude,
            longitude: longitude,
            radius: radius,
            regionEvent: regionEvent,
            state: .active,
            note: note,
            isRepeating: isRepeating,
            hasTimeWindow: hasTimeWindow,
            windowStart: hasTimeWindow ? windowStart : nil,
            windowEnd:   hasTimeWindow ? windowEnd   : nil,
            activeDays: activeDays,
            notifyContact: notifyContact,
            contactName: notifyContact ? contactName : "",
            contactPhone: notifyContact ? contactPhone : "",
            notificationSound: notificationSound
        )
    }

    // MARK: - Helpers

    func setCoordinate(_ coordinate: CLLocationCoordinate2D) {
        latitude  = coordinate.latitude
        longitude = coordinate.longitude
    }

    func reset() {
        editingID     = nil
        name          = ""
        note          = ""
        latitude      = 0
        longitude     = 0
        radius        = 200
        regionEvent   = .onEntry
        isRepeating   = false
        activeDays    = Set(1...7)
        hasTimeWindow     = false
        windowStart       = AlarmViewModel.defaultWindowStart
        windowEnd         = AlarmViewModel.defaultWindowEnd
        notificationSound = .default
        notifyContact = false
        contactName   = ""
        contactPhone  = ""
        validationError = nil
    }
}
