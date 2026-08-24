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
import CloudKit

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

    /// Opens the CloudKit-backed store, recovering the on-disk local file
    /// first if it's corrupted. Both call sites (NapStopApp, IntentModelContainer)
    /// used to just fall from a failed CloudKit attempt straight to
    /// `recoveringLocalContainer` and stop there — which works, but silently
    /// strands the caller on a local-only store even when the failure was
    /// local file corruption (not a CloudKit/iCloud problem), because
    /// `recoveringLocalContainer` deletes-and-recreates the file WITHOUT
    /// CloudKit.
    ///
    /// SECOND finding, 2026-08-24: a build-64 fix that only added the
    /// resync-after-recovery retry below wasn't enough — a user reproduced
    /// total loss of brand-new alarms after a single clean, deliberate
    /// power-off/power-on cycle (30s), which doesn't fit "abrupt power loss
    /// corrupted the WAL file" (a clean shutdown lets iOS flush writes
    /// normally). The far more likely trigger: CloudKit/network/iCloud
    /// account state genuinely isn't ready yet in the first moment or two
    /// after a phone reboots, so the FIRST `ModelContainer(...cloudConfig)`
    /// attempt below throws for a completely ordinary, transient reason —
    /// and the old code treated ANY failure there as proof of corruption,
    /// immediately falling to `recoveringLocalContainer`, which can itself
    /// throw trying to reopen a CloudKit-formatted file with a plain local
    /// config and DESTROY it — deleting alarms that were created only
    /// seconds earlier and likely hadn't finished uploading to iCloud yet,
    /// so the resync-after-recovery retry found nothing to redownload.
    ///
    /// THIRD finding, 2026-08-24, same investigation: the recovery fallback
    /// itself had a bug independent of timing. It called
    /// `recoveringLocalContainer`, which opens the store's file with a
    /// *plain, non-CloudKit* `ModelConfiguration`. But that on-disk file was
    /// originally created WITH `cloudKitDatabase: .automatic` — CloudKit
    /// mirroring bakes CloudKit-specific metadata into the store. Opening a
    /// CloudKit-formatted file with a mismatched plain-local config is
    /// itself liable to throw immediately, on a file that was never actually
    /// corrupted — which `recoveringLocalContainer` would then interpret as
    /// "corrupted," delete, and rebuild as a plain local file, permanently
    /// losing whatever hadn't finished syncing to iCloud yet. So a failure
    /// reason as ordinary as "iCloud not ready yet post-boot" could reach
    /// the destructive path twice over: once by exhausting the retries
    /// below, and again by the recovery step's own config mismatch making a
    /// perfectly fine file look broken.
    ///
    /// Fix, this pass: retry the CloudKit attempt a few times with a short
    /// delay (covers "not ready yet right after boot"), and if recovery is
    /// still needed, ALWAYS recover using the same CloudKit-mirrored config
    /// the file was actually created with — never the mismatched plain
    /// config — so a rebuilt store can resync from iCloud instead of being
    /// silently downgraded to local-only by a config that could never have
    /// opened that file correctly in the first place. `recoveringLocalContainer`
    /// (plain config) is now used only as the final, last-resort fallback if
    /// even a freshly rebuilt CloudKit-formatted store won't open — e.g. no
    /// CloudKit entitlement/account at all on this device.
    ///
    /// Also logs the actual thrown error at each step, alongside a
    /// best-effort snapshot of `CKAccountStatus` (available / no account /
    /// restricted / temporarily unavailable / could not determine) — a
    /// direct, cheap way to see whether iCloud itself was reachable at the
    /// moment of failure, without touching the SwiftData store at all.
    /// Logs go to both OSLog (via CrashReporter, for Console.app) and the
    /// in-app DebugLogger (Settings → Debug Log), so a repeat of this can be
    /// diagnosed from real evidence rather than guessed at again.
    @MainActor
    static func openCloudKitContainerRecoveringIfNeeded(schema: Schema = schema) throws -> ModelContainer {
        let cloudConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false, cloudKitDatabase: .automatic)

        let maxAttempts = 4
        for attempt in 1...maxAttempts {
            do {
                let c = try ModelContainer(for: schema, configurations: [cloudConfig])
                if attempt > 1 {
                    logBoth("ModelContainer: CloudKit store opened on attempt \(attempt)/\(maxAttempts) (earlier attempt(s) likely hit iCloud/network not ready yet post-launch)")
                }
                return c
            } catch {
                let status = currentAccountStatusSync()
                logBoth("ModelContainer: CloudKit open attempt \(attempt)/\(maxAttempts) failed [iCloud account: \(describe(status))] — \(error.localizedDescription)")
                if attempt < maxAttempts {
                    Thread.sleep(forTimeInterval: 0.75)
                }
            }
        }

        // Every attempt above used the SAME CloudKit-mirrored config the file
        // was created with, so reaching here means it's genuinely not
        // opening — not just "wrong config type," which was the old bug.
        // Recovery still uses that same CloudKit config, not a plain one,
        // so a rebuilt store can actually resync.
        logBoth("ModelContainer: CloudKit store unavailable after \(maxAttempts) attempts — clearing and rebuilding with CloudKit config")
        do {
            destroyStore(at: cloudConfig.url)
            let rebuilt = try ModelContainer(for: schema, configurations: [cloudConfig])
            logBoth("ModelContainer: rebuilt store using CloudKit config — will resync from iCloud if data exists there")
            return rebuilt
        } catch {
            logBoth("ModelContainer: rebuild with CloudKit config also failed — \(error.localizedDescription) — falling back to plain local store as last resort")
            return try recoveringLocalContainer(schema: schema)
        }
    }

    /// Writes the same message to both OSLog (via CrashReporter — visible
    /// in Console.app/Xcode even without a live debug session) and the
    /// in-app DebugLogger (Settings → Debug Log) — this runs during
    /// container init, before RootView.onAppear's beginSessionIfEnabled(),
    /// but DebugLogger.log(_:category:) only needs the user's
    /// "Enable Debug Log" setting to already be on (read directly from
    /// UserDefaults), not an active session, so it still captures here.
    private static func logBoth(_ message: String) {
        CrashReporter.log(message)
        DebugLogger.shared.log(message, category: "ModelContainer")
    }

    /// Best-effort, synchronous snapshot of the device's current iCloud
    /// account status — bridges CKContainer's completion-handler API with a
    /// short timeout so a hung/slow CloudKit daemon can never block launch
    /// indefinitely. Diagnostic only: this does not gate whether a retry
    /// happens above, since `.couldNotDetermine` right after boot is exactly
    /// the ambiguous case retrying is meant to ride out anyway — it's here
    /// so the logged failure reason says WHY a retry was needed instead of
    /// just that one was.
    private static func currentAccountStatusSync(timeout: TimeInterval = 1.0) -> CKAccountStatus {
        let semaphore = DispatchSemaphore(value: 0)
        var result: CKAccountStatus = .couldNotDetermine
        CKContainer.default().accountStatus { status, _ in
            result = status
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + timeout)
        return result
    }

    private static func describe(_ status: CKAccountStatus) -> String {
        switch status {
        case .available: return "available"
        case .noAccount: return "no account"
        case .restricted: return "restricted"
        case .temporarilyUnavailable: return "temporarily unavailable"
        case .couldNotDetermine: fallthrough
        @unknown default: return "could not determine"
        }
    }
}
