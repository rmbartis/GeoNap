// AlarmViewModelFieldTests.swift
// Full round-trip tests for every AlarmViewModel field that was not covered
// by the basic AlarmViewModelTests.swift — scheduling, sound, contacts, reset.
//
// Covered here:
//   • buildAlarm preserves isRepeating, activeDays, hasTimeWindow/windowTimes,
//                          notifyContact/notifyContactList, notificationSound
//   • load() populates all scheduling and contact fields
//   • reset() clears all fields including scheduling and contacts
//   • hasLocation computed property
//   • buildAlarm validation: window start == end → error

import XCTest
import CoreLocation
@testable import GeoNap

@MainActor
final class AlarmViewModelFieldTests: XCTestCase {

    var sut: AlarmViewModel!

    override func setUp() {
        super.setUp()
        sut = AlarmViewModel()
        // Provide a valid base so only the tested field varies
        sut.name      = "Test Stop"
        sut.latitude  = 40.7527
        sut.longitude = -73.9772
        sut.radius    = 200
    }

    override func tearDown() {
        sut = nil
        super.tearDown()
    }

    // MARK: - hasLocation

    func test_hasLocation_false_whenBothZero() {
        sut.latitude  = 0
        sut.longitude = 0
        XCTAssertFalse(sut.hasLocation)
    }

    func test_hasLocation_true_whenLatNonZero() {
        sut.latitude  = 40.0
        sut.longitude = 0
        XCTAssertTrue(sut.hasLocation)
    }

    func test_hasLocation_true_whenLonNonZero() {
        sut.latitude  = 0
        sut.longitude = -74.0
        XCTAssertTrue(sut.hasLocation)
    }

    func test_hasLocation_true_whenBothNonZero() {
        sut.latitude  = 40.7527
        sut.longitude = -73.9772
        XCTAssertTrue(sut.hasLocation)
    }

    // MARK: - buildAlarm: isRepeating

    func test_buildAlarm_preserves_isRepeating_true() {
        sut.isRepeating = true
        let alarm = sut.buildAlarm()
        XCTAssertTrue(alarm?.isRepeating ?? false,
                      "buildAlarm must carry isRepeating=true into the NapAlarm")
    }

    func test_buildAlarm_preserves_isRepeating_false() {
        sut.isRepeating = false
        let alarm = sut.buildAlarm()
        XCTAssertFalse(alarm?.isRepeating ?? true)
    }

    // MARK: - buildAlarm: activeDays

    func test_buildAlarm_preserves_activeDays() {
        sut.activeDays = Set(2...6)  // weekdays
        let alarm = sut.buildAlarm()
        XCTAssertEqual(alarm?.activeDays, Set(2...6),
                       "buildAlarm must carry activeDays into the NapAlarm")
    }

    func test_buildAlarm_preserves_allDays() {
        sut.activeDays = Set(1...7)
        let alarm = sut.buildAlarm()
        XCTAssertTrue(alarm?.isEveryDay ?? false)
    }

    // MARK: - buildAlarm: time window

    func test_buildAlarm_preserves_timeWindow() {
        sut.hasTimeWindow = true
        sut.windowStart   = hhmm(8, 0)
        sut.windowEnd     = hhmm(10, 0)

        let alarm = sut.buildAlarm()

        XCTAssertTrue(alarm?.hasTimeWindow ?? false)
        XCTAssertNotNil(alarm?.windowStart)
        XCTAssertNotNil(alarm?.windowEnd)

        let startH = Calendar.current.component(.hour, from: alarm!.windowStart!)
        let endH   = Calendar.current.component(.hour, from: alarm!.windowEnd!)
        XCTAssertEqual(startH, 8)
        XCTAssertEqual(endH,  10)
    }

    func test_buildAlarm_noTimeWindow_yieldsNilDates() {
        sut.hasTimeWindow = false
        let alarm = sut.buildAlarm()
        XCTAssertFalse(alarm?.hasTimeWindow ?? true)
        XCTAssertNil(alarm?.windowStart,
                     "windowStart must be nil when hasTimeWindow is false")
        XCTAssertNil(alarm?.windowEnd,
                     "windowEnd must be nil when hasTimeWindow is false")
    }

    func test_buildAlarm_fails_whenWindowStartEqualsEnd() {
        sut.hasTimeWindow = true
        sut.windowStart   = hhmm(9, 0)
        sut.windowEnd     = hhmm(9, 0)   // same time — invalid

        let alarm = sut.buildAlarm()
        XCTAssertNil(alarm,
                     "buildAlarm must fail when window start and end are identical")
        XCTAssertNotNil(sut.validationError)
    }

    // MARK: - buildAlarm: notificationSound

    func test_buildAlarm_preserves_notificationSound_critical() {
        sut.notificationSound = .critical
        let alarm = sut.buildAlarm()
        XCTAssertEqual(alarm?.notificationSound, .critical)
    }

