// Copyright © 2026 Robert Bartis. All rights reserved.

// RunAlarmShortcutTests.swift
// Unit tests for the "Run Shortcut on Alarm" feature (help.body.runShortcut),
// added 2026-07-11. Mirrors AutoSMSFreshnessTests.swift's coverage of
// NotifyContactsIntent almost exactly, since RunAlarmShortcutIntent was
// deliberately built as its sibling — same one-shot read/clear, same no
// staleness cutoff, same never-throws design. See RunAlarmShortcutIntent.swift's
// file header for the full rationale.
//
// NOTE: these require an Xcode build + simulator run to execute — they have not
// been run in this authoring environment.

import XCTest
@testable import GeoNap

// MARK: - isFresh / shouldRun (pure decision logic)

final class RunAlarmShortcutFreshnessTests: XCTestCase {

    func test_firedRecently_isFresh() {
        XCTAssertTrue(
            RunAlarmShortcutIntent.isFresh(firedAt: Date().timeIntervalSince1970 - 60),
            "A shortcut name written 60 s ago must run."
        )
    }

    func test_firedLongAgo_isStillFresh() {
        // No staleness cutoff, matching NotifyContactsIntent — a pending
        // Shortcut name from hours ago must still run on the next app-open
        // rather than being silently dropped.
        XCTAssertTrue(
            RunAlarmShortcutIntent.isFresh(firedAt: Date().timeIntervalSince1970 - (6 * 60 * 60)),
            "A shortcut name from 6 hours ago must still run — there is no time-based cutoff."
        )
    }

    func test_neverFired_isRejected() {
        XCTAssertFalse(
            RunAlarmShortcutIntent.isFresh(firedAt: 0),
            "firedAt == 0 means no alarm with Run Shortcut ever fired — nothing to run. This is the ordinary-app-open case."
        )
    }

    func test_freshNameAndFiredAt_shouldRun() {
        XCTAssertTrue(RunAlarmShortcutIntent.shouldRun(
            shortcutName: "Welcome Home",
            firedAt: Date().timeIntervalSince1970 - 60
        ), "A non-empty name with a real fire time must run.")
    }

    func test_emptyName_doesNotRun_evenIfFired() {
        XCTAssertFalse(RunAlarmShortcutIntent.shouldRun(
            shortcutName: "",
            firedAt: Date().timeIntervalSince1970 - 60
        ), "No name means nothing to run, regardless of fire time — e.g. the alarm that fired had no Run Shortcut configured.")
    }

    func test_neverFiredButNamePresent_doesNotRun() {
        // Guards against a regression where stale leftover content with
        // firedAt == 0 would slip through.
        XCTAssertFalse(RunAlarmShortcutIntent.shouldRun(
            shortcutName: "Welcome Home",
            firedAt: 0
        ))
    }

    func test_firedLongAgoWithName_stillShouldRun() {
        XCTAssertTrue(RunAlarmShortcutIntent.shouldRun(
            shortcutName: "Welcome Home",
            firedAt: Date().timeIntervalSince1970 - (6 * 60 * 60)
        ), "A name from 6 hours ago must still run — there is no time-based cutoff.")
    }

    /// `perform()` reads UserDefaults via hardcoded string literals rather
    /// than `RunShortcutDefaultsKey` directly (same actor-isolation rationale
    /// as NotifyContactsIntent.perform()), so this pins all three in sync.
    func test_defaultsKeyLiterals_matchIntentHardcodedStrings() {
        XCTAssertEqual(RunShortcutDefaultsKey.pendingShortcutName, "runShortcut_pendingName")
        XCTAssertEqual(RunShortcutDefaultsKey.pendingShortcutFiredAt, "runShortcut_pendingFiredAt")
    }
}

// MARK: - AlarmManager.runShortcutIfConfigured queueing behavior

@MainActor
final class RunAlarmShortcutQueueingTests: XCTestCase {

