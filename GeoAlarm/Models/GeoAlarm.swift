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

    @Attribute(.unique) var id: UUID = UUID()
    var name: String = ""
    var latitude: Double = 0
    var longitude: Double = 0
    var radius: Double = 200

    // Enums stored as raw strings for SwiftData / CloudKit compatibility
    var regionEventRaw: String = RegionEvent.onEntry.rawValue
    var stateRaw: String = AlarmState.active.rawValue

    var note: String = ""
    var lastTriggeredAt: Date? = nil

    /// When true, the alarm auto-resets once the user leaves the region,
    /// so it fires again on the next trip (daily commuter use case).
    /// Hysteresis is enforced by requiring a full region exit before re-arming.
    var isRepeating: Bool = false

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
        isRepeating: Bool = false
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
        self.isRepeating = isRepeating
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
