// ETAEstimatorTests.swift
// Unit tests for the time-based-alarm ETA engine and the new NapAlarm trigger fields.

import XCTest
import CoreLocation
@testable import GeoNap

final class ETAEstimatorTests: XCTestCase {

    // Helper: build a CLLocation with explicit speed + accuracy + timestamp.
    private func fix(_ lat: Double, _ lon: Double,
                     speed: CLLocationSpeed, accuracy: CLLocationAccuracy,
                     at t: Date) -> CLLocation {
        CLLocation(coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                   altitude: 0,
                   horizontalAccuracy: accuracy,
                   verticalAccuracy: 1,
                   course: 0,
                   speed: speed,
                   timestamp: t)
    }

    // A point ~1 km due north of the start, used as a destination.
    // 0.009° latitude ≈ 1001 m.
    private let start = CLLocationCoordinate2D(latitude: 40.0000, longitude: -74.0000)
    private let dest  = CLLocationCoordinate2D(latitude: 40.0090, longitude: -74.0000)

    func test_rejectsLowAccuracyFixes() {
        var e = ETAEstimator()
        let t = Date()
        e.add(fix(40.0, -74.0, speed: 10, accuracy: 500, at: t))   // coarse → ignored
        XCTAssertNil(e.averageSpeed, "Fixes worse than the accuracy gate must be ignored")
        XCTAssertNil(e.lastLocation)
    }

    func test_averageSpeed_overWindow() {
        var e = ETAEstimator()
        let t = Date()
        e.add(fix(40.000, -74.0, speed: 10, accuracy: 5, at: t))
        e.add(fix(40.001, -74.0, speed: 20, accuracy: 5, at: t.addingTimeInterval(1)))
        XCTAssertEqual(e.averageSpeed ?? 0, 15, accuracy: 0.001)
    }

    func test_eta_isDistanceOverSpeed() {
        var e = ETAEstimator()
        let t = Date()
        // Sitting at `start`, moving 10 m/s, destination ~1001 m away → ~100 s.
        e.add(fix(start.latitude, start.longitude, speed: 10, accuracy: 5, at: t))
        let eta = e.eta(to: dest)
        XCTAssertNotNil(eta)
        XCTAssertEqual(eta!, 100, accuracy: 5)   // ~1001 m / 10 m/s
    }

    func test_stopped_yieldsNilETA() {
        var e = ETAEstimator()
        let t = Date()
        e.add(fix(start.latitude, start.longitude, speed: 0, accuracy: 5, at: t))
        XCTAssertNil(e.eta(to: dest), "Stopped (speed < minSpeed) must not produce an ETA")
        XCTAssertFalse(e.shouldFire(to: dest, leadTimeMinutes: 5))
    }

    func test_shouldFire_whenWithinLeadTime() {
        var e = ETAEstimator()
        let t = Date()
        // 20 m/s toward a ~1001 m destination → ETA ~50 s < 5 min lead.
        e.add(fix(start.latitude, start.longitude, speed: 20, accuracy: 5, at: t))
        XCTAssertTrue(e.shouldFire(to: dest, leadTimeMinutes: 5))
        // ...but not within a 0-minute lead (ETA 50 s > 0 s).
        XCTAssertFalse(e.shouldFire(to: dest, leadTimeMinutes: 0))
    }

    func test_derivesSpeed_whenDopplerSpeedInvalid() {
        var e = ETAEstimator()
        let t = Date()
        // Two fixes 0.0009° (~100 m) apart, 10 s apart, speed=-1 (invalid) → ~10 m/s.
        e.add(fix(40.0000, -74.0, speed: -1, accuracy: 5, at: t))
        e.add(fix(40.0009, -74.0, speed: -1, accuracy: 5, at: t.addingTimeInterval(10)))
        XCTAssertEqual(e.averageSpeed ?? 0, 5, accuracy: 1.5,
                       "Average of derived ~10 m/s and the initial 0 should be ~5 m/s")
    }

    // MARK: - NapAlarm trigger fields

    func test_triggerMode_defaultsToDistance() {
        let a = NapAlarm(name: "T", latitude: 40, longitude: -74)
        XCTAssertEqual(a.triggerMode, .distance)
        XCTAssertEqual(a.leadTimeMinutes, 5)
    }

    func test_triggerMode_roundTrips() {
        let a = NapAlarm(name: "T", latitude: 40, longitude: -74,
                         triggerMode: .time, leadTimeMinutes: 8)
        XCTAssertEqual(a.triggerMode, .time)
        XCTAssertEqual(a.triggerModeRaw, "time")
        XCTAssertEqual(a.leadTimeMinutes, 8)
    }

    func test_outerRingRadius_includesWarmupAndClamps() {
        let a = NapAlarm(name: "T", latitude: 40, longitude: -74,
                         triggerMode: .time, leadTimeMinutes: 5)
        // Default warm-up = 5 min, so ring covers (5 + 5) min:
        // 40 m/s * 10 min * 60 = 24 000 m, within [300, 30000].
        XCTAssertEqual(a.outerRingRadius(), 24_000, accuracy: 0.5)
        // Without warm-up: 40 * 5 * 60 = 12 000 m.
        XCTAssertEqual(a.outerRingRadius(warmupMinutes: 0), 12_000, accuracy: 0.5)
        // Tiny speed clamps up to the floor.
        XCTAssertEqual(a.outerRingRadius(capSpeed: 0.1, warmupMinutes: 0, minRadius: 300),
                       300, accuracy: 0.5)
        // Huge lead clamps down to the ceiling.
        a.leadTimeMinutes = 600
        XCTAssertEqual(a.outerRingRadius(), 30_000, accuracy: 0.5)
    }
}
