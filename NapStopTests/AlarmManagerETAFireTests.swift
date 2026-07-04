// AlarmManagerETAFireTests.swift
// Coverage for the time-based (ETA) "final approach" fire path in
// AlarmManager.swift — previously untested per the 2026-06-29 CI review
// (docs/ci-and-help-review-2026-06-29.md, recommendation #1): only the
// warm-up-ring "must not self-fire" regression existed
// (AutoSMSFreshnessTests.TimeBasedWarmupRingTests). The actual "ETA drops to
// lead time → fire" loop, its time-window guard, and the "already inside the
// outer ring at arm time" branch had no test at all.
//
// Enabled by two small, behaviour-preserving changes to AlarmManager.swift
// (Bob, 2026-07-05):
//   1. `handleLocationUpdate(_:)` changed from `private` to internal, mirroring
//      `handleRegionEvent` — lets a test-target extension drive it directly,
//      the same pattern `simulateRegionEntered`/`simulateRegionExited` already use.
//   2. The "are we already inside the outer ring when the alarm is armed"
//      check was extracted from `startMonitoring` into a pure static method,
//      `AlarmManager.isAlreadyInsideWarmupRing(alarm:currentLocation:)`, so
//      the distance/radius decision is unit-testable without a real
//      CLLocationManager.

import XCTest
import CoreLocation
@testable import GeoNap

// MARK: - Testability extension (mirrors simulateRegionEntered/Exited)

extension AlarmManager {
    /// Feeds a location fix directly into the ETA engine, bypassing
    /// LocationManager/CLLocationManager entirely.
    func simulateLocationUpdate(_ location: CLLocation) {
        handleLocationUpdate(location)
    }
}

// MARK: - ETA fire path

@MainActor
final class AlarmManagerETAFireTests: XCTestCase {

    var sut: AlarmManager!

    override func setUp() {
        super.setUp()
        sut = AlarmManager()
    }

    override func tearDown() {
        sut = nil
        super.tearDown()
    }

    // Penn Station, same coordinate TimeBasedWarmupRingTests uses.
    private let destLat = 40.7506
    private let destLon = -73.9971

    private func makeTimeAlarm(leadTimeMinutes: Int = 5,
                                hasTimeWindow: Bool = false,
                                windowStart: Date? = nil,
                                windowEnd: Date? = nil) -> NapAlarm {
        // Argument order must match NapAlarm's declared init order (Swift
        // requires labeled args in declaration order): ... triggerMode,
        // leadTimeMinutes, regionEvent, ... hasTimeWindow, windowStart, windowEnd.
        NapAlarm(name: "Penn Station",
                 latitude: destLat, longitude: destLon,
                 triggerMode: .time, leadTimeMinutes: leadTimeMinutes,
                 regionEvent: .onEntry,
                 hasTimeWindow: hasTimeWindow,
                 windowStart: windowStart,
                 windowEnd: windowEnd)
    }

