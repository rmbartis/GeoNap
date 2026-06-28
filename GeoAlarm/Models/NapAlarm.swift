// NapAlarm.swift
// Core data model — SwiftData @Model class.
// Supports one-shot and repeating alarms with hysteresis.

import Foundation
import CoreLocation
import SwiftData

// MARK: - Enums

/// The lifecycle state of a geo-location alarm.
enum AlarmState: String, Codable, CaseIterable {
    case active    // Monitoring for entry/exit
    case triggered // Region event fired, waiting for exit (hysteresis)
    case snoozed   // Temporarily suppressed by user
    case inactive  // Disabled by user
}

/// Whether the alarm fires when entering or exiting the region.
enum RegionEvent: String, Codable, CaseIterable {
    case onEntry = "On Arrival"
    case onExit  = "On Departure"
}

/// How an alarm's trigger is defined:
///   - `.distance`: fixed-radius geofence (the original behavior).
///   - `.time`: fire ~`leadTimeMinutes` before arrival, using a rolling-average
///     speed → ETA (hybrid model — see docs/time-based-alarms-design.md).
enum TriggerMode: String, Codable, CaseIterable, Identifiable {
    case distance
    case time

    var id: String { rawValue }

    /// Localization key for the picker label.
    var localizationKey: String {
        switch self {
        case .distance: return "trigger.mode.distance"
        case .time:     return "trigger.mode.time"
        }
    }

    /// English fallback label (also the key registered in Localizable.strings).
    var englishLabel: String {
        switch self {
        case .distance: return "Distance (radius)"
        case .time:     return "Time (before arrival)"
        }
    }
}

// MARK: - Model

@Model
final class NapAlarm {

    var id: UUID = UUID()
    var name: String = ""
    var latitude: Double = 0
    var longitude: Double = 0
    var radius: Double = 200

    // MARK: - Trigger mode (distance vs. time)
    // Stored as a raw string for SwiftData/CloudKit compatibility. Additive +
    // defaulted so existing alarms migrate as `.distance` (unchanged behavior).
    var triggerModeRaw: String = TriggerMode.distance.rawValue
    /// Minutes before estimated arrival to fire, when `triggerMode == .time`.
    var leadTimeMinutes: Int = 5

    // Enums stored as raw strings for SwiftData / CloudKit compatibility
    var regionEventRaw: String = RegionEvent.onEntry.rawValue
    var stateRaw: String = AlarmState.active.rawValue

    var note: String = ""
    var lastTriggeredAt: Date? = nil
    var triggerCount: Int = 0

    /// When true, the alarm auto-resets once the user leaves the region,
    /// so it fires again on the next trip (daily commuter use case).
    /// Hysteresis is enforced by requiring a full region exit before re-arming.
    var isRepeating: Bool = false

    // MARK: - Time Window
    // Only the hour/minute components of these Dates are meaningful.
    // When hasTimeWindow is true the alarm only fires inside [windowStart, windowEnd].
    // Overnight spans (e.g. 22:00 → 06:00) are supported.

    var hasTimeWindow: Bool = false
    var windowStart: Date? = nil
    var windowEnd:   Date? = nil

    // MARK: - Active Days
    // Bitmask: bit 0 = Sunday, bit 1 = Monday, … bit 6 = Saturday
    // (matches Calendar.Component.weekday − 1, where weekday 1 = Sunday)
    // Default 127 = all 7 bits set = every day.

    var activeDaysRaw: Int = 127   // SwiftData-friendly Int; 127 = all days

    /// The set of weekday numbers (1 = Sun … 7 = Sat, matching Calendar) on which
    /// this alarm is allowed to fire. An empty set means every day (same as 127).
    var activeDays: Set<Int> {
        get {
            guard activeDaysRaw != 127 else { return Set(1...7) }
            var days = Set<Int>()
            for weekday in 1...7 {
                let bit = 1 << (weekday - 1)
                if activeDaysRaw & bit != 0 { days.insert(weekday) }
            }
            return days.isEmpty ? Set(1...7) : days
        }
        set {
            var mask = 0
            for weekday in newValue { mask |= 1 << (weekday - 1) }
            activeDaysRaw = mask == 0 ? 127 : mask
        }
    }

