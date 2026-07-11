// Copyright © 2026 Robert Bartis. All rights reserved.

// AutoSMSFreshnessTests.swift
// Unit tests for the Auto-SMS redesign and the time-based-alarm warm-up ring.
//
// Added by the CI-coverage review (scheduled task, 2026-06-29). These cover two
// recently-changed paths that previously had NO direct test:
//   1. NotifyContactsIntent's freshness guard — the rule that makes the
//      "When GeoNap Is Opened" Shortcuts automation safe (nothing sends unless
//      an alarm has actually fired).
//   2. The outer "warm-up" ring of a time-based alarm must START ETA tracking
//      but must NEVER fire the alarm by itself.
//
// UPDATED 2026-07-11: the original 15-minute staleness cutoff (`isFresh(firedAt:
// now:window:)`) was removed after a real device log showed it silently
// dropping legitimate sends — a rider getting off a bus/train and gathering
// belongings routinely took longer than 15 minutes to next open the app. Since
// `perform()` already reads-then-clears the pending keys unconditionally,
// dropping the cutoff introduces no duplicate-send risk. `isFresh` now only
// asks "has an alarm fired at all" (`firedAt > 0`). See
// docs/ — or [[autosms-freshness-window-too-tight]] in project memory — for
// the investigation.
//
// NOTE: these require an Xcode build + simulator run to execute — they have not
// been run in this authoring environment.

import XCTest
import CoreLocation
@testable import GeoNap

// MARK: - Auto-SMS freshness guard

final class NotifyContactsFreshnessTests: XCTestCase {

    func test_firedRecently_isFresh() {
        let now = Date().timeIntervalSince1970
        XCTAssertTrue(
            NotifyContactsIntent.isFresh(firedAt: now - 60),
            "A body written 60 s ago must be sent."
        )
    }

    func test_firedLongAgo_isStillFresh() {
        // No staleness cutoff as of 2026-07-11 — a pending body from hours ago
        // must still be sent on the next app-open rather than silently dropped.
        let now = Date().timeIntervalSince1970
        XCTAssertTrue(
            NotifyContactsIntent.isFresh(firedAt: now - (6 * 60 * 60)),
            "A body from 6 hours ago must still be sent — there is no time-based cutoff anymore."
        )
    }

    func test_neverFired_isRejected() {
        XCTAssertFalse(
            NotifyContactsIntent.isFresh(firedAt: 0),
            "firedAt == 0 means no alarm ever fired — nothing to send. This is the ordinary-app-open case."
        )
    }

    /// `perform()` reads UserDefaults via hardcoded string literals rather than
    /// `AutoNotifyDefaultsKey` directly (see the comment in `perform()` — done
    /// to avoid actor-isolation inference), which means the enum's key strings
    /// and the intent's literals can silently drift apart. This pins all three.
    func test_defaultsKeyLiterals_matchIntentHardcodedStrings() {
        XCTAssertEqual(AutoNotifyDefaultsKey.pendingBody, "autoNotify_pendingBody")
        XCTAssertEqual(AutoNotifyDefaultsKey.pendingPhones, "autoNotify_pendingPhones")
        XCTAssertEqual(AutoNotifyDefaultsKey.pendingBodyTimestamp, "autoNotify_pendingBodyTimestamp")
    }
}

// MARK: - Auto-SMS shouldNotify (no-throw redesign, 2026-07-09)

/// `NotifyContactsIntent.perform()` used to `throw` when there was nothing
/// fresh to send. Combined with the "App is Opened" trigger (the only one iOS
/// offers — see the intent's file header), that meant a thrown error, and the
/// resulting system "Automation Failed" banner, on nearly every ordinary
/// app-open. The fix: `perform()` now always returns a result — either the
/// real body/recipients or an empty sentinel — and the Shortcut itself gates
/// Send Message behind an "If Body is not empty" check. `shouldNotify` is the
/// pure decision behind that empty-vs-real branch; these tests are what would
/// have caught the original bug before it shipped.
final class NotifyContactsShouldNotifyTests: XCTestCase {

    func test_freshBodyAndPhones_shouldNotify() {
        let now = Date().timeIntervalSince1970
        XCTAssertTrue(NotifyContactsIntent.shouldNotify(
            body: "[Arrival] I arrived at Grand Central at 9:14 AM.",
            phones: ["+15551234567"],
            firedAt: now - 60
        ), "Fresh body with at least one phone must notify.")
    }

    func test_emptyBody_doesNotNotify_evenIfFiredWithPhones() {
        let now = Date().timeIntervalSince1970
        XCTAssertFalse(NotifyContactsIntent.shouldNotify(
            body: "", phones: ["+15551234567"],
            firedAt: now - 60
        ), "No body means nothing to send, regardless of recipients.")
    }

    func test_emptyPhones_doesNotNotify_evenIfFiredWithBody() {
        // e.g. the alarm that fired had only email contacts, or none at all —
        // this is exactly the guard that stops Send Message from trying to
        // text an empty recipient list.
        let now = Date().timeIntervalSince1970
        XCTAssertFalse(NotifyContactsIntent.shouldNotify(
            body: "[Arrival] I arrived at Grand Central at 9:14 AM.", phones: [],
            firedAt: now - 60
        ), "No phone recipients means nothing for Send Message to address.")
    }

    func test_firedLongAgoWithBodyAndPhones_stillShouldNotify() {
        // No staleness cutoff as of 2026-07-11 (see file header) — a pending
        // body from hours ago must still notify rather than being silently
        // dropped, since perform() clears it unconditionally either way.
        let now = Date().timeIntervalSince1970
        XCTAssertTrue(NotifyContactsIntent.shouldNotify(
            body: "[Arrival] I arrived at Grand Central at 9:14 AM.",
            phones: ["+15551234567"],
            firedAt: now - (6 * 60 * 60)
        ), "A body from 6 hours ago must still notify — there is no time-based cutoff anymore.")
    }

    func test_neverFired_doesNotNotify() {
        // firedAt == 0: no alarm has ever fired. This is the MOST common case
        // — the one that used to throw on every single app-open.
        XCTAssertFalse(NotifyContactsIntent.shouldNotify(
            body: "", phones: [],
            firedAt: 0
        ), "Never-fired, empty body/phones must not notify — the ordinary app-open path.")
    }

    func test_neverFiredButBodyAndPhonesPresent_doesNotNotify() {
        // Guards against a regression where stale leftover content with
        // firedAt == 0 would slip through.
        XCTAssertFalse(NotifyContactsIntent.shouldNotify(
            body: "[Arrival] I arrived at Grand Central at 9:14 AM.",
            phones: ["+15551234567"],
            firedAt: 0
        ))
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
