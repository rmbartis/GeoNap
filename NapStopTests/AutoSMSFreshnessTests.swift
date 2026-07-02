// AutoSMSFreshnessTests.swift
// Unit tests for the Auto-SMS redesign and the time-based-alarm warm-up ring.
//
// Added by the CI-coverage review (scheduled task, 2026-06-29). These cover two
// recently-changed paths that previously had NO direct test:
//   1. NotifyContactsIntent's freshness guard — the rule that makes the
//      "When GeoNap Is Opened" Shortcuts automation safe (a body older than the
//      freshness window, or no fired alarm at all, must NOT be sent).
//   2. The outer "warm-up" ring of a time-based alarm must START ETA tracking
//      but must NEVER fire the alarm by itself.
//
// NOTE: these require an Xcode build + simulator run to execute — they have not
// been run in this authoring environment.

import XCTest
import CoreLocation
@testable import GeoNap

// MARK: - Auto-SMS freshness guard

final class NotifyContactsFreshnessTests: XCTestCase {

    private let window: TimeInterval = 15 * 60   // keep in sync with AutoNotifyDefaultsKey.freshnessWindow

    func test_freshBody_isSent() {
        let now = Date().timeIntervalSince1970
        XCTAssertTrue(
            NotifyContactsIntent.isFresh(firedAt: now - 60, now: now, window: window),
            "A body written 60 s ago is well within the 15-minute window and must be sent."
        )
    }

    func test_staleBody_isRejected() {
        let now = Date().timeIntervalSince1970
        XCTAssertFalse(
            NotifyContactsIntent.isFresh(firedAt: now - (window + 1), now: now, window: window),
            "A body older than the freshness window must NOT be sent — this is what stops a casual app-open from re-sending an old message."
        )
    }

    func test_neverFired_isRejected() {
        let now = Date().timeIntervalSince1970
        XCTAssertFalse(
            NotifyContactsIntent.isFresh(firedAt: 0, now: now, window: window),
            "firedAt == 0 means no alarm ever fired — nothing to send."
        )
    }

    func test_exactlyAtWindowBoundary_isStillFresh() {
        let now = Date().timeIntervalSince1970
        XCTAssertTrue(
            NotifyContactsIntent.isFresh(firedAt: now - window, now: now, window: window),
            "Age == window is inclusive (<=), matching the original perform() guard."
        )
    }

    /// The matching constant on the model side must stay in sync with the literal
    /// the intent uses, so the freshness window is one value, not two drifting ones.
    func test_freshnessWindowConstant_matchesIntentLiteral() {
        XCTAssertEqual(AutoNotifyDefaultsKey.freshnessWindow, window,
                       "AutoNotifyDefaultsKey.freshnessWindow must equal the 15-minute literal NotifyContactsIntent.perform() uses.")
    }
}

// MARK: - Time-based warm-up ring (must not self-fire)

@MainActor
final class TimeBasedWarmupRingTests: XCTestCase {

    var sut: AlarmManager!

    override func setUp() {
        super.setUp()
        sut = AlarmManager()
    }

    override func tearDown() {
        sut = nil
        super.tearDown()
    }

    private func makeTimeAlarm() -> NapAlarm {
        NapAlarm(name: "Penn Station",
                 latitude: 40.7506, longitude: -73.9971,
                 triggerMode: .time, leadTimeMinutes: 5,
                 regionEvent: .onEntry)
    }

    func test_enteringWarmupRing_doesNotFireAlarm() {
        let alarm = makeTimeAlarm()
        sut.add(alarm: alarm)

        // Entering the OUTER warm-up ring should begin ETA tracking, never fire.
        sut.simulateRegionEntered(regionID: alarm.id.uuidString + NapAlarm.warmupRegionSuffix)

        XCTAssertEqual(sut.alarms.first?.state, .active,
                       "The warm-up ring must only start ETA tracking — it must not move the alarm to .triggered.")
        XCTAssertEqual(sut.alarms.first?.triggerCount, 0,
                       "Entering the warm-up ring must not increment triggerCount.")
    }

    func test_warmupRingSuffix_isDistinctFromInnerRegionID() {
        let alarm = makeTimeAlarm()
        XCTAssertEqual(alarm.outerWarmupRegion.identifier,
                       alarm.id.uuidString + NapAlarm.warmupRegionSuffix)
        XCTAssertEqual(alarm.clRegion.identifier, alarm.id.uuidString,
                       "Inner proximity ring keeps the bare UUID so the two rings are distinguishable.")
        XCTAssertTrue(alarm.outerWarmupRegion.notifyOnEntry)
        XCTAssertFalse(alarm.outerWarmupRegion.notifyOnExit,
                       "The warm-up ring is entry-only; exit is meaningless for it.")
    }
}
