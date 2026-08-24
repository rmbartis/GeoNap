// Copyright © 2026 Robert Bartis. All rights reserved.

// AlarmManagerLoadRetryTests.swift
// Coverage for AlarmManager.load()'s retry logic, added 2026-08-24 after a
// user report: alarms disappeared after a phone restart. Root cause traced
// to load()'s context.fetch() silently setting alarms = [] on ANY throw,
// logged only via print/CrashReporter (OSLog — invisible to the in-app
// DebugLogger export used to diagnose field reports). A fetch against a
// freshly-opened CloudKit-mirrored store can plausibly still throw for a
// moment right after a device reboot even once ModelContainer itself opens
// cleanly (see ModelContainerFactory.swift's history, and PurchaseManager
// .swift's equivalent retry logic added the same day for the same class of
// problem in StoreKit).
//
// The real race this targets — CloudKit's remote-import not settled yet
// immediately post-boot — can't be reproduced deterministically in a unit
// test or the Simulator (Bob asked directly: "Can this be tested in
// simulation" — no, Simulator doesn't replicate device boot/Data Protection
// timing). So these tests instead verify the RETRY BEHAVIOR itself via
// AlarmManager.fetchAlarmsOverride, a DEBUG-only test seam: does it retry
// the right number of times, recover if a later attempt succeeds, log every
// attempt to DebugLogger, and — critically — never destroy anything even
// when every attempt fails.

import XCTest
import SwiftData
@testable import GeoNap

// MARK: - DebugLogger test helpers
// Mirrors DebugLoggerTests.swift's private helpers — kept file-local
// (not shared) since Swift extensions can't be re-exported across test
// files without a shared test-support target, and duplicating three small
// one-line helpers is cheaper than introducing one.
private extension DebugLogger {
    func enableForTesting() {
        UserDefaults.standard.set(true, forKey: UserDefaultsKey.debugLoggingEnabled)
    }
    func resetForTesting() {
        UserDefaults.standard.set(false, forKey: UserDefaultsKey.debugLoggingEnabled)
        clearLog()
    }
    func hasEntry(containing substring: String) -> Bool {
        recentEntries.contains { $0.message.contains(substring) }
    }
    func entryCount(containing substring: String) -> Int {
        recentEntries.filter { $0.message.contains(substring) }.count
    }
}

@MainActor
final class AlarmManagerLoadRetryTests: XCTestCase {

    var sut: AlarmManager!
    var context: ModelContext!

    private enum FakeFetchError: Error { case simulatedFailure }

    override func setUp() {
        super.setUp()
        DebugLogger.shared.resetForTesting()
        DebugLogger.shared.enableForTesting()
        sut = AlarmManager()
        context = ModelContext(ModelContainerFactory.makeInMemory())
    }

    override func tearDown() {
        DebugLogger.shared.resetForTesting()
        sut = nil
        context = nil
        super.tearDown()
    }

    // MARK: - The common case: succeeds first try, no retry, no noise in the log

    func test_load_succeedsFirstTry_doesNotRetryOrLog() {
        var callCount = 0
        sut.fetchAlarmsOverride = { _ in
            callCount += 1
            return []
        }
        sut.setModelContext(context)

        XCTAssertEqual(callCount, 1)
        XCTAssertTrue(sut.alarms.isEmpty)
        XCTAssertFalse(DebugLogger.shared.hasEntry(containing: "attempt"), "a clean first-try success should be silent, matching production behavior before this fix")
    }

    // MARK: - The exact scenario this fix targets: transient failures, then recovery

    func test_load_retriesAndRecovers_afterTransientFailures() {
        let expected = [NapAlarm(name: "Recovered", latitude: 1, longitude: 1)]
        var callCount = 0
        sut.fetchAlarmsOverride = { _ in
            callCount += 1
            if callCount < 3 { throw FakeFetchError.simulatedFailure }
            return expected
        }
        sut.setModelContext(context)

        XCTAssertEqual(callCount, 3, "should have retried twice before succeeding on the 3rd attempt")
        XCTAssertEqual(sut.alarms.map(\.id), expected.map(\.id))
        XCTAssertEqual(DebugLogger.shared.entryCount(containing: "fetch attempt"), 2, "exactly the 2 failed attempts should be logged")
        XCTAssertTrue(DebugLogger.shared.hasEntry(containing: "succeeded on attempt 3/3"))
    }

    // MARK: - Every attempt fails: gives up gracefully, logs it, never crashes

    func test_load_allAttemptsFail_endsEmptyAndLogsGivingUp() {
        sut.fetchAlarmsOverride = { _ in throw FakeFetchError.simulatedFailure }
        sut.setModelContext(context)

        XCTAssertTrue(sut.alarms.isEmpty)
        XCTAssertEqual(DebugLogger.shared.entryCount(containing: "fetch attempt"), 3, "all 3 attempts should be logged")
        XCTAssertTrue(DebugLogger.shared.hasEntry(containing: "all 3"))
        XCTAssertTrue(
            DebugLogger.shared.hasEntry(containing: "was NOT deleted"),
            "the log must make clear a failed fetch never deletes existing data — it only fails to display it"
        )
    }

    // MARK: - A later, real load (e.g. triggered by a remote-change notification) recovers normally

    func test_load_calledAgainLater_recoversOnceOverrideIsCleared() {
        sut.fetchAlarmsOverride = { _ in throw FakeFetchError.simulatedFailure }
        sut.setModelContext(context)
        XCTAssertTrue(sut.alarms.isEmpty)

        sut.fetchAlarmsOverride = nil
        let alarm = NapAlarm(name: "Real Fetch", latitude: 2, longitude: 2)
        context.insert(alarm)
        try? context.save()

        sut.setModelContext(context)   // re-invoking is what observeRemoteChanges() does internally
        XCTAssertEqual(sut.alarms.count, 1)
        XCTAssertEqual(sut.alarms.first?.name, "Real Fetch")
    }
}
