// GeoAlarm.swift
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

// MARK: - Model

@Model
final class GeoAlarm {

    var id: UUID = UUID()
    var name: String = ""
    var latitude: Double = 0
    var longitude: Double = 0
    var radius: Double = 200

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

    // MARK: - Enum accessors

    var regionEvent: RegionEvent {
        get { RegionEvent(rawValue: regionEventRaw) ?? .onEntry }
        set { regionEventRaw = newValue.rawValue }
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

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    // MARK: - Time Window helper

    /// Returns true if the alarm should fire at `date`.
    /// Always true when hasTimeWindow is false.
    /// Compares hour/minute only — seconds are ignored for minute-resolution windows.
    func isWithinWindow(at date: Date = Date()) -> Bool {
        guard hasTimeWindow, let start = windowStart, let end = windowEnd else { return true }
        let cal = Calendar.current
        let nowMins   = cal.component(.hour, from: date)   * 60 + cal.component(.minute, from: date)
        let startMins = cal.component(.hour, from: start)  * 60 + cal.component(.minute, from: start)
        let endMins   = cal.component(.hour, from: end)    * 60 + cal.component(.minute, from: end)

        if startMins <= endMins {
            // Normal span, e.g. 08:00 – 22:00
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
        regionEvent: RegionEvent = .onEntry,
        state: AlarmState = .active,
        note: String = "",
        lastTriggeredAt: Date? = nil,
        triggerCount: Int = 0,
        isRepeating: Bool = false,
        hasTimeWindow: Bool = false,
        windowStart: Date? = nil,
        windowEnd: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.radius = radius
        self.regionEventRaw = regionEvent.rawValue
        self.stateRaw = state.rawValue
        self.note = note
        self.lastTriggeredAt = lastTriggeredAt
        self.triggerCount = triggerCount
        self.isRepeating = isRepeating
        self.hasTimeWindow = hasTimeWindow
        self.windowStart = windowStart
        self.windowEnd = windowEnd
    }
}

// MARK: - Sample data

extension GeoAlarm {
    static var preview: GeoAlarm {
        GeoAlarm(
            name: "Times Square",
            latitude: 40.7580,
            longitude: -73.9855,
            radius: 200,
            regionEvent: .onEntry,
            note: "Wake me when we arrive!"
        )
    }

    static var samples: [GeoAlarm] {
        [
            GeoAlarm(name: "Home",
                     latitude: 37.7749, longitude: -122.4194, radius: 150),
            GeoAlarm(name: "Penn Station",
                     latitude: 40.7506, longitude: -73.9971,  radius: 100,
                     isRepeating: true),
            GeoAlarm(name: "Airport",
                     latitude: 40.6413, longitude: -73.7781,  radius: 300,
                     state: .inactive)
        ]
    }
}