    /// A fix `meters` away from the alarm destination (due north), reported
    /// at `speed` m/s — enough to compute a deterministic ETA without relying
    /// on multi-fix speed averaging.
    private func fix(metersFromDestination meters: Double, speed: CLLocationSpeed) -> CLLocation {
        let deltaLat = meters / 111_320.0   // ~metres per degree latitude
        return CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: destLat + deltaLat, longitude: destLon),
            altitude: 0,
            horizontalAccuracy: 10,   // well under ETAEstimator's 50 m accuracyGate
            verticalAccuracy: 10,
            course: 0,
            speed: speed,
            timestamp: Date()
        )
    }

    private func hhmm(_ h: Int, _ m: Int) -> Date {
        Calendar.current.date(bySettingHour: h, minute: m, second: 0, of: Date()) ?? Date()
    }

    // MARK: - Fires when ETA ≤ lead time

    func test_etaFire_fires_whenCloseAndFastEnough() {
        let alarm = makeTimeAlarm(leadTimeMinutes: 5)   // 300 s threshold
        sut.add(alarm: alarm)

        // Enter the outer warm-up ring — begins ETA tracking, does not fire.
        sut.simulateRegionEntered(regionID: alarm.id.uuidString + NapAlarm.warmupRegionSuffix)
        XCTAssertEqual(sut.alarms.first?.state, .active)

        // 300 m out at 50 m/s → ETA = 6 s, well within the 300 s lead time.
        sut.simulateLocationUpdate(fix(metersFromDestination: 300, speed: 50))

        XCTAssertEqual(sut.alarms.first?.state, .triggered,
            "A time-based alarm must fire once ETA drops to/below the requested lead time")
        XCTAssertEqual(sut.alarms.first?.triggerCount, 1)
    }

    func test_etaFire_doesNotFire_whenTooSlowToComputeETA() {
        let alarm = makeTimeAlarm(leadTimeMinutes: 5)
        sut.add(alarm: alarm)
        sut.simulateRegionEntered(regionID: alarm.id.uuidString + NapAlarm.warmupRegionSuffix)

        // Speed below ETAEstimator.minSpeed (1.0 m/s, "stopped") → eta() is nil
        // regardless of distance → must never fire from this fix alone.
        sut.simulateLocationUpdate(fix(metersFromDestination: 50, speed: 0.2))

        XCTAssertEqual(sut.alarms.first?.state, .active,
            "Below minSpeed, ETA is undefined (nil) — the alarm must not fire on a stalled/stopped fix")
    }

    func test_etaFire_doesNotFire_beforeEnteringWarmupRing() {
        // No warm-up-ring entry — etaEstimators is empty, so even a fix that
        // WOULD satisfy shouldFire must be a no-op (nothing is tracking yet).
        let alarm = makeTimeAlarm(leadTimeMinutes: 5)
        sut.add(alarm: alarm)

        sut.simulateLocationUpdate(fix(metersFromDestination: 300, speed: 50))

        XCTAssertEqual(sut.alarms.first?.state, .active,
            "A location update must be ignored entirely until the outer warm-up ring has been entered")
    }

    func test_etaFire_stopsTracking_afterFiring() {
        // fireTimeBased() tears down monitoring + ETA tracking (non-repeating).
        // A second, otherwise-qualifying fix after firing must not re-fire or
        // increment triggerCount again.
        let alarm = makeTimeAlarm(leadTimeMinutes: 5)
        sut.add(alarm: alarm)
        sut.simulateRegionEntered(regionID: alarm.id.uuidString + NapAlarm.warmupRegionSuffix)
        sut.simulateLocationUpdate(fix(metersFromDestination: 300, speed: 50))
        XCTAssertEqual(sut.alarms.first?.triggerCount, 1)

        sut.simulateLocationUpdate(fix(metersFromDestination: 10, speed: 50))

        XCTAssertEqual(sut.alarms.first?.triggerCount, 1,
            "ETA tracking must stop once the alarm fires — a later fix must not fire it again")
    }

    // MARK: - Respects the time window

    func test_etaFire_doesNotFire_outsideTimeWindow() throws {
        // Mirrors AlarmManagerRegionEdgeCaseTests.test_handleRegionEntry_doesNotFire_outsideTimeWindow
        // for the ETA path: window 01:00–02:00, current real time assumed outside it.
        let hour = Calendar.current.component(.hour, from: Date())
        guard hour != 1 else {
            throw XCTSkip("Skipping window-block test: current hour is 01 (inside window)")
        }

        let alarm = makeTimeAlarm(leadTimeMinutes: 5,
                                   hasTimeWindow: true,
                                   windowStart: hhmm(1, 0),
                                   windowEnd: hhmm(2, 0))
        sut.add(alarm: alarm)
        sut.simulateRegionEntered(regionID: alarm.id.uuidString + NapAlarm.warmupRegionSuffix)

        sut.simulateLocationUpdate(fix(metersFromDestination: 300, speed: 50))

        XCTAssertEqual(sut.alarms.first?.state, .active,
            "A time-based alarm outside its active window must not fire even when ETA qualifies")
    }

    // MARK: - Multiple concurrent time-based alarms

    func test_etaFire_onlyFiresMatchingAlarm_whenMultipleTracking() {
        let target    = makeTimeAlarm(leadTimeMinutes: 5)
        // `handleLocationUpdate` computes each tracked alarm's ETA independently
        // as straight-line distance ÷ average speed from the SAME fix — it has
        // no notion of heading/direction. So "must not fire" only holds if the
        // bystander's destination is far enough that even the test fix's speed
        // (50 m/s) can't bring its ETA under the 5-minute lead time. An earlier
        // version placed the bystander ~10 km away, which at 50 m/s is only
        // ~200 s — UNDER the 300 s threshold — causing a false fire that had
        // nothing to do with alarm-isolation logic. ~160 km guarantees an ETA
        // of tens of minutes regardless of the fix's speed.
        let bystander = NapAlarm(name: "Other Stop", latitude: 42.0, longitude: -75.0,
                                  triggerMode: .time, leadTimeMinutes: 5,
                                  regionEvent: .onEntry)
        sut.add(alarm: target)
        sut.add(alarm: bystander)

        sut.simulateRegionEntered(regionID: target.id.uuidString + NapAlarm.warmupRegionSuffix)
        sut.simulateRegionEntered(regionID: bystander.id.uuidString + NapAlarm.warmupRegionSuffix)

        // Fix is close to `target`'s destination only.
        sut.simulateLocationUpdate(fix(metersFromDestination: 300, speed: 50))

        let targetState    = sut.alarms.first(where: { $0.id == target.id })?.state
        let bystanderState = sut.alarms.first(where: { $0.id == bystander.id })?.state
        XCTAssertEqual(targetState, .triggered, "The alarm actually close to its destination must fire")
        XCTAssertEqual(bystanderState, .active, "A bystander alarm tracked from a different location must not fire")
    }

    // MARK: - "Already inside the outer ring at arm time" — pure decision logic

    func test_isAlreadyInsideWarmupRing_trueWhenWellWithinRadius() {
        let alarm = makeTimeAlarm(leadTimeMinutes: 5)
        let ringRadius = alarm.outerRingRadius()
        let here = fix(metersFromDestination: ringRadius / 2, speed: 0)
        XCTAssertTrue(AlarmManager.isAlreadyInsideWarmupRing(alarm: alarm, currentLocation: here))
    }

    func test_isAlreadyInsideWarmupRing_falseWhenWellOutsideRadius() {
        let alarm = makeTimeAlarm(leadTimeMinutes: 5)
        let ringRadius = alarm.outerRingRadius()
        let here = fix(metersFromDestination: ringRadius * 2, speed: 0)
        XCTAssertFalse(AlarmManager.isAlreadyInsideWarmupRing(alarm: alarm, currentLocation: here))
    }

    func test_isAlreadyInsideWarmupRing_falseWhenNoCurrentFix() {
        let alarm = makeTimeAlarm(leadTimeMinutes: 5)
        XCTAssertFalse(AlarmManager.isAlreadyInsideWarmupRing(alarm: alarm, currentLocation: nil),
            "No current fix means nothing to compare against — must not assume 'already inside'")
    }

    func test_isAlreadyInsideWarmupRing_justInsideRadius_isTrue() {
        // A safe margin below the radius, not the exact boundary — CLLocation's
        // geodesic distance() and this test's flat "meters ÷ 111,320 = degrees"
        // approximation diverge by tens of meters at this latitude, so an
        // exact-equality boundary check would be flaky. 1 km of margin absorbs
        // that divergence while still meaningfully testing "just inside."
        let alarm = makeTimeAlarm(leadTimeMinutes: 5)
        let ringRadius = alarm.outerRingRadius()
        let here = fix(metersFromDestination: ringRadius - 1000, speed: 0)
        XCTAssertTrue(AlarmManager.isAlreadyInsideWarmupRing(alarm: alarm, currentLocation: here))
    }

    func test_isAlreadyInsideWarmupRing_justOutsideRadius_isFalse() {
        let alarm = makeTimeAlarm(leadTimeMinutes: 5)
        let ringRadius = alarm.outerRingRadius()
        let here = fix(metersFromDestination: ringRadius + 1000, speed: 0)
        XCTAssertFalse(AlarmManager.isAlreadyInsideWarmupRing(alarm: alarm, currentLocation: here))
    }

    // MARK: - Integration: add() begins ETA tracking immediately when already inside the ring

    func test_add_beginsETATrackingImmediately_whenAlreadyInsideWarmupRing() {
        // Regression for the bug this branch exists to prevent: an alarm
        // created (or the app relaunched) already inside the outer ring gets
        // NO "region entered" event from iOS — without this branch, ETA
        // tracking would never start and the alarm would fall through to the
        // ~200 m inner backstop instead of firing at the requested lead time.
        //
        // Uses a real LocationManager only for its plain `currentLocation`
        // property (a stored @Published var — no CLLocationManager call
        // needed to set it). The CLLocationManager calls `add()` triggers
        // along the way (region monitoring, continuous updates) are all
        // guarded in LocationManager to no-op safely without authorization,
        // so this is safe to run headless in CI.
        let alarm = makeTimeAlarm(leadTimeMinutes: 5)
        let ringRadius = alarm.outerRingRadius()

        let locationManager = LocationManager()
        locationManager.currentLocation = fix(metersFromDestination: ringRadius / 2, speed: 0)
        sut.locationManager = locationManager

        sut.add(alarm: alarm)   // triggerMode == .time → startMonitoring checks "already inside?"

        // If tracking began, a subsequent fast/close fix must fire the alarm
        // WITHOUT ever having gone through simulateRegionEntered(warmup).
        // If tracking did NOT begin, etaEstimators is empty and this is a no-op.
        sut.simulateLocationUpdate(fix(metersFromDestination: 300, speed: 50))

        XCTAssertEqual(sut.alarms.first?.state, .triggered,
            "Being already inside the outer ring when the alarm is armed must start ETA tracking immediately, without waiting for an OS region-entered event")
    }

    func test_add_doesNotBeginETATracking_whenOutsideWarmupRing() {
        let alarm = makeTimeAlarm(leadTimeMinutes: 5)
        let ringRadius = alarm.outerRingRadius()

        let locationManager = LocationManager()
        locationManager.currentLocation = fix(metersFromDestination: ringRadius * 2, speed: 0)
        sut.locationManager = locationManager

        sut.add(alarm: alarm)
        sut.simulateLocationUpdate(fix(metersFromDestination: 300, speed: 50))

        XCTAssertEqual(sut.alarms.first?.state, .active,
            "Starting outside the outer ring must NOT begin ETA tracking on add() — only an actual region-entered event (or being inside at arm time) should")
    }
}
