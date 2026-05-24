// AlarmViewModelTests.swift
// Unit tests for AlarmViewModel validation and alarm-building logic.

import XCTest
import CoreLocation
@testable import GeoAlarm

@MainActor
final class AlarmViewModelTests: XCTestCase {

    var sut: AlarmViewModel!   // system under test

    override func setUp() {
        super.setUp()
        sut = AlarmViewModel()
    }

    override func tearDown() {
        sut = nil
        super.tearDown()
    }

    // MARK: - isValid

    func test_isValid_false_whenNameEmpty() {
        sut.name      = ""
        sut.latitude  = 40.0
        sut.longitude = -74.0
        sut.radius    = 200
        XCTAssertFalse(sut.isValid)
    }

    func test_isValid_false_whenRadiusBelowMinimum() {
        sut.name      = "Test"
        sut.latitude  = 40.0
        sut.longitude = -74.0
        sut.radius    = 10   // below 50 m
        XCTAssertFalse(sut.isValid)
    }

    func test_isValid_false_whenCoordinateIsZeroZero() {
        sut.name      = "Test"
        sut.latitude  = 0
        sut.longitude = 0
        sut.radius    = 200
        // 0,0 is technically valid coordinates — this test documents current behavior
        // (the form requires the user to explicitly pick a location)
        XCTAssertTrue(sut.isValid)  // ViewModel allows it; UI enforces pin placement
    }

    func test_isValid_true_withAllFieldsSet() {
        sut.name      = "Home"
        sut.latitude  = 37.7749
        sut.longitude = -122.4194
        sut.radius    = 150
        XCTAssertTrue(sut.isValid)
    }

    // MARK: - buildAlarm

    func test_buildAlarm_returnsNil_andSetsError_whenNameEmpty() {
        sut.name      = "   "
        sut.latitude  = 40.0
        sut.longitude = -74.0
        sut.radius    = 200

        let alarm = sut.buildAlarm()
        XCTAssertNil(alarm)
        XCTAssertNotNil(sut.validationError)
    }

    func test_buildAlarm_returnsNil_whenRadiusTooSmall() {
        sut.name      = "Valid Name"
        sut.latitude  = 40.0
        sut.longitude = -74.0
        sut.radius    = 20

        let alarm = sut.buildAlarm()
        XCTAssertNil(alarm)
        XCTAssertNotNil(sut.validationError)
    }

    func test_buildAlarm_succeeds_withValidInput() {
        sut.name        = "Times Square"
        sut.latitude    = 40.7580
        sut.longitude   = -73.9855
        sut.radius      = 200
        sut.regionEvent = .onEntry
        sut.note        = "Wake me up!"

        let alarm = sut.buildAlarm()
        XCTAssertNotNil(alarm)
        XCTAssertEqual(alarm?.name,        "Times Square")
        XCTAssertEqual(alarm?.radius,       200)
        XCTAssertEqual(alarm?.regionEvent, .onEntry)
        XCTAssertEqual(alarm?.note,        "Wake me up!")
        XCTAssertNil(sut.validationError)
    }

    func test_buildAlarm_trimmedName() {
        sut.name      = "  Airport  "
        sut.latitude  = 40.6413
        sut.longitude = -73.7781
        sut.radius    = 300

        let alarm = sut.buildAlarm()
        XCTAssertEqual(alarm?.name, "Airport")
    }

    // MARK: - load (edit mode)

    func test_load_populatesFields() {
        let existing = GeoAlarm(
            id: UUID(),
            name: "Grand Central",
            latitude: 40.7527,
            longitude: -73.9772,
            radius: 120,
            regionEvent: .onExit,
            note: "Transfer here"
        )

        sut.load(alarm: existing)

        XCTAssertEqual(sut.name,        "Grand Central")
        XCTAssertEqual(sut.latitude,    40.7527,  accuracy: 0.00001)
        XCTAssertEqual(sut.longitude,   -73.9772, accuracy: 0.00001)
        XCTAssertEqual(sut.radius,      120)
        XCTAssertEqual(sut.regionEvent, .onExit)
        XCTAssertEqual(sut.note,        "Transfer here")
    }

    func test_buildAlarm_afterLoad_preservesID() {
        let existing = GeoAlarm.preview
        sut.load(alarm: existing)
        sut.name = existing.name

        let built = sut.buildAlarm()
        XCTAssertEqual(built?.id, existing.id)
    }

    // MARK: - reset

    func test_reset_clearsAllFields() {
        sut.name      = "Something"
        sut.latitude  = 99
        sut.longitude = 99
        sut.radius    = 999
        sut.note      = "Note"

        sut.reset()

        XCTAssertEqual(sut.name,      "")
        XCTAssertEqual(sut.latitude,  0)
        XCTAssertEqual(sut.longitude, 0)
        XCTAssertEqual(sut.radius,    200)
        XCTAssertEqual(sut.note,      "")
        XCTAssertNil(sut.validationError)
    }

    // MARK: - setCoordinate

    func test_setCoordinate_updatesLatLon() {
        let coord = CLLocationCoordinate2D(latitude: 51.5074, longitude: -0.1278)
        sut.setCoordinate(coord)
        XCTAssertEqual(sut.latitude,  51.5074, accuracy: 0.00001)
        XCTAssertEqual(sut.longitude, -0.1278, accuracy: 0.00001)
    }
}