    /// True when all 7 days are active (default state).
    var isEveryDay: Bool { activeDaysRaw == 127 || activeDays == Set(1...7) }

    /// Localized day-of-week summary (e.g. "Mon Tue Thu Fri", "月 火 木 金", "Weekdays").
    /// Pass the in-app `locale` (for the system's localized weekday symbols) and the
    /// in-app `bundle` (for the "Weekdays"/"Weekends" labels), so it follows the
    /// language chosen inside the app, not just the device language.
    func activeDaysLabel(locale: Locale, bundle: Bundle) -> String? {
        guard !isEveryDay else { return nil }
        let weekdays: Set<Int> = [2, 3, 4, 5, 6]
        let weekend:  Set<Int> = [1, 7]
        if activeDays == weekdays { return NSLocalizedString("Weekdays", bundle: bundle, comment: "") }
        if activeDays == weekend  { return NSLocalizedString("Weekends", bundle: bundle, comment: "") }
        var cal = Calendar(identifier: .gregorian)
        cal.locale = locale
        let symbols = cal.shortWeekdaySymbols   // index 0 = Sunday … 6 = Saturday, localized
        return activeDays.sorted().map { symbols[$0 - 1] }.joined(separator: " ")
    }

    // MARK: - Sound

    /// Raw value of the chosen NotificationSound (String for SwiftData / CloudKit compatibility).
    var soundNameRaw: String = NotificationSound.default.rawValue

    var notificationSound: NotificationSound {
        get { NotificationSound(rawValue: soundNameRaw) }
        set { soundNameRaw = newValue.rawValue }
    }

    // MARK: - Contact Notification
    // When enabled, a "Notify Contacts" action appears on the fired notification.
    // Tapping it opens a pre-composed iMessage/SMS with the contact's phone number(s).

    /// Whether to offer a contact notification when this alarm fires.
    var notifyContact: Bool = false

    /// Legacy single-contact fields — kept for SwiftData migration compatibility.
    /// New code uses notifyContactsJSON / notifyContactList instead.
    var contactName: String = ""
    var contactPhone: String = ""

    /// JSON-encoded [NotifyContact] array for Auto-Notify multi-contact support.
    var notifyContactsJSON: String = ""

    /// Typed accessor for the auto-notify contact list.
    var notifyContactList: [NotifyContact] {
        get { [NotifyContact].fromJSON(notifyContactsJSON) }
        set { notifyContactsJSON = newValue.toJSON() }
    }

    // MARK: - Transit

    /// True when this alarm was created from a GTFS transit stop.
    var isTransitAlarm: Bool = false

    /// Display name of the transit agency (e.g. "Amtrak").
    var transitAgencyName: String? = nil

    /// Route short/long name (e.g. "7 · Flushing Local").
    var transitRouteName: String? = nil

    /// Name of the selected stop (e.g. "Times Sq - 42 St").
    var transitStopName: String? = nil

    /// Raw GTFS route_type integer stored as string for SwiftData compatibility.
    var transitRouteTypeRaw: String? = nil

    var transitRouteType: GTFSRouteType? {
        get {
            guard let raw = transitRouteTypeRaw, let i = Int(raw) else { return nil }
            return GTFSRouteType(rawInt: i)
        }
        set { transitRouteTypeRaw = newValue.map { String($0.rawValue) } }
    }

    // MARK: - Enum accessors

    var regionEvent: RegionEvent {
        get { RegionEvent(rawValue: regionEventRaw) ?? .onEntry }
        set { regionEventRaw = newValue.rawValue }
    }

    var triggerMode: TriggerMode {
        get { TriggerMode(rawValue: triggerModeRaw) ?? .distance }
        set { triggerModeRaw = newValue.rawValue }
    }

    /// Minutes of continuous-GPS "warm-up" granted before the earliest possible
    /// fire, so the rolling-average speed has time to stabilize. The outer ring is
    /// sized for `leadTime + warmup`, i.e. tracking begins this many minutes before
    /// the alarm could fire (per Bob: "5 min + the time the user set").
    static let gpsWarmupMinutes = 5

