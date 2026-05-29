// AlarmManagerTests.swift
// Unit tests for AlarmManager CRUD, persistence, and state transitions.
// Uses a mock UserDefaults suite so tests don't pollute real app storage.

import XCTest
@testable import NapAlarm

@MainActor
final class AlarmManagerTests: XCTestCase {

    var sut: AlarmManager!

    override func setUp() {
        super.setUp()
        // Wipe the test suite before each run
        UserDefaults(suiteName: "test")?.removePersistentDomain(forName: "test")
        sut = AlarmManager()
    }

    override func tearDown() {
        UserDefaults(suiteName: "test")?.removePersistentDomain(forName: "test")
        sut = nil
        super.tearDown()
    }

    // MARK: - Add

    func test_add_appendsAlarm() {
        let alarm = NapAlarm.preview
        sut.add(alarm: alarm)
        XCTAssertEqual(sut.alarms.count, 1)
        XCTAssertEqual(sut.alarms.first?.id, alarm.id)
    }

    func test_add_multiple() {
        NapAlarm.samples.forEach { sut.add(alarm: $0) }
        XCTAssertEqual(sut.alarms.count, NapAlarm.samples.count)
    }

    // MARK: - Update

    func test_update_modifiesExistingAlarm() {
        let alarm = NapAlarm.preview
        sut.add(alarm: alarm)

        var modified = alarm
        modified = NapAlarm(
            id: alarm.id,
            name: "Updated Name",
            latitude: alarm.latitude,
            longitude: alarm.longitude,
            radius: 500
        )
        sut.update(alarm: modified)

        XCTAssertEqual(sut.alarms.first?.name,   "Updated Name")
        XCTAssertEqual(sut.alarms.first?.radius, 500)
        XCTAssertEqual(sut.alarms.count, 1)
    }

    func test_update_unknownID_doesNothing() {
        sut.add(alarm: NapAlarm.preview)
        let stranger = NapAlarm(name: "Stranger", latitude: 0, longitude: 0)
        sut.update(alarm: stranger)
        XCTAssertEqual(sut.alarms.count, 1)
    }

    // MARK: - Delete

    func test_delete_removesAlarm() {
        let alarm = NapAlarm.preview
        sut.add(alarm: alarm)
        sut.delete(alarm: alarm)
        XCTAssertTrue(sut.alarms.isEmpty)
    }

    func test_deleteAtOffsets() {
        NapAlarm.samples.forEach { sut.add(alarm: $0) }
        sut.delete(at: IndexSet([0]))
        XCTAssertEqual(sut.alarms.count, NapAlarm.samples.count - 1)
    }

    // MARK: - Toggle active

    func test_toggleActive_disablesActiveAlarm() {
        let alarm = NapAlarm.preview   // starts as .active
        sut.add(alarm: alarm)
        sut.toggleActive(alarm)
        XCTAssertEqual(sut.alarms.first?.state, .inactive)
    }

    func test_toggleActive_enablesInactiveAlarm() {
        var alarm = NapAlarm.preview
        alarm = NapAlarm(
            id: alarm.id,
            name: alarm.name,
            latitude: alarm.latitude,
            longitude: alarm.longitude,
            state: .inactive
        )
        sut.add(alarm: alarm)
        sut.toggleActive(alarm)
        XCTAssertEqual(sut.alarms.first?.state, .active)
    }

    // MARK: - State: triggered via region event

    func test_handleRegionEntry_triggersMatchingAlarm() {
        let alarm = NapAlarm.preview   // .onEntry
        sut.add(alarm: alarm)

        // Simulate the region event callback
        sut.simulateRegionEntered(regionID: alarm.id.uuidString)

        XCTAssertEqual(sut.alarms.first?.state, .triggered)
        XCTAssertNotNil(sut.alarms.first?.lastTriggeredAt)
    }

    func test_handleRegionEntry_doesNotTrigger_inactiveAlarm() {
        var alarm = NapAlarm.preview
        alarm = NapAlarm(
            id: alarm.id, name: alarm.name,
            latitude: alarm.latitude, longitude: alarm.longitude,
            state: .inactive
        )
        sut.add(alarm: alarm)
        sut.simulateRegionEntered(regionID: alarm.id.uuidString)
        XCTAssertEqual(sut.alarms.first?.state, .inactive)
    }

    func test_handleRegionExit_doesNotTrigger_onEntryAlarm() {
        let alarm = NapAlarm.preview   // .onEntry
        sut.add(alarm: alarm)
        sut.simulateRegionExited(regionID: alarm.id.uuidString)
        XCTAssertEqual(sut.alarms.first?.state, .active)  // unchanged
    }
}

// MARK: - Testability extension
// Exposes internal region-event handling so tests don't need a real CLLocationManager.
extension AlarmManager {
    func simulateRegionEntered(regionID: String) {
        handleRegionEvent(regionID: regionID, event: .onEntry)
    }
    func simulateRegionExited(regionID: String) {
        handleRegionEvent(regionID: regionID, event: .onExit)
    }
}
