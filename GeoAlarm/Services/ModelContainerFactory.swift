// Copyright © 2026 Robert Bartis. All rights reserved.

// ModelContainerFactory.swift
// Shared SwiftData ModelContainer construction for both the main app
// (NapStopApp.swift's `container` property) and the out-of-process App
// Intents (IntentModelContainer.swift) — both open the same on-disk store
// (CloudKit-backed with a local-only fallback; neither passes a custom
// `url:`, so SwiftData resolves both to the same default store location).
//
// Root cause of the 2026-07-25 crash (GeoNap.NapStopApp.init() ->
// swift_unexpectedError, "closure #1 in variable initialization expression
// of NapStopApp.container"): that store can end up corrupted if the device
// loses power mid-write — most commonly a dead battery cutting power while
// SwiftData/SQLite is mid-checkpoint on its WAL file. NapStopApp's local
// fallback used `try!`, so once the on-disk store was corrupted, EVERY
// subsequent launch threw the same error and force-crashed at init — a
// permanent boot loop with no way for the user to recover short of
// deleting and reinstalling the app.
//
// `recoveringLocalContainer` centralizes the fix: if opening the local
// store throws, delete the store's files and retry once against a fresh
// store, rather than propagating (or force-crashing on) the original
// error. Both call sites benefit, and a corrupted store gets self-healed by
// whichever of the two happens to run first after the crash (main app
// foreground launch, or a background Shortcut/widget/calendar-scan intent).
import Foundation
import SwiftData

enum ModelContainerFactory {

    /// The schema used by the main app's store.
    ///
    /// Marked `nonisolated`: it's referenced from the default parameter
    /// values below (`schema: Schema = schema`), which evaluate in a
    /// nonisolated context even though the functions themselves are
    /// `@MainActor`. Without this, the project's default main-actor
    /// isolation flags that as a cross-isolation access. `Schema` conforms
    /// to `Sendable`, so plain `nonisolated` — not `nonisolated(unsafe)` —
    /// is all that's needed here.
    nonisolated static let schema = Schema([NapAlarm.self, GTFSFeedModel.self, AutoNotifyDefaultsRecord.self])

    /// An isolated in-memory container — used for `--uitesting` launches so
    /// every run starts with zero alarms, deterministically, with no
    /// dependency on CloudKit/disk state.
    @MainActor
    static func makeInMemory(schema: Schema = schema) -> ModelContainer {
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try! ModelContainer(for: schema, configurations: [config])
    }

    /// Opens the on-disk (non-CloudKit) store. If that throws — almost
    /// always a corrupted SQLite/WAL file left behind by an unclean
    /// shutdown — deletes the store's files and retries ONCE against a
    /// fresh store.
    ///
    /// Still throws if the retry also fails (e.g. genuinely out of disk
    /// space), so a caller that needs a hard launch guarantee (NapStopApp)
    /// must supply its own last-resort fallback; a caller that's fine
    /// surfacing a one-off failure (an App Intent) can just propagate it.
    ///
    /// `url` defaults to SwiftData's standard on-disk location; tests pass
    /// an explicit temp-file URL so they never touch the real app's store.
    @MainActor
    static func recoveringLocalContainer(schema: Schema = schema, url: URL? = nil) throws -> ModelContainer {
        let localConfig = url.map { ModelConfiguration(schema: schema, url: $0) }
            ?? ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [localConfig])
        } catch {
            CrashReporter.record(error, context: "ModelContainer(local) failed to open — deleting store and retrying once")
            destroyStore(at: localConfig.url)
            return try ModelContainer(for: schema, configurations: [localConfig])
        }
    }

    /// Deletes the SQLite store file and its `-wal`/`-shm` sidecars at
    /// `url`, if present. No-op (not an error) for any file that doesn't exist.
    private static func destroyStore(at url: URL) {
        let fm = FileManager.default
        for suffix in ["", "-wal", "-shm"] {
            try? fm.removeItem(at: URL(fileURLWithPath: url.path + suffix))
        }
    }
}
