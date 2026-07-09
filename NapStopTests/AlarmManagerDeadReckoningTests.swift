// Copyright © 2026 Robert Bartis. All rights reserved.

// AlarmManagerDeadReckoningTests.swift
// Coverage for the opt-in, per-alarm dead-reckoning signal-loss bridge added
// to AlarmManager.swift (docs/dead-reckoning-design.md). Mirrors the test-seam
// conventions established in AlarmManagerETAFireTests.swift:
//   - `handleLocationAvailabilityChanged(_:)` and `evaluateDeadReckoning(for:now:)`
//     are internal (not private) so this test target can drive them directly,
//     bypassing LocationManager/CLLocationManager and a real Timer entirely.
//   - `evaluateDeadReckoning`'s injectable `now:` parameter (mirroring
//     AddAlarmView.freshLocation's pattern) means grace-period-expiry tests
//     don't depend on real wall-clock waits.
//
// The single most important test here is `test_deadReckoning_flagOff_neverBridges`:
// it is the regression the design doc calls out explicitly (§Testing) — an
// alarm that has NOT opted in must behave identically to today, even when a
// signal-loss event fires and an evaluation tick lands squarely inside what
// would otherwise be a firing window.

import XCTest
import CoreLocation
@testable import GeoNap

@MainActor
final class AlarmManagerDeadReckoningTests: XCTestCase {

    var sut: AlarmManager!

    override func setUp() {
        super.setUp()
        sut = AlarmManager()
    }

    override func tearDown() {
        sut = nil
        super.tearDown()
    }

    // Penn Station, consistent with AlarmManagerETAFireTests.
    private let destLat = 40.7506
    private let destLon = -73.9971

    private func makeTimeAlarm(leadTimeMinutes: Int = 5,
                                deadReckoningEnabled: Bool = true,
                                hasTimeWindow: Bool = false,
                                windowStart: Date? = nil,
                                windowEnd: Date? = nil) -> NapAlarm {
        NapAlarm(name: "Penn Station",
                 latitude: destLat, longitude: destLon,
                 triggerMode: .time, leadTimeMinutes: leadTimeMinutes,
                 regionEvent: .onEntry,
                 hasTimeWindow: hasTimeWindow,
                 windowStart: windowStart,
                 windowEnd: windowEnd,
                 deadReckoningEnabled: deadReckoningEnabled)
    }

