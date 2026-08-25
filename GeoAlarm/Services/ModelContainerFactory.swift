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
        return try rebuildCloudKitStore(schema: schema)
    }

    /// Deletes the on-disk CloudKit-mirrored store and opens a fresh one with
    /// the same CloudKit config — never a plain local one, so the rebuilt
    /// file can still resync from iCloud instead of being silently
    /// downgraded to local-only. Falls to `recoveringLocalContainer` (plain
    /// config) only if even a freshly rebuilt CloudKit-formatted store won't
    /// open at all (e.g. no CloudKit entitlement/account on this device).
    ///
    /// Extracted 2026-08-24 (non-blocking iCloud sync architecture) so both
    /// the short synchronous retry above (used by NapStopApp's instant
    /// fallback and IntentModelContainer, which can't await a long
    /// background resolve) and the patient background retry below
    /// (`resolveCloudKitContainerPatiently`) share this one destructive-
    /// rebuild implementation instead of duplicating it.
    @MainActor
    private static func rebuildCloudKitStore(schema: Schema) throws -> ModelContainer {
        let cloudConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false, cloudKitDatabase: .automatic)
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

    /// Single fast, synchronous attempt to open the CloudKit-backed store —
    /// no retry, no sleep. Returns `nil` immediately on any failure instead
    /// of throwing, so a caller can treat that as "not ready yet" and fall
    /// back to a non-blocking strategy rather than a hard error.
    ///
    /// Used by NapStopApp at launch (2026-08-24, non-blocking iCloud sync
    /// architecture) to try the common case — CloudKit already warm, store
    /// opens instantly — without ever blocking the UI for the multi-second
    /// retry loop in `openCloudKitContainerRecoveringIfNeeded`. If this
    /// returns `nil`, the app opens immediately on `makeLocalPlaceholder`
    /// instead, and `resolveCloudKitContainerPatiently` keeps trying in the
    /// background.
    @MainActor
    static func quickCloudKitAttempt(schema: Schema = schema) -> ModelContainer? {
        let cloudConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false, cloudKitDatabase: .automatic)
        return try? ModelContainer(for: schema, configurations: [cloudConfig])
    }

    /// An isolated in-memory container used as a temporary holding pen while
    /// the real CloudKit-backed store is still resolving in the background.
    /// Deliberately never touches the on-disk CloudKit file — stacking a
    /// second local store at/near that same path is exactly the kind of
    /// config-mismatch corruption risk `rebuildCloudKitStore` above exists
    /// to avoid. Anything the user creates against this container (e.g. a
    /// new alarm) is carried over to the resolved container by
    /// `migratePlaceholderAlarms` once it's ready.
    @MainActor
    static func makeLocalPlaceholder(schema: Schema = schema) -> ModelContainer {
        makeInMemory(schema: schema)
    }

    /// Resolves the CloudKit-backed container patiently, off the launch
    /// path: up to 20 attempts, starting at a 1s delay and backing off to a
    /// 3s cap between tries (~52s total budget) — long enough to ride out
    /// `cloudd` genuinely not being warmed up yet in the first moments after
    /// a device reboot, without ever blocking app launch (this `async`
    /// function is only ever awaited from a background `Task`, never from
    /// the `container` property itself). Uses `Task.sleep`, not
    /// `Thread.sleep` — this must yield, not block, the actor.
    ///
    /// Falls through to the existing `openCloudKitContainerRecoveringIfNeeded`
    /// only if every patient attempt above still fails — repurposed
    /// (2026-08-24) as the final last-resort fallback rather than removed:
    /// its own short retry + destructive-rebuild logic is still exactly
    /// right for that "nothing else worked" case, and IntentModelContainer
    /// / NapStopApp's instant-launch quick attempt still call it directly
    /// for their own synchronous needs.
    @MainActor
    static func resolveCloudKitContainerPatiently(schema: Schema = schema) async -> ModelContainer {
        let cloudConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false, cloudKitDatabase: .automatic)
        let maxAttempts = 20
        var delay: TimeInterval = 1.0

        for attempt in 1...maxAttempts {
            if let c = try? ModelContainer(for: schema, configurations: [cloudConfig]) {
                logBoth("ModelContainer: patient background resolve succeeded on attempt \(attempt)/\(maxAttempts)")
                return c
            }
            if attempt < maxAttempts {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                delay = min(delay + 0.5, 3.0)
            }
        }

        logBoth("ModelContainer: patient background resolve exhausted \(maxAttempts) attempts — falling back to short-retry/destructive-rebuild path")
        if let recovered = try? openCloudKitContainerRecoveringIfNeeded(schema: schema) {
            return recovered
        }
        // openCloudKitContainerRecoveringIfNeeded's own last-resort
        // (recoveringLocalContainer) already covers disk-backed failure —
        // reaching here means even that threw. Run in-memory for this
        // session rather than leave the app without any container at all.
        logBoth("ModelContainer: all disk-backed attempts failed during patient resolve — running in-memory for this session")
        return makeInMemory(schema: schema)
    }

    /// Carries over any `NapAlarm` created in the temporary placeholder
    /// container (see `makeLocalPlaceholder`) into the now-resolved target
    /// container, skipping any whose `id` is already present there (e.g. an
    /// alarm that finished syncing down from iCloud in the meantime).
    /// Returns the number of alarms actually migrated, for logging/banner
    /// purposes. No-ops (returns 0) if the placeholder never had any alarms
    /// — the common case, since this window is normally a few seconds.
    @MainActor
    static func migratePlaceholderAlarms(from placeholder: ModelContainer, into target: ModelContainer) -> Int {
        let sourceContext = placeholder.mainContext
        let targetContext = target.mainContext
        guard let sourceAlarms = try? sourceContext.fetch(FetchDescriptor<NapAlarm>()), !sourceAlarms.isEmpty else {
            return 0
        }
        let existingIDs = Set((try? targetContext.fetch(FetchDescriptor<NapAlarm>()))?.map(\.id) ?? [])
        var migrated = 0
        for alarm in sourceAlarms where !existingIDs.contains(alarm.id) {
            targetContext.insert(NapAlarm.copy(of: alarm))
            migrated += 1
        }
        if migrated > 0 {
            try? targetContext.save()
            logBoth("ModelContainer: migrated \(migrated) alarm(s) created during iCloud sync into the resolved store")
        }
        return migrated
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
