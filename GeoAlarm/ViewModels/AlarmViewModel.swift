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
    @Published var triggerMode: TriggerMode = .distance
    @Published var leadTimeMinutes: Int = 5
    /// Opt-in, per-alarm. Only meaningful when `triggerMode == .time`. See
    /// docs/dead-reckoning-design.md.
    @Published var deadReckoningEnabled: Bool = false
    @Published var regionEvent: RegionEvent = .onEntry
    @Published var isRepeating: Bool = false

    // MARK: - Active days (1 = Sun … 7 = Sat, matching Calendar.weekday)
    @Published var activeDays: Set<Int> = Set(1...7)

    // MARK: - Sound
    @Published var notificationSound: NotificationSound = .default

    // MARK: - Auto-Notify contacts

    /// Suppresses the `notifyContact` didSet during load/reset so we don't
    /// overwrite per-alarm contacts with global defaults.
    private var suppressAutoNotifyDidSet = false

    /// When toggled ON for the first time on a new alarm, pre-populates the
    /// contact list from the global defaults saved in Settings.
    @Published var notifyContact: Bool = false {
        didSet {
            guard !suppressAutoNotifyDidSet else { return }
            if notifyContact && notifyContactList.isEmpty {
                notifyContactList = [NotifyContact].loadGlobalDefaults()
            }
        }
    }

    /// Per-alarm contact list (phone numbers and/or email addresses).
    @Published var notifyContactList: [NotifyContact] = []

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
        radius.rounded() >= 200 &&         // round to avoid imperial unit conversion drift (655 ft = 199.64 m)
        (latitude != 0 || longitude != 0) &&
        CLLocationCoordinate2DIsValid(CLLocationCoordinate2D(latitude: latitude, longitude: longitude)) &&
        !hasAutoNotifyWithNoContacts
    }

    /// True when Auto-Notify is toggled on but there's nobody to notify — the
    /// toggle's `didSet` already tries to auto-fill from Settings → Auto-Notify
    /// Defaults the moment it's switched on, so this can only be true when
    /// there are no global defaults configured AND the user hasn't added a
    /// per-alarm contact either. Gates both `isValid` (disables Save/Update in
    /// real time) and `buildAlarm()` (hard-blocks with `validationError` as a
    /// defense-in-depth backstop) so an alarm can't silently save with Auto-Notify
    /// on and nobody to actually notify (Bob, 2026-07-04).
    var hasAutoNotifyWithNoContacts: Bool {
        notifyContact && notifyContactList.isEmpty
    }

    /// True once the user has explicitly picked a map location (rules out the (0,0) default).
    var hasLocation: Bool { latitude != 0 || longitude != 0 }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    private var editingID: UUID?

    /// Holds a reference to the SwiftData-managed object being edited.
    /// When set, buildAlarm() mutates this object in place so the model
    /// context tracks the changes and save() persists them correctly.
    /// Creating a new NapAlarm in edit mode (the old behaviour) left the
    /// original object — and its sound — unchanged in the context.
    private var existingAlarm: NapAlarm?

    // MARK: - Edit mode

    func load(alarm: NapAlarm) {
        // Suppress didSet so the existing per-alarm contact list is not
        // overwritten with global defaults while loading.
        suppressAutoNotifyDidSet = true
        defer { suppressAutoNotifyDidSet = false }

        existingAlarm     = alarm
        editingID         = alarm.id
        name              = alarm.name
        note              = alarm.note
        latitude          = alarm.latitude
        longitude         = alarm.longitude
        radius            = alarm.radius
        triggerMode       = alarm.triggerMode
        leadTimeMinutes   = alarm.leadTimeMinutes
        deadReckoningEnabled = alarm.deadReckoningEnabled
        regionEvent       = alarm.regionEvent
        isRepeating       = alarm.isRepeating
        activeDays        = alarm.activeDays
        hasTimeWindow     = alarm.hasTimeWindow
        windowStart       = alarm.windowStart ?? AlarmViewModel.defaultWindowStart
        windowEnd         = alarm.windowEnd   ?? AlarmViewModel.defaultWindowEnd
        notificationSound = alarm.notificationSound
        notifyContact     = alarm.notifyContact
        notifyContactList = alarm.notifyContactList
    }

    // MARK: - Build model

    func buildAlarm() -> NapAlarm? {
        validationError = nil
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else {
            validationError = "Please enter a name for this alarm."
            return nil
        }
        guard radius.rounded() >= 200 else {
            validationError = "Radius must be at least 200 metres."
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
        guard !hasAutoNotifyWithNoContacts else {
            validationError = "Auto-Notify is on but has no contact. Add a contact or turn off Auto-Notify."
            return nil
        }

        // When editing, mutate the existing SwiftData-managed object in place.
        // Creating a new NapAlarm and passing it to update() would leave the
        // original object (and its sound/properties) unchanged in the context,
        // because the new object is never inserted — the bug that caused the
        // user-selected alarm sound to be ignored on edit.
        if let alarm = existingAlarm {
            alarm.name              = trimmedName
            alarm.latitude          = latitude
            alarm.longitude         = longitude
            alarm.radius            = radius
            alarm.triggerMode       = triggerMode
            alarm.leadTimeMinutes   = leadTimeMinutes
            alarm.deadReckoningEnabled = deadReckoningEnabled
            alarm.regionEvent       = regionEvent
            alarm.note              = note
            alarm.isRepeating       = isRepeating
            alarm.activeDays        = activeDays
            alarm.hasTimeWindow     = hasTimeWindow
            alarm.windowStart       = hasTimeWindow ? windowStart : nil
            alarm.windowEnd         = hasTimeWindow ? windowEnd   : nil
            alarm.notifyContact     = notifyContact
            alarm.notifyContactList = notifyContact ? notifyContactList : []
            alarm.notificationSound = notificationSound
            return alarm
        }

        // New alarm — create a fresh object.
        return NapAlarm(
            id: editingID ?? UUID(),
            name: trimmedName,
            latitude: latitude,
            longitude: longitude,
            radius: radius,
            triggerMode: triggerMode,
            leadTimeMinutes: leadTimeMinutes,
            regionEvent: regionEvent,
            state: .active,
            note: note,
            isRepeating: isRepeating,
            hasTimeWindow: hasTimeWindow,
            windowStart: hasTimeWindow ? windowStart : nil,
            windowEnd:   hasTimeWindow ? windowEnd   : nil,
            activeDays: activeDays,
            notifyContact: notifyContact,
            notifyContactsJSON: notifyContact ? notifyContactList.toJSON() : "",
            notificationSound: notificationSound,
            deadReckoningEnabled: deadReckoningEnabled
        )
    }

    // MARK: - Helpers

    func setCoordinate(_ coordinate: CLLocationCoordinate2D) {
        latitude  = coordinate.latitude
        longitude = coordinate.longitude
    }

    func reset() {
        suppressAutoNotifyDidSet = true
        defer { suppressAutoNotifyDidSet = false }

        existingAlarm     = nil
        editingID         = nil
        name              = ""
        note              = ""
        latitude          = 0
        longitude         = 0
        radius            = 200
        triggerMode       = .distance
        leadTimeMinutes   = 5
        deadReckoningEnabled = false
        regionEvent       = .onEntry
        isRepeating       = false
        activeDays        = Set(1...7)
        hasTimeWindow     = false
        windowStart       = AlarmViewModel.defaultWindowStart
        windowEnd         = AlarmViewModel.defaultWindowEnd
        notificationSound = .default
        notifyContact     = false
        notifyContactList = []
        validationError   = nil
    }
}
