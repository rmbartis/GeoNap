// GPSLockIndicatorTests.swift
// Coverage for AddAlarmView's "Waiting for GPS lock…" indicator — flagged as
// an untested UI/ViewModel state transition in the 2026-06-29 CI review
// (docs/ci-and-help-review-2026-06-29.md, recommendation #3).
//
// The indicator's condition (`isWaitingForGPSLock`) and its fix-freshness
// gate (`freshCurrentLocation`) were private computed logic embedded directly
// in the AddAlarmView struct, coupled to `locationManager`/`viewModel`
// instance state. Extracted into two static, pure functions
// (`AddAlarmView.isWaitingForGPSLock(...)` and `AddAlarmView.freshLocation(...)`)
// so they're unit testable without instantiating the view or a real
// LocationManager (Bob, 2026-07-05).

import XCTest
import CoreLocation
@testable import GeoNap

final class GPSLockIndicatorTests: XCTestCase {

    // MARK: - isWaitingForGPSLock

    func test_isWaitingForGPSLock_true_whenAllConditionsMet() {
        XCTAssertTrue(AddAlarmView.isWaitingForGPSLock(
            isEditingExistingAlarm: false,
            hasLocation: false,
            isLocationUnavailable: false,
            authorizationStatus: .authorizedWhenInUse,
            hasFreshCurrentLocation: false
        ))
    }

    func test_isWaitingForGPSLock_true_withAuthorizedAlways() {
        XCTAssertTrue(AddAlarmView.isWaitingForGPSLock(
            isEditingExistingAlarm: false,
            hasLocation: false,
            isLocationUnavailable: false,
            authorizationStatus: .authorizedAlways,
            hasFreshCurrentLocation: false
        ))
    }

    func test_isWaitingForGPSLock_false_whenEditingExistingAlarm() {
        XCTAssertFalse(AddAlarmView.isWaitingForGPSLock(
            isEditingExistingAlarm: true,
            hasLocation: false,
            isLocationUnavailable: false,
            authorizationStatus: .authorizedWhenInUse,
            hasFreshCurrentLocation: false
        ), "Editing an existing alarm must never show the GPS-lock indicator — it already has a location")
    }

    func test_isWaitingForGPSLock_false_whenLocationAlreadySet() {
        XCTAssertFalse(AddAlarmView.isWaitingForGPSLock(
            isEditingExistingAlarm: false,
            hasLocation: true,
            isLocationUnavailable: false,
            authorizationStatus: .authorizedWhenInUse,
            hasFreshCurrentLocation: false
        ), "Once the user has a location (map tap, search, or auto-fill), the indicator must clear")
    }

    func test_isWaitingForGPSLock_false_whenLocationUnavailable() {
        XCTAssertFalse(AddAlarmView.isWaitingForGPSLock(
            isEditingExistingAlarm: false,
            hasLocation: false,
            isLocationUnavailable: true,
            authorizationStatus: .authorizedWhenInUse,
            hasFreshCurrentLocation: false
        ), "If hardware reports location unavailable, show that warning instead of an indefinite spinner")
    }

    func test_isWaitingForGPSLock_false_whenNotDetermined() {
        XCTAssertFalse(AddAlarmView.isWaitingForGPSLock(
            isEditingExistingAlarm: false,
            hasLocation: false,
            isLocationUnavailable: false,
            authorizationStatus: .notDetermined,
            hasFreshCurrentLocation: false
        ), "Without authorization yet, there's a permission prompt to show — not a GPS spinner")
    }

    func test_isWaitingForGPSLock_false_whenDenied() {
        XCTAssertFalse(AddAlarmView.isWaitingForGPSLock(
            isEditingExistingAlarm: false,
            hasLocation: false,
            isLocationUnavailable: false,
            authorizationStatus: .denied,
            hasFreshCurrentLocation: false
        ))
    }

