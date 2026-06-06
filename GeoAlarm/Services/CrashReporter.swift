// CrashReporter.swift
// Native crash and error reporting — replaces Firebase Crashlytics.
// No third-party SDKs. No data leaves the device.
//
// Breadcrumbs and non-fatal errors are written to two places:
//   1. OSLog — visible in Xcode console and Console.app, and automatically
//      included in iOS crash reports captured by the system.
//   2. DebugLogger — visible in the in-app debug log (Settings → Support).
//
// System crash logs are captured automatically by iOS and accessible via:
//   Settings → Privacy & Security → Analytics & Improvements → Analytics Data
//   Xcode → Window → Devices & Simulators → View Device Logs
//
// The public API is intentionally identical to the old Crashlytics wrapper
// so no call sites in the app needed to change.

import Foundation
import OSLog

enum CrashReporter {

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.rmbartis.GeoNap",
        category: "CrashReporter"
    )

    // MARK: - Breadcrumbs

    /// Log a plain-text breadcrumb.
    /// Appears in Xcode console, Console.app, and is included in system
    /// crash reports that follow — providing context for the crash.
    static func log(_ message: String) {
        logger.info("📍 \(message, privacy: .public)")
    }

    // MARK: - Non-fatal errors

    /// Record a caught error for diagnostic purposes.
    /// Written to OSLog; visible in Xcode console and system crash reports.
    static func record(_ error: Error, context: String? = nil) {
        let tag = context.map { "[\($0)] " } ?? ""
        let description = "\(tag)\(error.localizedDescription)"
        logger.error("❌ Non-fatal: \(description, privacy: .public)")
    }

    // MARK: - Custom keys

    /// Attach a key/value pair to the OSLog stream (mirrors Crashlytics API).
    static func setKey(_ key: String, value: CustomStringConvertible) {
        logger.debug("🔑 \(key, privacy: .public)=\(value.description, privacy: .public)")
    }
}

