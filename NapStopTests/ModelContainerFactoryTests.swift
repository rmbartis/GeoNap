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
}
