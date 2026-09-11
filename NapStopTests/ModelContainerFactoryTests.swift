// Copyright © 2026 Robert Bartis. All rights reserved.

// ModelContainerFactoryTests.swift
// Regression coverage for the 2026-07-25 crash: NapStopApp.init() ->
// swift_unexpectedError from a `try!` when opening the on-disk SwiftData
// store. Root cause was a corrupted local store (most plausibly left behind
// by the device losing power mid-write, e.g. a dead battery) causing the
// force-try to throw on every subsequent launch — a permanent crash loop.
//
// These tests reproduce a corrupted store on disk (a file that exists but
// isn't a valid SwiftData/SQLite store) and assert that
// ModelContainerFactory.recoveringLocalContainer deletes it and opens a
// fresh, working store instead of throwing.

import XCTest
import SwiftData
@testable import GeoNap

@MainActor
final class ModelContainerFactoryTests: XCTestCase {

    private var storeURL: URL!

    override func setUpWithError() throws {
        storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ModelContainerFactoryTests-\(UUID().uuidString).store")
    }

    override func tearDownWithError() throws {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: storeURL.path + suffix))
        }
    }

    // MARK: - Happy path

    func test_recoveringLocalContainer_opensACleanStore() throws {
        let container = try ModelContainerFactory.recoveringLocalContainer(url: storeURL)
        XCTAssertNotNil(container)
    }

    // MARK: - Corruption recovery (the actual crash scenario)

    /// A store file that exists but isn't a valid SQLite/SwiftData store —
    /// simulating corruption from an unclean shutdown — must not throw.
    /// Recovery should delete the bad file and open a fresh store instead
    /// of propagating the original error (which, at the old `try!` call
    /// site in NapStopApp, crashed the app on every launch).
    func test_recoveringLocalContainer_recoversFromCorruptedStore() throws {
        try Data("not a real sqlite store — simulated power-loss corruption".utf8)
            .write(to: storeURL)

        let container = try ModelContainerFactory.recoveringLocalContainer(url: storeURL)

        // The recovered container must actually be usable, not just
        // non-throwing — round-trip an alarm through it.
        let context = ModelContext(container)
        let alarm = NapAlarm(name: "Test", latitude: 40.0, longitude: -74.0)
        context.insert(alarm)
        try context.save()
        XCTAssertEqual(try context.fetch(FetchDescriptor<NapAlarm>()).count, 1)
    }

    /// The `-wal` sidecar is exactly where an interrupted write (device
    /// losing power mid-checkpoint) tends to leave a store in a bad state.
    /// Corrupting only the sidecar, not the main store file, must still
    /// recover cleanly.
    func test_recoveringLocalContainer_recoversFromCorruptedWALSidecar() throws {
        // Create a real, valid store first so the main file is legitimate.
        _ = try ModelContainerFactory.recoveringLocalContainer(url: storeURL)

        // Now corrupt just the -wal sidecar, as an interrupted checkpoint would.
        let walURL = URL(fileURLWithPath: storeURL.path + "-wal")
        try Data("truncated mid-write".utf8).write(to: walURL)

        let container = try ModelContainerFactory.recoveringLocalContainer(url: storeURL)
        let context = ModelContext(container)
        XCTAssertNoThrow(try context.fetch(FetchDescriptor<NapAlarm>()))
    }

    // MARK: - Regression: 2026-09-11 background crash (0xdead10cc / RUNNINGBOARD SIGKILL)
    //
    // Root cause: IntentModelContainer.make() hand-rolled its own
    // `Schema([NapAlarm.self, GTFSFeedModel.self])`, missing
    // AutoNotifyDefaultsRecord.self (added to the real schema below on
    // 2026-07-11). Every time IntentModelContainer opened the SAME on-disk
    // store the main app uses, SwiftData saw a 2-entity schema against a
    // 3-entity on-disk model and treated it as needing a store migration.
    // CalendarScanBackgroundTask.run() triggered this from a background
    // execution context; the migration's WAL checkpoint got stuck on a busy
    // lock long enough that RunningBoard killed the whole process for
    // holding a file lock while suspended. Fix: IntentModelContainer.make()
    // now calls ModelContainerFactory.schema directly instead of keeping a
    // second, driftable copy.
    //
    // IntentModelContainer.make() itself is intentionally NOT called from
    // unit tests (see NapAlarmShortcutsTests.swift's file header — it hits a
    // real on-disk/CloudKit store with no injection seam, and Bob asked to
    // skip adding one). These tests instead cover what the fix actually
    // relies on: that ModelContainerFactory.schema is the one complete,
    // reusable source of truth, and that a store opened with it once can be
    // reopened with it again — by a second, independent ModelContainer
    // instance, exactly like IntentModelContainer.make() does relative to
    // the main app's container — without any migration path being hit.

    /// Guards against ever silently dropping a model type from the shared
    /// schema again (whether here, or by a future call site re-introducing
    /// its own hand-rolled copy instead of reusing this one).
    func test_schema_includesAllPersistedModelTypes() {
        let names = Set(ModelContainerFactory.schema.entities.map(\.name))
        XCTAssertEqual(names, ["NapAlarm", "GTFSFeedModel", "AutoNotifyDefaultsRecord"])
    }

    /// Simulates the main app creating the store first, then a second,
    /// independent ModelContainer (standing in for IntentModelContainer)
    /// opening the SAME on-disk store later with the SAME shared schema —
    /// the scenario that used to hit a schema mismatch and a migration
    /// attempt. Both opens and a full round-trip (including
    /// AutoNotifyDefaultsRecord, the entity that was actually missing) must
    /// succeed with no error.
    func test_reopeningStoreWithSharedSchema_afterInitialCreation_requiresNoMigration() throws {
        let firstOpen = try ModelContainerFactory.recoveringLocalContainer(
            schema: ModelContainerFactory.schema,
            url: storeURL
        )
        let firstContext = ModelContext(firstOpen)
        firstContext.insert(NapAlarm(name: "From main app", latitude: 1, longitude: 1))
        firstContext.insert(AutoNotifyDefaultsRecord(contactsJSON: "[]"))
        try firstContext.save()

        // A second, independent container/context against the same file —
        // mirroring IntentModelContainer.make() opening what the main app
        // already created.
        let secondOpen = try ModelContainerFactory.recoveringLocalContainer(
            schema: ModelContainerFactory.schema,
            url: storeURL
        )
        let secondContext = ModelContext(secondOpen)

        XCTAssertEqual(try secondContext.fetch(FetchDescriptor<NapAlarm>()).count, 1)
        XCTAssertEqual(try secondContext.fetch(FetchDescriptor<AutoNotifyDefaultsRecord>()).count, 1)
    }
}