    /// Outer "get close" geofence radius (metres) for a time-based alarm: the
    /// distance covered at `capSpeed` over (lead time + GPS warm-up), clamped to
    /// sane bounds. Crossing this ring wakes the app to begin continuous ETA
    /// tracking (hybrid model). For distance alarms this is unused.
    /// - Parameters:
    ///   - capSpeed: assumed max approach speed in m/s (default ≈144 km/h).
    ///   - warmupMinutes: continuous-GPS lead before the fire window (default 5).
    func outerRingRadius(capSpeed: Double = 40,
                         warmupMinutes: Int = NapAlarm.gpsWarmupMinutes,
                         minRadius: Double = 300,
                         maxRadius: Double = 30_000) -> Double {
        let totalMinutes = Double(leadTimeMinutes + warmupMinutes)
        let raw = capSpeed * totalMinutes * 60
        return min(max(raw, minRadius), maxRadius)
    }

    var state: AlarmState {
        get { AlarmState(rawValue: stateRaw) ?? .active }
        set { stateRaw = newValue.rawValue }
    }

    var isActive: Bool { state == .active }

    // MARK: - CLRegion

    /// CLCircularRegion used by CLLocationManager for monitoring.
    /// Repeating alarms monitor BOTH entry AND exit:
    ///   - Entry  → fires the alarm notification
    ///   - Exit   → resets state to .active (hysteresis) so it can fire again
    var clRegion: CLCircularRegion {
        let region = CLCircularRegion(
            center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            radius: max(radius, 50),
            identifier: id.uuidString
        )
        region.notifyOnEntry = (regionEvent == .onEntry) || isRepeating
        region.notifyOnExit  = (regionEvent == .onExit)  || isRepeating
        return region
    }

    /// Identifier suffix that marks the outer "warm-up" ring of a time-based alarm,
    /// distinguishing it from the inner proximity ring (which keeps the bare UUID).
    static let warmupRegionSuffix = ":warmup"

    /// Outer "get close" ring for a time-based alarm. Entering it wakes the app to
    /// start continuous GPS + ETA tracking (hybrid model). notifyOnEntry only.
    var outerWarmupRegion: CLCircularRegion {
        let region = CLCircularRegion(
            center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            radius: outerRingRadius(),
            identifier: id.uuidString + Self.warmupRegionSuffix
        )
        region.notifyOnEntry = true
        region.notifyOnExit  = false
        return region
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    // MARK: - Time Window helper

    /// Returns true if the alarm should fire at `date`.
    /// Checks both the active-days bitmask and the optional time window.
    func isWithinWindow(at date: Date = Date()) -> Bool {
        let cal = Calendar.current

        // Day-of-week check (weekday: 1 = Sun … 7 = Sat)
        if !isEveryDay {
            let weekday = cal.component(.weekday, from: date)
            guard activeDays.contains(weekday) else { return false }
        }

        // Time window check
        guard hasTimeWindow, let start = windowStart, let end = windowEnd else { return true }
        let nowMins   = cal.component(.hour, from: date)   * 60 + cal.component(.minute, from: date)
        let startMins = cal.component(.hour, from: start)  * 60 + cal.component(.minute, from: start)
        let endMins   = cal.component(.hour, from: end)    * 60 + cal.component(.minute, from: end)

        if startMins <= endMins {
            return nowMins >= startMins && nowMins <= endMins
        } else {
            // Overnight span, e.g. 22:00 – 06:00
            return nowMins >= startMins || nowMins <= endMins
        }
    }

    /// Formatted "HH:mm – HH:mm" string for display, using the supplied formatter.
    func windowLabel(using format: TimeFormat) -> String? {
        guard hasTimeWindow, let start = windowStart, let end = windowEnd else { return nil }
        return "\(format.formatTime(start)) – \(format.formatTime(end))"
    }

    // MARK: - Init

    init(
        id: UUID = UUID(),
        name: String,
        latitude: Double,
        longitude: Double,
        radius: Double = 200,
        triggerMode: TriggerMode = .distance,
        leadTimeMinutes: Int = 5,
        regionEvent: RegionEvent = .onEntry,
        state: AlarmState = .active,
        note: String = "",
        lastTriggeredAt: Date? = nil,
        triggerCount: Int = 0,
        isRepeating: Bool = false,
        hasTimeWindow: Bool = false,
        windowStart: Date? = nil,
        windowEnd: Date? = nil,
        activeDays: Set<Int> = Set(1...7),
        notifyContact: Bool = false,
        contactName: String = "",
        contactPhone: String = "",
        notifyContactsJSON: String = "",
        isTransitAlarm: Bool = false,
        transitAgencyName: String? = nil,
        transitRouteName: String? = nil,
        transitStopName: String? = nil,
        transitRouteType: GTFSRouteType? = nil,
        notificationSound: NotificationSound = .default
    ) {
        self.id = id
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.radius = radius
        self.triggerModeRaw = triggerMode.rawValue
        self.leadTimeMinutes = leadTimeMinutes
        self.regionEventRaw = regionEvent.rawValue
        self.stateRaw = state.rawValue
        self.note = note
        self.lastTriggeredAt = lastTriggeredAt
        self.triggerCount = triggerCount
        self.isRepeating = isRepeating
        self.hasTimeWindow = hasTimeWindow
        self.windowStart = windowStart
        self.windowEnd = windowEnd
        self.activeDays = activeDays
        self.notifyContact     = notifyContact
        self.contactName       = contactName
        self.contactPhone      = contactPhone
        self.notifyContactsJSON = notifyContactsJSON
        self.isTransitAlarm = isTransitAlarm
        self.transitAgencyName = transitAgencyName
        self.transitRouteName = transitRouteName
        self.transitStopName = transitStopName
        self.transitRouteTypeRaw = transitRouteType.map { String($0.rawValue) }
        self.soundNameRaw = notificationSound.rawValue
    }
}

// MARK: - NotifyContact

/// A contact entry used by the Auto-Notify feature.
/// Stores either a phone number or an email address in `value`.
struct NotifyContact: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var value: String   // phone number or email address