    func test_isWaitingForGPSLock_false_whenRestricted() {
        XCTAssertFalse(AddAlarmView.isWaitingForGPSLock(
            isEditingExistingAlarm: false,
            hasLocation: false,
            isLocationUnavailable: false,
            authorizationStatus: .restricted,
            hasFreshCurrentLocation: false
        ))
    }

    func test_isWaitingForGPSLock_false_whenFreshFixAlreadyArrived() {
        XCTAssertFalse(AddAlarmView.isWaitingForGPSLock(
            isEditingExistingAlarm: false,
            hasLocation: false,
            isLocationUnavailable: false,
            authorizationStatus: .authorizedWhenInUse,
            hasFreshCurrentLocation: true
        ), "A fresh fix has already arrived — the indicator must clear even before hasLocation catches up")
    }

    // MARK: - freshLocation

    private func location(secondsAgo: TimeInterval, accuracy: CLLocationAccuracy, now: Date) -> CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 40.7506, longitude: -73.9971),
            altitude: 0,
            horizontalAccuracy: accuracy,
            verticalAccuracy: accuracy,
            course: 0,
            speed: 0,
            timestamp: now.addingTimeInterval(-secondsAgo)
        )
    }

    func test_freshLocation_nilInput_returnsNil() {
        XCTAssertNil(AddAlarmView.freshLocation(nil))
    }

    func test_freshLocation_recentAndAccurate_isReturned() {
        let now = Date()
        let loc = location(secondsAgo: 5, accuracy: 20, now: now)
        XCTAssertNotNil(AddAlarmView.freshLocation(loc, now: now))
    }

    func test_freshLocation_stale_returnsNil() {
        let now = Date()
        let loc = location(secondsAgo: 45, accuracy: 20, now: now)   // > default maxAge (30s)
        XCTAssertNil(AddAlarmView.freshLocation(loc, now: now),
            "A fix older than 30 s is a stale last-known location, not where the user is now")
    }

    func test_freshLocation_ageBoundary_isExclusive() {
        let now = Date()
        let loc = location(secondsAgo: 30, accuracy: 20, now: now)   // exactly at maxAge
        XCTAssertNil(AddAlarmView.freshLocation(loc, now: now),
            "age < maxAge is strict — exactly 30 s old must be rejected, matching the source's `age < 30` check")
    }

    func test_freshLocation_justUnderAgeBoundary_isAccepted() {
        let now = Date()
        let loc = location(secondsAgo: 29.9, accuracy: 20, now: now)
        XCTAssertNotNil(AddAlarmView.freshLocation(loc, now: now))
    }

    func test_freshLocation_lowAccuracy_returnsNil() {
        let now = Date()
        let loc = location(secondsAgo: 5, accuracy: 150, now: now)   // > default maxAccuracy (100 m)
        XCTAssertNil(AddAlarmView.freshLocation(loc, now: now),
            "A 150 m accuracy fix (coarse cell/Wi-Fi) is too imprecise to auto-centre an alarm")
    }

    func test_freshLocation_accuracyBoundary_isExclusive() {
        let now = Date()
        let loc = location(secondsAgo: 5, accuracy: 100, now: now)   // exactly at maxAccuracy
        XCTAssertNil(AddAlarmView.freshLocation(loc, now: now),
            "accuracy < maxAccuracy is strict — exactly 100 m must be rejected, matching the source's `< 100` check")
    }

    func test_freshLocation_negativeAccuracy_returnsNil() {
        // CLLocation reports a negative horizontalAccuracy when the fix is invalid.
        let now = Date()
        let loc = location(secondsAgo: 5, accuracy: -1, now: now)
        XCTAssertNil(AddAlarmView.freshLocation(loc, now: now),
            "A negative accuracy value means CoreLocation itself considers the fix invalid")
    }

    func test_freshLocation_customMaxAgeAndAccuracy_areRespected() {
        let now = Date()
        let loc = location(secondsAgo: 40, accuracy: 120, now: now)
        // Both defaults would reject this fix; wider custom thresholds accept it.
        XCTAssertNotNil(AddAlarmView.freshLocation(loc, now: now, maxAge: 60, maxAccuracy: 150))
    }
}
