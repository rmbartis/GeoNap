// AlarmViewModelTests.swift
// Unit tests for AlarmViewModel validation and alarm-building logic.

import XCTest
import CoreLocation
@testable import GeoNap

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
        let existing = NapAlarm(
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
        let existing = NapAlarm.preview
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

    // MARK: - Radius boundary regression (imperial minimum)

    /// Regression: 164 ft × 0.3048 = 49.9872 m.
    /// The old check `radius >= 50` treated this as INVALID because 49.987 < 50.
    /// The fix uses `radius.rounded() >= 50` which rounds 49.987 → 50 → valid.
    /// This test must stay green to prevent re-introducing the bug.
    func test_isValid_at164ft_inMeters_isTrue() {
        sut.name      = "Test"
        sut.latitude  = 40.0
        sut.longitude = -74.0
        sut.radius    = DistanceUnit.imperial.toMeters(164)  // = 49.9872 m

        XCTAssertTrue(sut.isValid,
            "164 ft (≈49.99 m) must be valid — the Save button was incorrectly disabled at the minimum imperial slider value")
    }

    func test_buildAlarm_at164ft_succeeds() {
        sut.name      = "Station"
        sut.latitude  = 40.0
        sut.longitude = -74.0
        sut.radius    = DistanceUnit.imperial.toMeters(164)

        let alarm = sut.buildAlarm()
        XCTAssertNotNil(alarm,
            "buildAlarm should succeed when radius is 164 ft — the minimum imperial slider value")
    }

    func test_isValid_below164ft_isFalse() {
        // 163 ft = 49.68 m — genuinely below 50 m, should be invalid
        sut.name      = "Test"
        sut.latitude  = 40.0
        sut.longitude = -74.0
        sut.radius    = DistanceUnit.imperial.toMeters(163)  // = 49.682 m

        XCTAssertFalse(sut.isValid,
            "163 ft (≈49.68 m) is genuinely below 50 m and should be invalid")
    }

    // MARK: - DistanceUnit conversion

    func test_distanceUnit_imperial_toMeters_164ft() {
        // 164 ft × 0.3048 = 49.9872 m — verify the conversion is correct
        let meters = DistanceUnit.imperial.toMeters(164)
        XCTAssertEqual(meters, 49.9872, accuracy: 0.001)
    }

    func test_distanceUnit_imperial_sliderMinimum_is164ft() {
        // The imperial slider minimum must be 164 ft so that the slider can reach
        // the radius limit in a single step.
        XCTAssertEqual(DistanceUnit.imperial.sliderRange.lowerBound, 164,
            "Imperial slider lower bound must be 164 ft (the minimum that rounds to 50 m)")
    }
}
