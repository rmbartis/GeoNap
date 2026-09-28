// Copyright © 2026 Robert Bartis. All rights reserved.

// DebugLogger.swift
// Thread-safe, append-only debug log that writes structured entries to a plain
// text file in the app's Documents folder.
//
// Usage (from any file, any thread):
//   DebugLogger.shared.log("Region entered", category: "Location")
//
// The log file location (visible in Files app):
//   On My iPhone → GeoNap → GeoNapDebug.log
//
// Logging is opt-in and controlled via the "Enable Debug Log" toggle in
// Settings.  When disabled, log() is a no-op.

import Foundation
import UIKit

// MARK: - DebugLogTrimmer

/// Pure trimming logic for DebugLogger's size cap, extracted as a standalone
/// enum (mirrors CalendarScanRefreshScheduling / CalendarScanCandidateMerger's
/// "pure logic only" convention elsewhere in this project) so it's unit
/// testable with small in-memory fixtures instead of writing real multi-MB
/// files to disk (2026-09-28).
nonisolated enum DebugLogTrimmer {
    /// Returns trimmed content keeping roughly the most recent `targetBytes`
    /// of `data`, snapped forward to the next newline so no entry is left
    /// truncated mid-line, with `noticePrefix` prepended — or `nil` if
    /// `data` is already at or under `maxBytes` and no trim is needed.
    static func trim(_ data: Data, maxBytes: Int, targetBytes: Int, noticePrefix: String) -> Data? {
        guard data.count > maxBytes else { return nil }
        guard targetBytes > 0, targetBytes < data.count else {
            // Degenerate config (targetBytes <= 0, or >= the whole file) —
            // nothing sensible to keep; drop everything but the notice.
            return noticePrefix.data(using: .utf8) ?? Data()
        }

        let seekOffset = data.count - targetBytes
        var tail = data.suffix(from: data.index(data.startIndex, offsetBy: seekOffset))

        // Snap forward to the next newline so the kept portion doesn't start
        // mid-entry.
        if let newlineIndex = tail.firstIndex(of: 0x0A) {
            tail = tail.suffix(from: tail.index(after: newlineIndex))
        }

        guard let noticeData = noticePrefix.data(using: .utf8) else { return Data(tail) }
        return noticeData + Data(tail)
    }
}

// MARK: - DebugLogger

final class DebugLogger {

    // MARK: Shared instance

    static let shared = DebugLogger()

    // MARK: - State