    init(id: UUID = UUID(), name: String, value: String) {
        self.id    = id
        self.name  = name
        self.value = value.trimmingCharacters(in: .whitespaces)
    }

    /// True when `value` looks like an email address.
    var isEmail: Bool { value.contains("@") }

    /// SF Symbol name appropriate for the contact type.
    var systemImage: String { isEmail ? "envelope" : "phone" }
}

extension Array where Element == NotifyContact {
    /// Decode from a JSON string (e.g. stored in NapAlarm.notifyContactsJSON).
    static func fromJSON(_ json: String) -> [NotifyContact] {
        guard !json.isEmpty,
              let data = json.data(using: .utf8),
              let list = try? JSONDecoder().decode([NotifyContact].self, from: data)
        else { return [] }
        return list
    }

    /// Encode to a JSON string for persistent storage.
    func toJSON() -> String {
        guard let data = try? JSONEncoder().encode(self),
              let str  = String(data: data, encoding: .utf8)
        else { return "[]" }
        return str
    }

    /// Load the global Auto-Notify defaults from UserDefaults.
    static func loadGlobalDefaults() -> [NotifyContact] {
        fromJSON(UserDefaults.standard.string(forKey: "defaultNotifyContacts") ?? "")
    }

    /// Persist the current array as the global Auto-Notify defaults.
    func saveAsGlobalDefaults() {
        UserDefaults.standard.set(toJSON(), forKey: "defaultNotifyContacts")
    }
}

// MARK: - Sample data

extension NapAlarm {
    static var preview: NapAlarm {
        NapAlarm(
            name: "Times Square",
            latitude: 40.7580,
            longitude: -73.9855,
            radius: 200,
            regionEvent: .onEntry,
            note: "Wake me when we arrive!"
        )
    }

    static var samples: [NapAlarm] {
        [
            NapAlarm(name: "Home",
                     latitude: 37.7749, longitude: -122.4194, radius: 150),
            NapAlarm(name: "Penn Station",
                     latitude: 40.7506, longitude: -73.9971,  radius: 100,
                     isRepeating: true),
            NapAlarm(name: "Airport",
                     latitude: 40.6413, longitude: -73.7781,  radius: 300,
                     state: .inactive)
        ]
    }
}
