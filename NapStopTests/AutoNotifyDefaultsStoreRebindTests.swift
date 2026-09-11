// Copyright © 2026 Robert Bartis. All rights reserved.

// AutoNotifyDefaultsStoreRebindTests.swift
// Coverage for AutoNotifyDefaultsStore.configure()'s re-bind behavior, added
// 2026-09-11 after a crash report (EXC_BREAKPOINT, ModelContext.container
// .getter force-unwrap inside fetchRecord(in:)) traced to a real device.
//
// Root cause: AutoNotifyDefaultsStore.configure() was only ever called once,
// from NapStopApp's performLaunchSetupIfNeeded(), against the placeholder
// ModelContainer created at launch (see ModelContainerFactory.swift).
// NapStopApp.resolveCloudKitContainerIfNeeded() later swaps `container` to
// the real CloudKit-backed container and re-binds alarmManager via
// setModelContext(resolved.mainContext) — but was NOT re-binding
// AutoNotifyDefaultsStore the same way. Once the placeholder container had
// nothing else retaining it, it was free to deallocate, and the NEXT
// load()/save() call crashed trying to fetch/save against a ModelContext
// whose owning container no longer existed — not a catchable Swift error
// (the `try?` inside fetchRecord(in:) doesn't protect against this; it's a
// fatal trap inside SwiftData itself), so it reliably crashed the app.
//
// This can't be reproduced end-to-end in a unit test without a real
// ModelContainer deallocation race (same category of un-reproducible-in-CI
// issue as AlarmManagerLoadRetryTests.swift's target bug). Instead, these
// tests verify the RE-BIND CONTRACT itself: calling configure() a second
// time with a new context must fully redirect load()/save() to that new
// context — proving the fix NapStopApp.swift now applies (calling
// configure() again in resolveCloudKitContainerIfNeeded(), mirroring
// alarmManager.setModelContext()) is exercised and won't silently regress.

import XCTest
import SwiftData
@testable import GeoNap

@MainActor
final class AutoNotifyDefaultsStoreRebindTests: XCTestCase {

    var contextA: ModelContext!
    var contextB: ModelContext!

    override func setUp() {
        super.setUp()
        contextA = ModelContext(ModelContainerFactory.makeInMemory())
        contextB = ModelContext(ModelContainerFactory.makeInMemory())
    }

    override func tearDown() {
        contextA = nil
        contextB = nil
        super.tearDown()
    }

    // MARK: - The common case: configure once, load/save round-trips normally

    func test_configureThenSaveThenLoad_roundTripsOnSameContext() {
        AutoNotifyDefaultsStore.configure(contextA)
        let contacts = [NotifyContact(name: "Mom", value: "555-1234")]

        contacts.saveAsGlobalDefaults()
        let loaded = [NotifyContact].loadGlobalDefaults()

        XCTAssertEqual(loaded, contacts)
    }

    // MARK: - The exact scenario this fix targets: re-configure after a container swap

    func test_reconfigureWithNewContext_redirectsLoadAndSaveToNewContext() {
        // Simulates the placeholder container (contextA) being used at
        // launch, then NapStopApp.resolveCloudKitContainerIfNeeded()
        // swapping in the resolved container (contextB) and re-binding —
        // exactly what the NapStopApp.swift fix now does.
        AutoNotifyDefaultsStore.configure(contextA)
        let oldContacts = [NotifyContact(name: "Old Container Contact", value: "555-0000")]
        oldContacts.saveAsGlobalDefaults()
        XCTAssertEqual([NotifyContact].loadGlobalDefaults(), oldContacts)

        AutoNotifyDefaultsStore.configure(contextB)

        // Must read as empty from the fresh context, NOT crash, and NOT
        // still reflect contextA's data — proving load() is actually
        // operating against contextB now, not a stale reference to contextA.
        XCTAssertEqual([NotifyContact].loadGlobalDefaults(), [])

        let newContacts = [NotifyContact(name: "New Container Contact", value: "555-9999")]
        newContacts.saveAsGlobalDefaults()

        XCTAssertEqual([NotifyContact].loadGlobalDefaults(), newContacts, "save() after re-configure must write to the new context")

        // contextA must be untouched by the post-swap save — confirms the
        // two contexts were never conflated.
        let stillInOldContext = try? contextA.fetch(FetchDescriptor<AutoNotifyDefaultsRecord>())
        XCTAssertEqual(stillInOldContext?.first?.contactsJSON, oldContacts.toJSON())
    }

    // MARK: - Repeated re-configure (e.g. multiple language-change view rebuilds)

    func test_repeatedReconfigureWithSameContext_isSafeAndIdempotent() {
        AutoNotifyDefaultsStore.configure(contextA)
        let contacts = [NotifyContact(name: "Stable", value: "555-4242")]
        contacts.saveAsGlobalDefaults()

        // RootView's `.id(languageManager.currentLanguage)` can re-run
        // performLaunchSetupIfNeeded-adjacent setup multiple times across a
        // session; configure() must tolerate being called repeatedly with
        // an already-current context without duplicating or losing data.
        AutoNotifyDefaultsStore.configure(contextA)
        AutoNotifyDefaultsStore.configure(contextA)

        XCTAssertEqual([NotifyContact].loadGlobalDefaults(), contacts)
    }
}