    func test_buildAlarm_preserves_notificationSound_vibrate() {
        sut.notificationSound = .vibrate
        let alarm = sut.buildAlarm()
        XCTAssertEqual(alarm?.notificationSound, .vibrate)
    }

    // MARK: - buildAlarm: contacts

    func test_buildAlarm_preserves_notifyContact_true() {
        let contact = NotifyContact(name: "Alice", value: "+15551234567")
        sut.notifyContactList = [contact]
        // Bypass the didSet auto-population by setting the flag after the list
        sut.notifyContact = true
        // notifyContact didSet loads global defaults when list is empty — but list
        // is already populated so no override occurs here.
        let alarm = sut.buildAlarm()
        XCTAssertTrue(alarm?.notifyContact ?? false)
        XCTAssertEqual(alarm?.notifyContactList.count, 1)
        XCTAssertEqual(alarm?.notifyContactList.first?.value, "+15551234567")
    }

    func test_buildAlarm_notifyContactFalse_yieldsEmptyJSON() {
        sut.notifyContact = false
        sut.notifyContactList = [NotifyContact(name: "Bob", value: "+15559876543")]
        let alarm = sut.buildAlarm()
        XCTAssertFalse(alarm?.notifyContact ?? true)
        // When notifyContact is false, contacts must not be persisted
        XCTAssertTrue(alarm?.notifyContactsJSON.isEmpty ?? false,
                      "notifyContactsJSON must be empty when notifyContact is false")
    }

    // MARK: - load: scheduling fields

    func test_load_populatesIsRepeating() {
        let existing = NapAlarm(name: "A", latitude: 40.0, longitude: -74.0,
                                isRepeating: true)
        sut.load(alarm: existing)
        XCTAssertTrue(sut.isRepeating)
    }

    func test_load_populatesActiveDays() {
        let existing = NapAlarm(name: "A", latitude: 40.0, longitude: -74.0,
                                activeDays: Set(2...6))
        sut.load(alarm: existing)
        XCTAssertEqual(sut.activeDays, Set(2...6))
    }

    func test_load_populatesTimeWindow() {
        let start = hhmm(7, 30)
        let end   = hhmm(9, 0)
        let existing = NapAlarm(name: "A", latitude: 40.0, longitude: -74.0,
                                hasTimeWindow: true, windowStart: start, windowEnd: end)
        sut.load(alarm: existing)

        XCTAssertTrue(sut.hasTimeWindow)
        XCTAssertEqual(Calendar.current.component(.hour,   from: sut.windowStart), 7)
        XCTAssertEqual(Calendar.current.component(.minute, from: sut.windowStart), 30)
        XCTAssertEqual(Calendar.current.component(.hour,   from: sut.windowEnd),   9)
    }

    func test_load_populatesNotificationSound() {
        let existing = NapAlarm(name: "A", latitude: 40.0, longitude: -74.0,
                                notificationSound: .critical)
        sut.load(alarm: existing)
        XCTAssertEqual(sut.notificationSound, .critical)
    }

    func test_load_populatesNotifyContactAndList() {
        let contact = NotifyContact(name: "Carol", value: "+15550001111")
        let existing = NapAlarm(name: "A", latitude: 40.0, longitude: -74.0,
                                notifyContact: true,
                                notifyContactsJSON: [contact].toJSON())
        sut.load(alarm: existing)

        XCTAssertTrue(sut.notifyContact)
        XCTAssertEqual(sut.notifyContactList.count, 1)
        XCTAssertEqual(sut.notifyContactList.first?.value, "+15550001111")
    }

    // MARK: - reset: completeness

    func test_reset_clearsIsRepeating() {
        sut.isRepeating = true
        sut.reset()
        XCTAssertFalse(sut.isRepeating)
    }

    func test_reset_clearsActiveDays_toAllDays() {
        sut.activeDays = Set(2...6)
        sut.reset()
        XCTAssertEqual(sut.activeDays, Set(1...7))
    }

    func test_reset_clearsTimeWindow() {
        sut.hasTimeWindow = true
        sut.reset()
        XCTAssertFalse(sut.hasTimeWindow)
    }

    func test_reset_clearsNotificationSound_toDefault() {
        sut.notificationSound = .critical
        sut.reset()
        XCTAssertEqual(sut.notificationSound, .default)
    }

    func test_reset_clearsNotifyContact() {
        sut.notifyContactList = [NotifyContact(name: "X", value: "+1555")]
        sut.notifyContact = true
        sut.reset()
        XCTAssertFalse(sut.notifyContact)
        XCTAssertTrue(sut.notifyContactList.isEmpty)
    }

    func test_reset_clearsValidationError() {
        // Trigger a validation error
        sut.name = ""
        _ = sut.buildAlarm()
        XCTAssertNotNil(sut.validationError)

        sut.reset()
        XCTAssertNil(sut.validationError)
    }

    // MARK: - Helpers

    private func hhmm(_ h: Int, _ m: Int) -> Date {
        var c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        c.hour = h; c.minute = m; c.second = 0
        return Calendar.current.date(from: c) ?? Date()
    }
}
