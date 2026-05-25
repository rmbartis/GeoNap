// CrashReporter.swift
// Thin wrapper around Firebase Crashlytics.
// Import this file instead of FirebaseCrashlytics directly so
// the rest of the app stays decoupled from the Firebase SDK.

import Foundation
import FirebaseCrashlytics

enum CrashReporter {

    // MARK: - Breadcrumbs

    /// Log a plain-text breadcrumb that will appear in the Crashlytics
    /// "Log" section for any crash that follows.
    static func log(_ message: String) {
        Crashlytics.crashlytics().log(message)
    }

    // MARK: - Non-fatal errors

    /// Record a caught error as a non-fatal issue in the Firebase Console.
    /// `context` is attached as a custom key so you can filter by feature.
    static func record(_ error: Error, context: String? = nil) {
        var userInfo: [String: Any] = [:]
        if let context {
            userInfo["context"] = context
        }
        Crashlytics.crashlytics().record(
            error: error,
            userInfo: userInfo.isEmpty ? nil : userInfo
        )
    }

    // MARK: - Custom keys

    /// Attach an arbitrary key/value pair that appears alongside every
    /// crash or non-fatal report — useful for app state (e.g. alarm count).
    static func setKey(_ key: String, value: CustomStringConvertible) {
        Crashlytics.crashlytics().setCustomValue(value.description, forKey: key)
    }
}
