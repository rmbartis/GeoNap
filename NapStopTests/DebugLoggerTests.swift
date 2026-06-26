// DebugLoggerTests.swift
// CI tests verifying that:
//   1. DebugLogger records entries when enabled and ignores calls when disabled.
//   2. clearLog() empties the in-memory buffer.
//   3. AlarmManager writes a log entry for every user-facing action.
//
// All assertions run against DebugLogger.recentEntries (populated synchronously)
// so no async waiting or file I/O is needed.

import XCTest
@testable import GeoNap

// MARK: - Helpers

private extension DebugLogger {
    /// Enable logging without writing the session header (avoids UIDevice in tests).
    func enableForTesting() {
        UserDefaults.standard.set(true, forKey: UserDefaultsKey.debugLoggingEnabled)
    }

    /// Disable and wipe state after each test.
    func resetForTesting() {
        UserDefaults.standard.set(false, forKey: UserDefaultsKey.debugLoggingEnabled)
        clearLog()
    }

    /// True if any recent entry's message contains `substring`.
    func hasEntry(containing substring: String) -> Bool {
        recentEntries.contains { $0.message.contains(substring) || $0.category.contains(substring) }
    }
}

// MARK: - DebugLogger unit tests

final class DebugLoggerTests: XCTestCase {

    private let logger = DebugLogger.shared

    override func setUp() {
        super.setUp()
        logger.resetForTesting()
        logger.enableForTesting()
    }

    override func tearDown() {
        logger.resetForTesting()
        super.tearDown()
    }

    // MARK: Basic recording

    func test_log_createsEntry_whenEnabled() {
        logger.log("hello world", category: "Test")
        XCTAssertFalse(logger.recentEntries.isEmpty)
    }

    func test_log_entryContainsMessage() {
        logger.log("penn station", category: "Test")
        XCTAssertTrue(logger.hasEntry(containing: "penn station"))
    }

    func test_log_entryContainsCategory() {
        logger.log("msg", category: "Location")
        XCTAssertEqual(logger.recentEntries.last?.category, "Location")
    }

    func test_log_entryHasISO8601Timestamp() {
        logger.log("ts check", category: "Test")
        let ts = logger.recentEntries.last?.timestamp ?? ""
        // ISO 8601 timestamps always contain "T" between date and time.
        XCTAssertTrue(ts.contains("T"), "Timestamp should be ISO 8601, got: \(ts)")
    }

    func test_log_multipleEntriesAccumulate() {
        logger.log("one",   category: "Test")
        logger.log("two",   category: "Test")
        logger.log("three", category: "Test")
        XCTAssertGreaterThanOrEqual(logger.recentEntries.count, 3)
    }

    // MARK: Disabled — no-op

    func test_log_noEntry_whenDisabled() {
        logger.resetForTesting()           // leaves isEnabled = false
        logger.log("should not appear", category: "Test")
        XCTAssertFalse(logger.hasEntry(containing: "should not appear"))
    }

    func test_log_resumes_afterReenabling() {
        logger.resetForTesting()
        logger.enableForTesting()
        logger.log("resumed", category: "Test")
        XCTAssertTrue(logger.hasEntry(containing: "resumed"))
    }

    // MARK: clearLog

    func test_clearLog_emptiesRecentEntries() {
        logger.log("entry A", category: "Test")
        logger.log("entry B", category: "Test")
        logger.clearLog()
        XCTAssertTrue(logger.recentEntries.isEmpty)
    }

    func test_clearLog_thenLog_producesNewEntry() {
        logger.log("before clear", category: "Test")
        logger.clearLog()
        logger.log("after clear", category: "Test")
        XCTAssertEqual(logger.recentEntries.count, 1)
        XCTAssertTrue(logger.hasEntry(containing: "after clear"))
    }
}

// MARK: - AlarmManager + DebugLogger integration tests

/// Verifies that every user-facing AlarmManager action writes at least one
/// entry to DebugLogger.recentEntries with the alarm name present.
///
/// AlarmManager is exercised without a real ModelContext (left nil) —
/// the logging calls still run before/after persistence.
@MainActor
final class AlarmManagerDebugLogTests: XCTestCase {

    private var sut: AlarmManager!
    private let logger = DebugLogger.shared

