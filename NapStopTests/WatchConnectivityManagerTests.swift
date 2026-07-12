// Copyright © 2026 Robert Bartis. All rights reserved.

// WatchConnectivityManagerTests.swift
// CI tests verifying the 2026-07-11 DebugLogger integration:
//   1. Watch sync activity (context updates, skips, failures) is routed
//      through DebugLogger under the "Watch" category — not print() — so a
//      user-submitted debug log actually shows what happened Watch-side.
//   2. Pairing status changes are logged individually via
//      logPairingChangeIfNeeded() (the method the WCSessionDelegate
//      callbacks — notably sessionWatchStateDidChange — hop to on the
//      MainActor), not just once in DebugLogger's session header.
//
// WCSession pairing state can't be manipulated directly in a unit test (no
// real or simulated Watch pairing available in CI), so these tests exercise
// the logging *plumbing*: a change in observed pairing description produces
// exactly one log entry, and a repeat observation with no change produces
// none. logPairingChangeIfNeeded() is called directly rather than through
// the nonisolated delegate methods, since those hop to MainActor via
// `Task { @MainActor in ... }` — inherently async and not something a
// synchronous test can await deterministically. See that method's doc
// comment in WatchConnectivityManager.swift.

import XCTest
@testable import GeoNap

private extension DebugLogger {
    func enableForTesting() {
        UserDefaults.standard.set(true, forKey: UserDefaultsKey.debugLoggingEnabled)
    }
    func resetForTesting() {
        UserDefaults.standard.set(false, forKey: UserDefaultsKey.debugLoggingEnabled)
        clearLog()
    }
    func hasEntry(containing substring: String) -> Bool {
        recentEntries.contains { $0.message.contains(substring) || $0.category.contains(substring) }
    }
}

@MainActor
final class WatchConnectivityManagerTests: XCTestCase {

    private let logger = DebugLogger.shared
    private let sut = WatchConnectivityManager.shared

    override func setUp() {
        super.setUp()
        logger.resetForTesting()
        logger.enableForTesting()
        sut.resetPairingStateForTesting()
    }

    override func tearDown() {
        logger.resetForTesting()
        sut.resetPairingStateForTesting()
        super.tearDown()
    }

    // MARK: - Pairing status description

    func test_pairingStatusDescription_isNonEmpty() {
        XCTAssertFalse(sut.pairingStatusDescription.isEmpty)
    }

    // MARK: - Sync activity routed through DebugLogger

    func test_updateWatch_logsUnderWatchCategory() {
        // In the CI simulator there is never an activated WCSession (no
        // paired Watch), so updateWatch(with:) always takes the "skipped"
        // path — exactly the path that must log rather than silently no-op.
        sut.updateWatch(with: [])
        let entry = logger.recentEntries.last { $0.category == "Watch" }
        XCTAssertNotNil(entry, "updateWatch must log an entry under the Watch category. entries: \(logger.recentEntries.map(\.message))")
    }

    func test_updateWatch_doesNotCrash_whenLoggerDisabled() {
        logger.resetForTesting() // disables logging
        XCTAssertNoThrow(sut.updateWatch(with: []))
    }

    // MARK: - Pairing state change logging

    func test_logPairingChangeIfNeeded_logsOnFirstObservation() {
        sut.logPairingChangeIfNeeded()
        XCTAssertTrue(logger.hasEntry(containing: "Watch pairing status changed"),
                      "First pairing observation must log a change. entries: \(logger.recentEntries.map(\.message))")
    }

    func test_logPairingChangeIfNeeded_doesNotDuplicateLog_whenUnchanged() {
        sut.logPairingChangeIfNeeded()   // first observation — logs
        logger.clearLog()
        sut.logPairingChangeIfNeeded()   // same state again — must NOT log
        XCTAssertFalse(logger.hasEntry(containing: "Watch pairing status changed"),
                       "Repeat observation with no actual change must not log again.")
    }

    // MARK: - Session header includes pairing snapshot

    func test_sessionHeader_includesWatchPairingLine() throws {
        logger.resetForTesting()
        logger.isEnabled = true // real setter — exercises writeSessionHeader()
        let logContents = try String(contentsOf: logger.logFileURL, encoding: .utf8)
        XCTAssertTrue(logContents.contains("Watch:"),
                      "Session header must include a Watch pairing status line.")
    }
}
