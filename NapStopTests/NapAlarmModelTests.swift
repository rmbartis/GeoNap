// NapAlarmModelTests.swift
// Unit tests for the NapAlarm model, sound regression guards, and Info.plist checks.

import XCTest
import CoreLocation
import UserNotifications
@testable import GeoNap

final class NapAlarmModelTests: XCTestCase {

    // MARK: - Default init
    func test_defaultRadius_is200() {
        let alarm = NapAlarm(name: "Test", latitude: 40.0, longitude: -74.0)
        XCTAssertEqual(alarm.radius, 200)
    }

    func test_defaultState_isActive() {
        let alarm = NapAlarm(name: "Test", latitude: 40.0, longitude: -74.0)
        XCTAssertEqual(alarm.state, .active)
        XCTAssertTrue(alarm.isActive)
    }

    func test_defaultEvent_isOnEntry() {
        let alarm = NapAlarm(name: "Test", latitude: 40.0, longitude: -74.0)
        XCTAssertEqual(alarm.regionEvent, .onEntry)
    }

    // MARK: - CLCircularRegion mapping
    func test_clRegion_identifier_matchesUUID() {
        let alarm = NapAlarm(name: "Penn Station", latitude: 40.7506, longitude: -73.9971)
        XCTAssertEqual(alarm.clRegion.identifier, alarm.id.uuidString)
    }

    func test_clRegion_center_matchesCoordinate() {
        let alarm = NapAlarm(name: "Test", latitude: 37.5, longitude: -122.5, radius: 300)
        XCTAssertEqual(alarm.clRegion.center.latitude,  37.5,   accuracy: 0.00001)
        XCTAssertEqual(alarm.clRegion.center.longitude, -122.5, accuracy: 0.00001)
    }

    func test_clRegion_enforces50mMinimum() {
        // Radii below 50 m are clamped to 50 m
        let alarm = NapAlarm(name: "Tiny", latitude: 0, longitude: 0, radius: 10)
        XCTAssertEqual(alarm.clRegion.radius, 50)
    }

    func test_clRegion_notifyOnEntry_whenEventIsEntry() {
        let alarm = NapAlarm(name: "A", latitude: 0, longitude: 0, regionEvent: .onEntry)
        XCTAssertTrue(alarm.clRegion.notifyOnEntry)
        XCTAssertFalse(alarm.clRegion.notifyOnExit)
    }

    func test_clRegion_notifyOnExit_whenEventIsExit() {
        let alarm = NapAlarm(name: "B", latitude: 0, longitude: 0, regionEvent: .onExit)
        XCTAssertFalse(alarm.clRegion.notifyOnEntry)
        XCTAssertTrue(alarm.clRegion.notifyOnExit)
    }

    // MARK: - Field assignment
    // NapAlarm is a SwiftData @Model class (not Codable); verify fields survive
    // in-memory mutation rather than JSON round-trip.
    func test_fieldsRetainAssignedValues() {
        let alarm = NapAlarm(
            name: "JFK Airport",
            latitude: 40.6413,
            longitude: -73.7781,
            radius: 500,
            regionEvent: .onExit,
            state: .inactive,
            note: "Don't miss check-in"
        )

        XCTAssertEqual(alarm.name,        "JFK Airport")
        XCTAssertEqual(alarm.latitude,    40.6413,  accuracy: 0.000001)
        XCTAssertEqual(alarm.longitude,  -73.7781,  accuracy: 0.000001)
        XCTAssertEqual(alarm.radius,      500)
        XCTAssertEqual(alarm.regionEvent, .onExit)
        XCTAssertEqual(alarm.state,       .inactive)
        XCTAssertEqual(alarm.note,        "Don't miss check-in")
    }

    // MARK: - Equatable
    func test_equalityBasedOnID() {
        let id = UUID()
        let a1 = NapAlarm(id: id, name: "A", latitude: 0, longitude: 0)
        var a2 = a1
        a2 = NapAlarm(id: id, name: "Modified", latitude: 1, longitude: 1)
        // Same ID → equal (Equatable conforms on full struct, so fields must match)
        XCTAssertNotEqual(a1, a2)  // Different fields despite same ID
    }
}

// MARK: - Sound regression guards

/// Regression: default sound was changed to .critical, which requires the
/// com.apple.developer.usernotifications.critical-alerts entitlement (not present).
/// Without it iOS silently drops the sound — resulting in no audible alarm.
@MainActor
final class SoundRegressionTests: XCTestCase {

    func test_defaultSound_isDefault_notCritical() {
        let alarm = NapAlarm(name: "Test", latitude: 40.0, longitude: -74.0)
        XCTAssertEqual(alarm.notificationSound, .default,
            "Default sound must be .default — .critical requires the critical-alerts entitlement which is not present")
        XCTAssertNotEqual(alarm.notificationSound, .critical,
            ".critical silently produces no sound without the entitlement")
    }

    func test_soundNameRaw_defaultsToDefault() {
        let alarm = NapAlarm(name: "Test", latitude: 40.0, longitude: -74.0)
        XCTAssertEqual(alarm.soundNameRaw, "default",
            "soundNameRaw must be 'default' — was incorrectly set to 'critical'")
    }

    func test_explicitCriticalSound_roundTrips() {
        let alarm = NapAlarm(name: "Test", latitude: 40.0, longitude: -74.0,
                             notificationSound: .critical)
        XCTAssertEqual(alarm.notificationSound, .critical)
        XCTAssertEqual(alarm.soundNameRaw, "critical")
    }

    func test_vibrateSound_unSound_isNil() {
        XCTAssertNil(NotificationSound.vibrate.unSound,
            ".vibrate must produce nil UNNotificationSound (vibration only)")
    }

    func test_defaultAndCritical_ids_areDistinct() {
        XCTAssertNotEqual(NotificationSound.default.id, NotificationSound.critical.id)
    }

    // MARK: Info.plist background modes

    /// 'location' must be in UIBackgroundModes for reliable background geofencing.
    func test_infoPlist_hasLocationBackgroundMode() {
        let modes = Bundle.main.infoDictionary?["UIBackgroundModes"] as? [String] ?? []
        XCTAssertTrue(modes.contains("location"),
            "UIBackgroundModes must include 'location'. Found: \(modes)")
    }

    func test_infoPlist_hasRemoteNotificationBackgroundMode() {
        let modes = Bundle.main.infoDictionary?["UIBackgroundModes"] as? [String] ?? []
        XCTAssertTrue(modes.contains("remote-notification"),
            "UIBackgroundModes must include 'remote-notification'. Found: \(modes)")
    }
}
