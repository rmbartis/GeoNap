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
        // isValid rejects (0,0): ViewModel now requires an explicit pin placement.
        XCTAssertFalse(sut.isValid)
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

    // MARK: - Edit round-trip (regression tests for alarm-sound bug)
    // The bug: buildAlarm() in edit mode created a new NapAlarm instead of
    // mutating the existing SwiftData-managed object, so all edits — including
    // the user-selected sound — were silently discarded.

    func test_editRoundTrip_mutatesExistingObject_notifcationSound() {
        // Arrange: existing alarm with the default sound.
        let existing = NapAlarm(
            name: "Penn Station", latitude: 40.750, longitude: -73.997,
            notificationSound: .default
        )
        sut.load(alarm: existing)

        // Act: user picks a custom sound and taps Save.
        let custom = NotificationSound(rawValue: "train-horn.wav")
        sut.notificationSound = custom
        guard let built = sut.buildAlarm() else {
            XCTFail("buildAlarm returned nil"); return
        }

        // Assert: buildAlarm must return the SAME managed object and its
        // sound must reflect the user's selection.
        XCTAssertTrue(built === existing,
            "buildAlarm() in edit mode must return the existing NapAlarm object " +
            "so SwiftData tracks the mutation — not a newly allocated one.")
        XCTAssertEqual(existing.notificationSound, custom,
            "The existing NapAlarm's notificationSound must be updated in place.")
    }

    func test_editRoundTrip_mutatesAllFields() {
        let existing = NapAlarm(
            name: "Original", latitude: 10.0, longitude: 20.0,
            radius: 200, regionEvent: .onEntry, isRepeating: false,
            notificationSound: .default
        )
        sut.load(alarm: existing)

        sut.name              = "Updated"
        sut.latitude          = 51.5
        sut.longitude         = -0.12
        sut.radius            = 500
        sut.regionEvent       = .onExit
        sut.isRepeating       = true
        sut.notificationSound = NotificationSound(rawValue: "boat-horn.wav")

        guard let built = sut.buildAlarm() else {
            XCTFail("buildAlarm returned nil"); return
        }

        XCTAssertTrue(built === existing, "Edit mode must return the existing alarm object")
        XCTAssertEqual(existing.name,              "Updated")
        XCTAssertEqual(existing.latitude,          51.5,  accuracy: 0.0001)
        XCTAssertEqual(existing.longitude,         -0.12, accuracy: 0.0001)
        XCTAssertEqual(existing.radius,            500)
        XCTAssertEqual(existing.regionEvent,       .onExit)
        XCTAssertTrue(existing.isRepeating)
        XCTAssertEqual(existing.notificationSound, NotificationSound(rawValue: "boat-horn.wav"))
    }

    func test_editRoundTrip_afterReset_buildCreatesNewObject() {
        // After reset(), buildAlarm() must NOT mutate the previously loaded alarm.
        let existing = NapAlarm(
            name: "Train", latitude: 40.750, longitude: -73.997,
            notificationSound: .default
        )
        sut.load(alarm: existing)
        sut.reset()

        sut.name      = "New Alarm"
        sut.latitude  = 40.758
        sut.longitude = -73.985

        guard let built = sut.buildAlarm() else {
            XCTFail("buildAlarm returned nil"); return
        }
        XCTAssertFalse(built === existing,
            "After reset(), buildAlarm() must not mutate the previously loaded alarm")
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
        // 155 ft = 47.24 m — well below the 50 m threshold even after rounding, should be invalid.
        // (163 ft ≈ 49.68 m rounds to 50 m and is intentionally accepted by the rounding rule
        //  that keeps 164 ft ≈ 49.99 m valid; use 155 ft to test a clearly out-of-range value.)
        sut.name      = "Test"
        sut.latitude  = 40.0
        sut.longitude = -74.0
        sut.radius    = DistanceUnit.imperial.toMeters(155)  // = 47.244 m

        XCTAssertFalse(sut.isValid,
            "155 ft (≈47.24 m) rounds to 47 m and should be invalid")
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
