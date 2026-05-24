// GeoAlarm.swift
// Core data model representing a single geo-location alarm.

import Foundation
internal import CoreLocation

/// The lifecycle state of a geo-location alarm.
enum AlarmState: String, Codable, CaseIterable {
    case active    // Monitoring for entry/exit
    case triggered // Region event fired, alarm sounding
    case snoozed   // Temporarily suppressed
    case inactive  // Disabled by user
}

/// Whether the alarm fires when entering or exiting the region.
enum RegionEvent: String, Codable, CaseIterable {
    case onEntry = "On Arrival"
    case onExit  = "On Departure"
}

/// A single geo-location alarm.
struct GeoAlarm: Identifiable, Codable, Equatable {
    let id: UUID

    // User-visible label
    var name: String

    // Center of the monitored region
    var latitude: Double
    var longitude: Double

    // Radius in meters (CLCircularRegion minimum is 1 m; practical minimum ~50 m)
    var radius: Double

    // Trigger preference
    var regionEvent: RegionEvent

    // Current lifecycle state
    var state: AlarmState

    // Optional note shown in the notification
    var note: String

    // When the alarm was last triggered (nil = never)
    var lastTriggeredAt: Date?

    // MARK: - Computed helpers

    /// CLCircularRegion used by CLLocationManager for monitoring.
    var clRegion: CLCircularRegion {
        let region = CLCircularRegion(
            center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            radius: max(radius, 50),   // Enforce Apple's practical minimum
            identifier: id.uuidString
        )
        region.notifyOnEntry = (regionEvent == .onEntry)
        region.notifyOnExit  = (regionEvent == .onExit)
        return region
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var isActive: Bool { state == .active }

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
        lastTriggeredAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.radius = radius
        self.regionEvent = regionEvent
        self.state = state
        self.note = note
        self.lastTriggeredAt = lastTriggeredAt
    }
}

// MARK: - Sample data for Previews & Tests
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
            GeoAlarm(name: "Home",        latitude: 37.7749,  longitude: -122.4194, radius: 150),
            GeoAlarm(name: "Penn Station", latitude: 40.7506, longitude: -73.9971,  radius: 100, regionEvent: .onArrival),
            GeoAlarm(name: "Airport",     latitude: 40.6413,  longitude: -73.7781,  radius: 300, state: .inactive)
        ]
    }
}

// Convenience alias so both spellings compile during development
private extension RegionEvent {
    static var onArrival: RegionEvent { .onEntry }
}
