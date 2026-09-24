// Copyright © 2026 Robert Bartis. All rights reserved.

// AlarmManagerRemoteChangeDebounceTests.swift
// Coverage for the debounce added to AlarmManager.observeRemoteChanges()
// 2026-09-24. Root cause: NSPersistentStoreRemoteChange fires once per
// incremental CloudKit sync transaction, not batched, so a real sync
// catch-up can deliver a dozen-plus of these within a second or two — and
// every single one used to trigger a full load() + reregisterAllRegions()
// (which stops and restarts EVERY monitored region, even when there are
// zero). Found from debug-log evidence of exactly that: repeated "Stopped
// monitoring all 0 region(s)" lines firing back-to-back with no alarms even
// active, while investigating whether background churn unrelated to any
// alarm could be competing with Calendar Scanning's BGAppRefreshTask for
// iOS's background execution budget (see monetization-tier-pricing /
// calendar-scan-alarms-design project memory for the fuller investigation).
//
// Uses AlarmManager.remoteChangeDebounceIntervalOverride (DEBUG-only test
// seam) to shrink the real 2-second debounce window down to milliseconds,
// and AlarmManager.remoteChangeReloadCount (also DEBUG-only) to observe how
// many times the debounced reload actually ran — the thing that
// distinguishes "coalesced into one" from "still firing per notification."

import XCTest
import SwiftData
@testable import GeoNap

@MainActor
final class AlarmManagerRemoteChangeDebounceTests: XCTestCase {

    var sut: AlarmManager!
    var context: ModelContext!

    /// Short enough to keep the test fast, long enough to reliably outlast
    /// the scheduling jitter of posting several notifications back to back.
    private let testDebounceInterval: Duration = .milliseconds(30)
    /// Comfortably longer than testDebounceInterval so we're not racing it.
    private let settleDelay: Duration = .milliseconds(150)

    override func setUp() {
        super.setUp()
        sut = AlarmManager()
        context = ModelContext(ModelContainerFactory.makeInMemory())
        AlarmManager.remoteChangeDebounceIntervalOverride = testDebounceInterval
        sut.setModelContext(context)   // registers the NSPersistentStoreRemoteChange observer
    }

    override func tearDown() {
        AlarmManager.remoteChangeDebounceIntervalOverride = nil
        sut = nil
        context = nil
        super.tearDown()
    }

    private func postRemoteChange() {
        NotificationCenter.default.post(name: NSNotification.Name.NSPersistentStoreRemoteChange, object: nil)
    }

    func test_singleNotification_reloadsExactlyOnce() async throws {
        postRemoteChange()
        try await Task.sleep(for: settleDelay)
        XCTAssertEqual(sut.remoteChangeReloadCount, 1)
    }

    func test_burstOfNotifications_collapsesToSingleReload() async throws {
        // Simulate a CloudKit sync catch-up delivering many notifications in
        // quick succession — this is exactly the pattern seen in the field.
        for _ in 0..<10 {
            postRemoteChange()
        }
        try await Task.sleep(for: settleDelay)
        XCTAssertEqual(sut.remoteChangeReloadCount, 1, "A burst of notifications should collapse into a single reload, not one per notification.")
    }

    func test_secondBurstAfterFirstSettles_reloadsAgain() async throws {
        // Debouncing shouldn't permanently suppress future reloads — a
        // second, later burst (a genuinely separate sync event) must still
        // produce its own reload.
        postRemoteChange()
        try await Task.sleep(for: settleDelay)
        XCTAssertEqual(sut.remoteChangeReloadCount, 1)

        postRemoteChange()
        postRemoteChange()
        try await Task.sleep(for: settleDelay)
        XCTAssertEqual(sut.remoteChangeReloadCount, 2)
    }

    func test_notificationsSpacedFartherApartThanDebounceInterval_eachReloadsSeparately() async throws {
        // Two notifications spaced well past the debounce window are two
        // separate bursts, not one — each should get its own reload rather
        // than the second silently extending/absorbing the first.
        postRemoteChange()
        try await Task.sleep(for: settleDelay)
        postRemoteChange()
        try await Task.sleep(for: settleDelay)
        XCTAssertEqual(sut.remoteChangeReloadCount, 2)
    }
}