    var sut: AlarmManager!

    override func setUp() {
        super.setUp()
        sut = AlarmManager()
        UserDefaults.standard.removeObject(forKey: RunShortcutDefaultsKey.pendingShortcutName)
        UserDefaults.standard.removeObject(forKey: RunShortcutDefaultsKey.pendingShortcutFiredAt)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: RunShortcutDefaultsKey.pendingShortcutName)
        UserDefaults.standard.removeObject(forKey: RunShortcutDefaultsKey.pendingShortcutFiredAt)
        sut = nil
        super.tearDown()
    }

    private func makeAlarm(runShortcutName: String = "") -> NapAlarm {
        NapAlarm(name: "Amandas", latitude: 36.5073961, longitude: -87.3142547,
                 regionEvent: .onEntry, runShortcutName: runShortcutName)
    }

    func test_alarmWithoutRunShortcut_writesNoPendingName() {
        let alarm = makeAlarm(runShortcutName: "")
        sut.add(alarm: alarm)

        sut.simulateRegionEntered(regionID: alarm.id.uuidString)

        XCTAssertNil(UserDefaults.standard.string(forKey: RunShortcutDefaultsKey.pendingShortcutName),
            "An alarm with no Run Shortcut configured must not write a pending name.")
    }

    func test_alarmWithRunShortcut_writesPendingName() {
        let alarm = makeAlarm(runShortcutName: "Welcome Home")
        sut.add(alarm: alarm)

        sut.simulateRegionEntered(regionID: alarm.id.uuidString)

        XCTAssertEqual(UserDefaults.standard.string(forKey: RunShortcutDefaultsKey.pendingShortcutName), "Welcome Home",
            "An alarm with Run Shortcut configured must queue its exact name.")
    }

    func test_alarmWithRunShortcut_writesRecentFiredAt() {
        let alarm = makeAlarm(runShortcutName: "Welcome Home")
        let before = Date().timeIntervalSince1970

        sut.add(alarm: alarm)
        sut.simulateRegionEntered(regionID: alarm.id.uuidString)

        let after = Date().timeIntervalSince1970
        let ts = UserDefaults.standard.double(forKey: RunShortcutDefaultsKey.pendingShortcutFiredAt)
        XCTAssertGreaterThanOrEqual(ts, before)
        XCTAssertLessThanOrEqual(ts, after)
    }

    func test_whitespaceOnlyName_treatedAsDisabled() {
        // Mirrors AlarmViewModel/TransitAlarmView trimming the field before
        // save — a whitespace-only name should behave the same as empty.
        let alarm = makeAlarm(runShortcutName: "   ")
        sut.add(alarm: alarm)

        sut.simulateRegionEntered(regionID: alarm.id.uuidString)

        XCTAssertNil(UserDefaults.standard.string(forKey: RunShortcutDefaultsKey.pendingShortcutName),
            "A whitespace-only Run Shortcut name must be treated as disabled, same as empty.")
    }

    /// Known limitation, shared with Auto-Notify (see the TODO on
    /// AlarmManager.queueAutoNotify): the pending slot is single, not a
    /// queue, so a second alarm firing before the app is opened overwrites
    /// the first alarm's pending name.
    func test_secondAlarmFiringFirst_overwritesPendingName() {
        let first  = makeAlarm(runShortcutName: "First Scene")
        let second = makeAlarm(runShortcutName: "Second Scene")
        sut.add(alarm: first)
        sut.add(alarm: second)

        sut.simulateRegionEntered(regionID: first.id.uuidString)
        sut.simulateRegionEntered(regionID: second.id.uuidString)

        XCTAssertEqual(UserDefaults.standard.string(forKey: RunShortcutDefaultsKey.pendingShortcutName), "Second Scene",
            "Only the most recently fired alarm's Shortcut name should remain pending — documented in help.body.runShortcut, not yet fixed by a queue.")
    }
}