    /// A fix `meters` from the destination (due north) at an explicit
    /// timestamp — unlike AlarmManagerETAFireTests' single-fix helper, dead
    /// reckoning needs two fixes with a real Δt between them to compute a
    /// closing rate, so the timestamp must be controllable.
    private func fix(metersFromDestination meters: Double,
                      speed: CLLocationSpeed,
                      at t: Date) -> CLLocation {
        let deltaLat = meters / 111_320.0
        return CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: destLat + deltaLat, longitude: destLon),
            altitude: 0,
            horizontalAccuracy: 10,
            verticalAccuracy: 10,
            course: 0,
            speed: speed,
            timestamp: t
        )
    }

    private func hhmm(_ h: Int, _ m: Int) -> Date {
        Calendar.current.date(bySettingHour: h, minute: m, second: 0, of: Date()) ?? Date()
    }

    /// Arms `alarm`, enters its outer warm-up ring, and feeds two fixes
    /// `intervalSeconds` apart so the ETA estimator has both an
    /// `averageSpeed` and a `closingRate` — the minimum needed for a
    /// dead-reckoning snapshot to be captured on signal loss. Returns the
    /// live ETA at the second fix so callers can assert it doesn't already
    /// qualify to fire on its own.
    @discardableResult
    private func armAndTrack(_ alarm: NapAlarm,
                              firstDistance: Double,
                              secondDistance: Double,
                              speed: CLLocationSpeed,
                              intervalSeconds: TimeInterval = 5) -> TimeInterval {
        sut.add(alarm: alarm)
        sut.simulateRegionEntered(regionID: alarm.id.uuidString + NapAlarm.warmupRegionSuffix)
        let t0 = Date()
        sut.simulateLocationUpdate(fix(metersFromDestination: firstDistance, speed: speed, at: t0))
        sut.simulateLocationUpdate(fix(metersFromDestination: secondDistance, speed: speed, at: t0.addingTimeInterval(intervalSeconds)))
        return secondDistance / speed
    }

    // MARK: - Critical regression: flag off must never bridge

    func test_deadReckoning_flagOff_neverBridges() {
        // 7000 m out at 20 m/s → live ETA 350 s, safely above the 300 s (5 min)
        // lead time, so no premature fire from the two setup fixes themselves.
        let alarm = makeTimeAlarm(leadTimeMinutes: 5, deadReckoningEnabled: false)
        let liveETA = armAndTrack(alarm, firstDistance: 7100, secondDistance: 7000, speed: 20)
        XCTAssertGreaterThan(liveETA, 300, "Test setup must not already qualify to fire live")
        XCTAssertEqual(sut.alarms.first?.state, .active)

        sut.handleLocationAvailabilityChanged(true)   // signal lost
        // Evaluate at +60s — well inside the 75 s grace period an ENABLED
        // alarm would get for a 5-minute lead time, and comfortably past the
        // point (+50s) where a bridged alarm would have fired (see the
        // enabled-equivalent test below).
        sut.evaluateDeadReckoning(for: alarm.id, now: Date().addingTimeInterval(60))

        XCTAssertEqual(sut.alarms.first?.state, .active,
            "An alarm that has not opted into dead reckoning must never fire from a signal-loss extrapolation — only from a live GPS fix or the geofence backstop")
        XCTAssertEqual(sut.alarms.first?.triggerCount, 0)
    }

    // MARK: - Enabled: fires while bridging a gap

    func test_deadReckoning_enabled_firesWithinGracePeriod() {
        // Same geometry as the flag-off test: live ETA is 350 s (above the
        // 300 s threshold) so the two setup fixes alone must not fire it.
        let alarm = makeTimeAlarm(leadTimeMinutes: 5, deadReckoningEnabled: true)
        let liveETA = armAndTrack(alarm, firstDistance: 7100, secondDistance: 7000, speed: 20)
        XCTAssertGreaterThan(liveETA, 300)
        XCTAssertEqual(sut.alarms.first?.state, .active)

        sut.handleLocationAvailabilityChanged(true)
        // At +60s, extrapolated ETA = 350 - 60 = 290s <= 300s lead time, and
        // 60s is still within the 75s grace period for a 5-minute lead time
        // (NapAlarm.deadReckoningGracePeriod(leadTimeMinutes: 5) == 75).
        sut.evaluateDeadReckoning(for: alarm.id, now: Date().addingTimeInterval(60))

        XCTAssertEqual(sut.alarms.first?.state, .triggered,
            "An enabled alarm must fire once the extrapolated ETA drops to the lead time, even while GPS is unavailable")
        XCTAssertEqual(sut.alarms.first?.triggerCount, 1)
    }

    func test_deadReckoning_enabled_doesNotFire_beforeExtrapolatedETAQualifies() {
        let alarm = makeTimeAlarm(leadTimeMinutes: 5, deadReckoningEnabled: true)
        armAndTrack(alarm, firstDistance: 7100, secondDistance: 7000, speed: 20)

        sut.handleLocationAvailabilityChanged(true)
        // At +10s, extrapolated ETA = 350 - 10 = 340s, still above the 300s
        // lead time — must not fire yet.
        sut.evaluateDeadReckoning(for: alarm.id, now: Date().addingTimeInterval(10))

        XCTAssertEqual(sut.alarms.first?.state, .active,
            "Must not fire before the extrapolated ETA actually drops to the lead time")
    }

    // MARK: - Grace period expiry reverts to the geofence backstop

    func test_deadReckoning_expiresAfterGracePeriod_withoutFiring() {
        // Lead time 1 minute → grace period floors to 30s (min bound in
        // NapAlarm.deadReckoningGracePeriod). Distance is intentionally too
        // far for a 20 m/s closing rate to bridge within 30s, so the gap
        // must expire before ever qualifying to fire.
        let alarm = makeTimeAlarm(leadTimeMinutes: 1, deadReckoningEnabled: true)
        armAndTrack(alarm, firstDistance: 7100, secondDistance: 7000, speed: 20)

        sut.handleLocationAvailabilityChanged(true)
        // Past the 30s grace cap — the snapshot must expire, not fire.
        sut.evaluateDeadReckoning(for: alarm.id, now: Date().addingTimeInterval(35))
        XCTAssertEqual(sut.alarms.first?.state, .active,
            "Once the grace period expires the alarm must fall back to the geofence backstop, not fire on a stale extrapolation")

        // A second, later evaluation for the same id must be a no-op — the
        // expired snapshot must actually be cleared, not merely skipped once.
        sut.evaluateDeadReckoning(for: alarm.id, now: Date().addingTimeInterval(9999))
        XCTAssertEqual(sut.alarms.first?.state, .active)
        XCTAssertEqual(sut.alarms.first?.triggerCount, 0)
    }

    // MARK: - Never fires from a standing start

    func test_deadReckoning_neverFires_whenStoppedAtGapStart() {
        // Both fixes report 0.5 m/s — below ETAEstimator.minSpeed (1.0) — so
        // averageSpeed is 0.5. The worst-case scenario the design doc calls
        // out: a train stopped right as signal is lost. Even a very generous
        // elapsed time must not produce a fire.
        let alarm = makeTimeAlarm(leadTimeMinutes: 5, deadReckoningEnabled: true)
        armAndTrack(alarm, firstDistance: 500, secondDistance: 480, speed: 0.5)
        XCTAssertEqual(sut.alarms.first?.state, .active, "Below minSpeed, live ETA is nil — must not fire from the setup fixes")

        sut.handleLocationAvailabilityChanged(true)
        sut.evaluateDeadReckoning(for: alarm.id, now: Date().addingTimeInterval(60))

        XCTAssertEqual(sut.alarms.first?.state, .active,
            "A gap that starts at (or below) minSpeed must never fire on dead reckoning alone — there's no reliable motion to extrapolate")
    }

    // MARK: - A real fix resuming clears the bridge

    func test_deadReckoning_realFixResumed_clearsBridge() {
        let alarm = makeTimeAlarm(leadTimeMinutes: 5, deadReckoningEnabled: true)
        armAndTrack(alarm, firstDistance: 7100, secondDistance: 7000, speed: 20)

        sut.handleLocationAvailabilityChanged(true)
        sut.handleLocationAvailabilityChanged(false)   // signal restored before the gap could fire

        // Same +60s that fires in test_deadReckoning_enabled_firesWithinGracePeriod
        // — here it must be a no-op because the bridge was already cleared.
        sut.evaluateDeadReckoning(for: alarm.id, now: Date().addingTimeInterval(60))

        XCTAssertEqual(sut.alarms.first?.state, .active,
            "A real fix resuming must clear the dead-reckoning bridge so a stale extrapolation can't fire later")
    }

    // MARK: - Never starts without an active ETA tracking session

    func test_deadReckoning_doesNotStart_whenNotTrackingETA() {
        // deadReckoningEnabled == true, but the alarm never entered its outer
        // warm-up ring, so etaEstimators is empty for it — there is nothing
        // to snapshot a closing rate from.
        let alarm = makeTimeAlarm(leadTimeMinutes: 5, deadReckoningEnabled: true)
        sut.add(alarm: alarm)

        sut.handleLocationAvailabilityChanged(true)
        sut.evaluateDeadReckoning(for: alarm.id, now: Date().addingTimeInterval(9999))

        XCTAssertEqual(sut.alarms.first?.state, .active,
            "Dead reckoning must only bridge alarms that are actively being tracked via continuous GPS")
    }

    // MARK: - Time window guard still applies

    func test_deadReckoning_doesNotFire_outsideTimeWindow() throws {
        let hour = Calendar.current.component(.hour, from: Date())
        guard hour != 1 else {
            throw XCTSkip("Skipping window-block test: current hour is 01 (inside window)")
        }
        let alarm = makeTimeAlarm(leadTimeMinutes: 5, deadReckoningEnabled: true,
                                   hasTimeWindow: true,
                                   windowStart: hhmm(1, 0), windowEnd: hhmm(2, 0))
        armAndTrack(alarm, firstDistance: 7100, secondDistance: 7000, speed: 20)

        sut.handleLocationAvailabilityChanged(true)
        sut.evaluateDeadReckoning(for: alarm.id, now: Date().addingTimeInterval(60))

        XCTAssertEqual(sut.alarms.first?.state, .active,
            "A dead-reckoning fire must respect the alarm's active time window exactly like the live ETA path does")
    }

    // MARK: - Firing via dead reckoning fully tears down tracking

    func test_deadReckoning_fire_stopsTracking_soLaterEvaluationsAreNoOps() {
        let alarm = makeTimeAlarm(leadTimeMinutes: 5, deadReckoningEnabled: true)
        armAndTrack(alarm, firstDistance: 7100, secondDistance: 7000, speed: 20)

        sut.handleLocationAvailabilityChanged(true)
        sut.evaluateDeadReckoning(for: alarm.id, now: Date().addingTimeInterval(60))
        XCTAssertEqual(sut.alarms.first?.triggerCount, 1)

        // The fire path (fireTimeBased → stopETATracking) must clear the
        // dead-reckoning bookkeeping too — a stray later evaluation for the
        // same id must not double-fire or crash.
        sut.evaluateDeadReckoning(for: alarm.id, now: Date().addingTimeInterval(120))

        XCTAssertEqual(sut.alarms.first?.triggerCount, 1,
            "A fired, non-repeating alarm must not fire again from a later dead-reckoning evaluation")
    }
}
