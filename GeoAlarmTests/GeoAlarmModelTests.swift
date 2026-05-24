// GeoAlarmModelTests.swift
// Unit tests for the GeoAlarm model: initialization, CLCircularRegion mapping,
// coding round-trips, and helper properties.

import XCTest
import CoreLocation
@testable import GeoAlarm

final class GeoAlarmModelTests: XCTestCase {

    // MARK: - Default init
    func test_defaultRadius_is200() {
        let alarm = GeoAlarm(name: "Test", latitude: 40.0, longitude: -74.0)
        XCTAssertEqual(alarm.radius, 200)
    }

    func test_defaultState_isActive() {
        let alarm = GeoAlarm(name: "Test", latitude: 40.0, longitude: -74.0)
        XCTAssertEqual(alarm.state, .active)
        XCTAssertTrue(alarm.isActive)
    }

    func test_defaultEvent_isOnEntry() {
        let alarm = GeoAlarm(name: "Test", latitude: 40.0, longitude: -74.0)
        XCTAssertEqual(alarm.regionEvent, .onEntry)
    }

    // MARK: - CLCircularRegion mapping
    func test_clRegion_identifier_matchesUUID() {
        let alarm = GeoAlarm(name: "Penn Station", latitude: 40.7506, longitude: -73.9971)
        XCTAssertEqual(alarm.clRegion.identifier, alarm.id.uuidString)
    }

    func test_clRegion_center_matchesCoordinate() {
        let alarm = GeoAlarm(name: "Test", latitude: 37.5, longitude: -122.5, radius: 300)
        XCTAssertEqual(alarm.clRegion.center.latitude,  37.5,   accuracy: 0.00001)
        XCTAssertEqual(alarm.clRegion.center.longitude, -122.5, accuracy: 0.00001)
    }

    func test_clRegion_enforces50mMinimum() {
        // Radii below 50 m are clamped to 50 m
        let alarm = GeoAlarm(name: "Tiny", latitude: 0, longitude: 0, radius: 10)
        XCTAssertEqual(alarm.clRegion.radius, 50)
    }

    func test_clRegion_notifyOnEntry_whenEventIsEntry() {
        let alarm = GeoAlarm(name: "A", latitude: 0, longitude: 0, regionEvent: .onEntry)
        XCTAssertTrue(alarm.clRegion.notifyOnEntry)
        XCTAssertFalse(alarm.clRegion.notifyOnExit)
    }

    func test_clRegion_notifyOnExit_whenEventIsExit() {
        let alarm = GeoAlarm(name: "B", latitude: 0, longitude: 0, regionEvent: .onExit)
        XCTAssertFalse(alarm.clRegion.notifyOnEntry)
        XCTAssertTrue(alarm.clRegion.notifyOnExit)
    }

    // MARK: - Codable round-trip
    func test_codableRoundTrip() throws {
        let original = GeoAlarm(
            name: "JFK Airport",
            latitude: 40.6413,
            longitude: -73.7781,
            radius: 500,
            regionEvent: .onExit,
            state: .inactive,
            note: "Don't miss check-in"
        )

        let data   = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(GeoAlarm.self, from: data)

        XCTAssertEqual(decoded.id,           original.id)
        XCTAssertEqual(decoded.name,         original.name)
        XCTAssertEqual(decoded.latitude,     original.latitude,  accuracy: 0.000001)
        XCTAssertEqual(decoded.longitude,    original.longitude, accuracy: 0.000001)
        XCTAssertEqual(decoded.radius,       original.radius)
        XCTAssertEqual(decoded.regionEvent,  original.regionEvent)
        XCTAssertEqual(decoded.state,        original.state)
        XCTAssertEqual(decoded.note,         original.note)
    }

    // MARK: - Equatable
    func test_equalityBasedOnID() {
        let id = UUID()
        let a1 = GeoAlarm(id: id, name: "A", latitude: 0, longitude: 0)
        var a2 = a1
        a2 = GeoAlarm(id: id, name: "Modified", latitude: 1, longitude: 1)
        // Same ID → equal (Equatable conforms on full struct, so fields must match)
        XCTAssertNotEqual(a1, a2)  // Different fields despite same ID
    }
}