    /// Whether logging is currently active.
    /// Backed by UserDefaults so it persists across launches.
    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: UserDefaultsKey.debugLoggingEnabled) }
        set {
            UserDefaults.standard.set(newValue, forKey: UserDefaultsKey.debugLoggingEnabled)
            if newValue {
                writeSessionHeader()
            } else {
                log("Logging disabled by user.", category: "Logger")
            }
        }
    }

    /// Writes a fresh session header (device + app + build) if logging is enabled.
    /// Call once at app launch so every run in the log is stamped with the build it
    /// ran on — important when a user keeps logging on across an app update, so the
    /// build line always matches what Settings → About → "Build" shows.
    func beginSessionIfEnabled() {
        guard isEnabled else { return }
        writeSessionHeader()
    }

    // MARK: - File path

    /// The URL of the log file — `Documents/GeoNapDebug.log`.
    /// This path is shown to users in the confirmation dialog and is accessible
    /// via the Files app: On My iPhone → GeoNap → GeoNapDebug.log
    var logFileURL: URL {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GeoNapDebug.log")
    }

    // MARK: - In-memory buffer (for testing and last-N-entries UI)

    /// A structured log entry kept in memory.
    struct Entry {
        let timestamp: String
        let category:  String
        let message:   String
    }

    /// Maximum number of entries retained in `recentEntries`.
    private let maxRecentEntries = 200

    /// The most recent log entries, newest last.
    /// Populated synchronously in `log()` before the async file write,
    /// so tests can read it immediately without waiting for I/O.
    private(set) var recentEntries: [Entry] = []

    private let entriesLock = NSLock()

    // MARK: - Private

    private let queue = DispatchQueue(label: "com.geoalarm.debuglogger", qos: .utility)
    private let iso   = ISO8601DateFormatter()

    // MARK: - Size cap (2026-09-28)

    /// The log file is append-only with no cap otherwise — with diagnostic
    /// logging now expected to stay on indefinitely (see
    /// CalendarScanBackgroundTask.logPendingRequestsForDiagnostics), a
    /// long-running install would grow this file forever. Once it crosses
    /// `maxLogFileSizeBytes`, it's trimmed down to the most recent
    /// `trimTargetBytes` — checked (and, rarely, trimmed) on the same
    /// serial `queue` every write already runs on, so there's no new
    /// concurrency to worry about.
    private let maxLogFileSizeBytes: Int64 = 2 * 1024 * 1024   // 2 MB
    private let trimTargetBytes: Int64 = 1 * 1024 * 1024       // 1 MB

    private init() {}

    // MARK: - Public API

    /// Append a log entry.  No-op when logging is disabled.
    /// Safe to call from any thread or actor.
    func log(_ message: String, category: String = "App") {
        guard isEnabled else { return }

        let timestamp = iso.string(from: Date())

        // In-memory append — synchronous so callers can read recentEntries immediately.
        entriesLock.lock()
        recentEntries.append(Entry(timestamp: timestamp, category: category, message: message))
        if recentEntries.count > maxRecentEntries { recentEntries.removeFirst() }
        entriesLock.unlock()

        let entry = "[\(timestamp)] [\(category)] \(message)\n"

        queue.async { [weak self] in
            guard let self else { return }
            do {
                let url = self.logFileURL
                if FileManager.default.fileExists(atPath: url.path) {
                    let handle = try FileHandle(forWritingTo: url)
                    handle.seekToEndOfFile()
                    if let data = entry.data(using: .utf8) {
                        handle.write(data)
                    }
                    try handle.close()
                } else {
                    try entry.write(to: url, atomically: false, encoding: .utf8)
                }
            } catch {
                // Avoid recursive calls — just print to console
                print("[DebugLogger] Write failed: \(error.localizedDescription)")
            }
            self.trimLogFileIfNeeded()
        }
    }

    /// The banner DebugLogTrimmer.trim prepends to a trimmed file — pulled
    /// out as a static so DebugLoggerTrimNoticeTests can assert against the
    /// exact same string the real trim path uses.
    static let trimNotice: (Int64) -> String = { maxBytes in
        let separator = String(repeating: "─", count: 60)
        return "\(separator)\n[log trimmed — earlier entries removed to stay under \(ByteCountFormatter.string(fromByteCount: maxBytes, countStyle: .file))]\n\(separator)\n"
    }

    /// Trims the log file down to its most recent `trimTargetBytes` once it
    /// exceeds `maxLogFileSizeBytes`, via the pure DebugLogTrimmer.trim.
    /// Always called from `queue` (the same serial queue every write runs
    /// on), right after a write — so this is rare in practice (only once
    /// per ~1 MB of growth past the cap) rather than a full read+rewrite on
    /// every single log line. Loads the whole file into memory — fine at
    /// this size (capped at 2 MB), and keeps the trimming logic itself pure
    /// and testable rather than juggling FileHandle seeks.
    private func trimLogFileIfNeeded() {
        let url = logFileURL
        guard let data = try? Data(contentsOf: url) else { return }
        guard let trimmed = DebugLogTrimmer.trim(
            data,
            maxBytes: Int(maxLogFileSizeBytes),
            targetBytes: Int(trimTargetBytes),
            noticePrefix: Self.trimNotice(maxLogFileSizeBytes)
        ) else { return }

        do {
            try trimmed.write(to: url, options: .atomic)
        } catch {
            print("[DebugLogger] Trim write failed: \(error.localizedDescription)")
        }
    }

    /// Remove the log file and clear the in-memory buffer.
    func clearLog() {
        entriesLock.lock()
        recentEntries.removeAll()
        entriesLock.unlock()

        queue.async { [weak self] in
            guard let self else { return }
            try? FileManager.default.removeItem(at: self.logFileURL)
        }
        // Write a fresh header after clearing so the file exists immediately
        if isEnabled { writeSessionHeader() }
    }

    /// Size of the log file in bytes (0 if file does not exist).
    var logFileSizeBytes: Int64 {
        (try? FileManager.default.attributesOfItem(atPath: logFileURL.path)[.size] as? Int64) ?? 0
    }

    /// Human-readable file size string (e.g. "42 KB").
    var logFileSizeString: String {
        let bytes = logFileSizeBytes
        if bytes == 0 { return "empty" }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    // MARK: - Session header

    /// Write a header block with device / app / build info when logging is first enabled
    /// or after a clear.  Helps support personnel identify the session context.
    private func writeSessionHeader() {
        let device   = UIDevice.current
        let bundle   = Bundle.main
        let appName  = bundle.infoDictionary?["CFBundleDisplayName"] as? String
                       ?? bundle.infoDictionary?["CFBundleName"] as? String
                       ?? "GeoNap"
        let version  = bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build    = bundle.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        // The exact build identifier shown to the user in Settings → About → "Build".
        // Use Build.timestamp (auto-generated each build) so a log a user sends always
        // matches the build string they can read off their screen. The Info.plist
        // "BuildTimestamp" key is a placeholder that isn't reliably populated.
        let userBuild = Build.timestamp
        let ios      = device.systemVersion
        let model    = device.model
        let name     = device.name         // user's device name
        let locale   = Locale.current.identifier
        let tz       = TimeZone.current.identifier
        // Snapshot only — see WatchConnectivityManager.logPairingChangeIfNeeded()
        // for the log entries written whenever pairing actually changes mid-session.
        let watch    = WatchConnectivityManager.shared.pairingStatusDescription

        let separator = String(repeating: "─", count: 60)
        let header = """
        \(separator)
        GeoNap Debug Log — Session started \(iso.string(from: Date()))
        \(separator)
        App:      \(appName) \(version) (build \(build))
        Build:    \(userBuild)
        Device:   \(model) — \(name)
        iOS:      \(ios)
        Watch:    \(watch)
        Locale:   \(locale)   TZ: \(tz)
        \(separator)

        """

        queue.async { [weak self] in
            guard let self else { return }
            // Append to existing file (preserves prior sessions) or create new.
            let url = self.logFileURL
            do {
                if FileManager.default.fileExists(atPath: url.path) {
                    let handle = try FileHandle(forWritingTo: url)
                    handle.seekToEndOfFile()
                    if let data = header.data(using: .utf8) { handle.write(data) }
                    try handle.close()
                } else {
                    try header.write(to: url, atomically: false, encoding: .utf8)
                }
            } catch {
                print("[DebugLogger] Header write failed: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - UserDefaults Keys

extension DebugLogger {
    // `nonisolated` (Bob — 2026-07-09, warning clean-up): a single constant
    // key string, referenced from AppSettings.swift's `nonisolated enum
    // AppStorageKey` — without this, the module's default-MainActor-
    // isolation build setting made this implicitly MainActor-isolated
    // (DebugLogger itself carries no explicit annotation either way),
    // which broke that nonisolated reference. See AppSettings.swift's
    // file-header comment for the fuller explanation of this pattern.
    nonisolated enum UserDefaultsKey {
        static let debugLoggingEnabled = "debugLoggingEnabled"
    }
}
