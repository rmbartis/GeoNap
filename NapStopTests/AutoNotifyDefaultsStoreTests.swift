// Copyright © 2026 Robert Bartis. All rights reserved.

// AutoNotifyDefaultsStoreTests.swift
// Covers the CloudKit-synced Auto-Notify Defaults store added 2026-07-11 to
// close a cross-device-sync gap (see AutoNotifyDefaultsStore.swift /
// AutoNotifyDefaultsRecord.swift, and the monetization-tier-pricing memory).
// Uses a real in-memory SwiftData ModelContainer/ModelContext rather than
// mocking — AutoNotifyDefaultsStore's whole job is the SwiftData round-trip
// and upsert behavior, so that's what needs exercising, not a stand-in.
//
// NOTE: like the rest of this suite, requires an Xcode build to execute —
// not run in this authoring environment.

import XCTest
import SwiftData
@testable import GeoNap

@MainActor
final class AutoNotifyDefaultsStoreTests: XCTestCase {

    private var context: ModelContext!

    override func setUp() {
        super.setUp()
        let schema = Schema([AutoNotifyDefaultsRecord.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [config])
        context = ModelContext(container)
        // No legacy UserDefaults data in the common case — migration tests
        // below seed and clean this up explicitly.
        UserDefaults.standard.removeObject(forKey: AppStorageKey.defaultNotifyContacts)
        AutoNotifyDefaultsStore.configure(context)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: AppStorageKey.defaultNotifyContacts)
        context = nil
        super.tearDown()
    }

    // MARK: - Basic round-trip

    func test_load_withNothingSaved_returnsEmpty() {
        XCTAssertEqual(AutoNotifyDefaultsStore.load(), [])
    }

    func test_save_thenLoad_roundTrips() {
        let contacts = [
            NotifyContact(name: "Mom", value: "+15551234567"),
            NotifyContact(name: "Work", value: "assistant@example.com"),
        ]
        AutoNotifyDefaultsStore.save(contacts)
        XCTAssertEqual(AutoNotifyDefaultsStore.load(), contacts)
    }

    // MARK: - Upsert, not duplicate

    func test_save_calledTwice_upsertsSingleRecord() throws {
        AutoNotifyDefaultsStore.save([NotifyContact(name: "First", value: "+15550000000")])
        AutoNotifyDefaultsStore.save([NotifyContact(name: "Second", value: "+15551111111")])

        XCTAssertEqual(AutoNotifyDefaultsStore.load().map(\.name), ["Second"])

        let allRecords = try context.fetch(FetchDescriptor<AutoNotifyDefaultsRecord>())
        XCTAssertEqual(allRecords.count, 1, "save() must upsert the single shared row, never create a second one")
    }

    func test_save_emptyArray_clearsContacts() {
        AutoNotifyDefaultsStore.save([NotifyContact(name: "Temp", value: "+15552222222")])
        AutoNotifyDefaultsStore.save([])
        XCTAssertEqual(AutoNotifyDefaultsStore.load(), [])
    }

    // MARK: - Migration from the old UserDefaults-backed storage

    func test_migration_movesLegacyUserDefaultsContactsIntoStore() throws {
        // Simulate a device that configured Auto-Notify Defaults before this
        // migration shipped: legacy JSON sitting in UserDefaults, nothing in
        // the new store yet.
        let legacy = [NotifyContact(name: "Legacy Contact", value: "+15553334444")]
        UserDefaults.standard.set(legacy.toJSON(), forKey: AppStorageKey.defaultNotifyContacts)

        // Fresh container/context, as if the app just launched on this device
        // for the first time after the update.
        let schema = Schema([AutoNotifyDefaultsRecord.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let freshContainer = try ModelContainer(for: schema, configurations: [config])
        let freshContext = ModelContext(freshContainer)

        AutoNotifyDefaultsStore.configure(freshContext)

        XCTAssertEqual(AutoNotifyDefaultsStore.load(), legacy, "Migration must move the legacy list into the new store")
        XCTAssertNil(UserDefaults.standard.string(forKey: AppStorageKey.defaultNotifyContacts), "Legacy key must be cleared once migrated")
    }

    func test_migration_doesNotOverwriteExistingRecord() throws {
        // A record already exists on this device (either a prior migration
        // or a deliberately-saved list) — stale UserDefaults data must never
        // clobber it, even if UserDefaults still has something in it.
        let current = [NotifyContact(name: "Current", value: "+15555556666")]
        AutoNotifyDefaultsStore.save(current)

        UserDefaults.standard.set(
            [NotifyContact(name: "Stale", value: "+15559998888")].toJSON(),
            forKey: AppStorageKey.defaultNotifyContacts
        )

        // Re-configure against the SAME context, as if the app relaunched.
        AutoNotifyDefaultsStore.configure(context)

        XCTAssertEqual(AutoNotifyDefaultsStore.load(), current, "An existing record must never be overwritten by re-running migration")
    }

    func test_migration_ignoresEmptyLegacyList() throws {
        UserDefaults.standard.set("[]", forKey: AppStorageKey.defaultNotifyContacts)

        let schema = Schema([AutoNotifyDefaultsRecord.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let freshContainer = try ModelContainer(for: schema, configurations: [config])
        let freshContext = ModelContext(freshContainer)

        AutoNotifyDefaultsStore.configure(freshContext)

        XCTAssertEqual(AutoNotifyDefaultsStore.load(), [], "An empty legacy list shouldn't create a pointless migrated record")
    }
}