    override func setUp() {
        super.setUp()
        logger.resetForTesting()
        logger.enableForTesting()
        sut = AlarmManager()
    }

    override func tearDown() {
        logger.resetForTesting()
        sut = nil
        super.tearDown()
    }

    // MARK: add

    func test_add_logsEntry() {
        let alarm = makeAlarm(name: "Penn Station")
        sut.add(alarm: alarm)
        XCTAssertTrue(logger.hasEntry(containing: "Penn Station"),
                      "add() must log the alarm name. entries: \(logger.recentEntries.map(\.message))")
    }

    func test_add_categoryIsAlarmManager() {
        sut.add(alarm: makeAlarm(name: "Add Category Test"))
        let entry = logger.recentEntries.last { $0.message.contains("Add Category Test") }
        XCTAssertEqual(entry?.category, "AlarmManager")
    }

    // MARK: delete

    func test_delete_logsEntry() {
        let alarm = makeAlarm(name: "Airport")
        sut.add(alarm: alarm)
        logger.clearLog()
        sut.delete(alarm: alarm)
        XCTAssertTrue(logger.hasEntry(containing: "Airport"),
                      "delete() must log the alarm name.")
    }

    // MARK: handleRegionEvent — alarm triggered

    func test_regionEntered_logsTriggered() {
        let alarm = makeAlarm(name: "Times Square")
        sut.add(alarm: alarm)
        logger.clearLog()

        sut.simulateRegionEntered(regionID: alarm.id.uuidString)

        XCTAssertTrue(logger.hasEntry(containing: "Times Square"),
                      "handleRegionEvent(.onEntry) must log the alarm name. entries: \(logger.recentEntries.map(\.message))")
    }

    func test_regionExited_onExitAlarm_logsTriggered() {
        let alarm = NapAlarm(name: "Departure Gate", latitude: 40.6, longitude: -73.7,
                             regionEvent: .onExit, state: .active)
        sut.add(alarm: alarm)
        logger.clearLog()

        sut.simulateRegionExited(regionID: alarm.id.uuidString)

        XCTAssertTrue(logger.hasEntry(containing: "Departure Gate"))
    }

    // MARK: handleRegionEvent — repeating alarm re-armed

    func test_regionExit_rearmsRepeatingAlarm_logsRearmed() {
        let alarm = NapAlarm(name: "Daily Commute", latitude: 40.7, longitude: -74.0,
                             regionEvent: .onEntry, state: .active, isRepeating: true)
        sut.add(alarm: alarm)
        sut.simulateRegionEntered(regionID: alarm.id.uuidString)   // trigger it
        logger.clearLog()

        sut.simulateRegionExited(regionID: alarm.id.uuidString)    // re-arm

        XCTAssertTrue(logger.hasEntry(containing: "Daily Commute"),
                      "Re-arming must log the alarm name. entries: \(logger.recentEntries.map(\.message))")
    }

    // (snooze logging test removed — snooze is now owned by AlarmKit, not AlarmManager.)

    // MARK: Each action produces at least one entry

    func test_eachUserAction_producesAtLeastOneEntry() {
        // add
        let alarm = makeAlarm(name: "Coverage Alarm")
        var count = logger.recentEntries.count
        sut.add(alarm: alarm)
        XCTAssertGreaterThan(logger.recentEntries.count, count, "add must log")

        // delete
        count = logger.recentEntries.count
        sut.delete(alarm: alarm)
        XCTAssertGreaterThan(logger.recentEntries.count, count, "delete must log")
    }

    // MARK: Disabled logger — AlarmManager calls must not crash

    func test_alarmManager_doesNotCrash_whenLoggerDisabled() {
        logger.resetForTesting()   // disables logging

        let alarm = makeAlarm(name: "No Crash")
        XCTAssertNoThrow(sut.add(alarm: alarm))
        XCTAssertNoThrow(sut.simulateRegionEntered(regionID: alarm.id.uuidString))
        XCTAssertNoThrow(sut.delete(alarm: alarm))
    }

    // MARK: Helpers

    private func makeAlarm(name: String) -> NapAlarm {
        NapAlarm(name: name, latitude: 40.7580, longitude: -73.9855, radius: 200)
    }
}
