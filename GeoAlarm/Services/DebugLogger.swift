// DebugLogger.swift
// Thread-safe, append-only debug log that writes structured entries to a plain
// text file in the app's Documents folder.
//
// Usage (from any file, any thread):
//   DebugLogger.shared.log("Region entered", category: "Location")
//
// The log file location (visible in Files app):
//   On My iPhone → NapAlarm → NapAlarmDebug.log
//
// Logging is opt-in and controlled via the "Enable Debug Log" toggle in
// Settings.  When disabled, log() is a no-op.

import Foundation
import UIKit

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

    // MARK: - File path

    /// The URL of the log file — `Documents/NapAlarmDebug.log`.
    /// This path is shown to users in the confirmation dialog and is accessible
    /// via the Files app: On My iPhone → NapAlarm → NapAlarmDebug.log
    var logFileURL: URL {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NapAlarmDebug.log")
    }

    // MARK: - Private

    private let queue = DispatchQueue(label: "com.geoalarm.debuglogger", qos: .utility)
    private let iso   = ISO8601DateFormatter()

    private init() {}

    // MARK: - Public API

    /// Append a log entry.  No-op when logging is disabled.
    /// Safe to call from any thread or actor.
    func log(_ message: String, category: String = "App") {
        guard isEnabled else { return }

        let timestamp = iso.string(from: Date())
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
        }
    }

    /// Remove the log file.
    func clearLog() {
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
                       ?? "NapAlarm"
        let version  = bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build    = bundle.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        let buildTS  = bundle.infoDictionary?["BuildTimestamp"] as? String ?? "?"
        let ios      = device.systemVersion
        let model    = device.model
        let name     = device.name         // user's device name
        let locale   = Locale.current.identifier
        let tz       = TimeZone.current.identifier

        let separator = String(repeating: "─", count: 60)
        let header = """
        \(separator)
        NapAlarm Debug Log — Session started \(iso.string(from: Date()))
        \(separator)
        App:      \(appName) \(version) (build \(build))
        BuildTS:  \(buildTS)
        Device:   \(model) — \(name)
        iOS:      \(ios)
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
    enum UserDefaultsKey {
        static let debugLoggingEnabled = "debugLoggingEnabled"
    }
}
