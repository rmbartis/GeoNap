// Copyright © 2026 Robert Bartis. All rights reserved.

// CalendarScanNotifier.swift
// Phase 3: posts a local "N new trips found" notification when a background
// (or manual) calendar scan turns up candidates the user hasn't seen before.
//
// This is deliberately NOT AlarmKit (see GeoAlarmScheduler.swift) — AlarmKit
// is reserved for the actual geofence alarm firing (full-screen, cuts through
// silent mode). A "here's what we found, come take a look" heads-up is a much
// lighter-weight interaction, so it uses the silver UNUserNotificationCenter
// local-notification API instead, matching how GeoNap's privacy text already
// describes notifications working ("local notifications entirely on-device
// using iOS's UNUserNotificationCenter" — see privacy.body.notifications).
//
// Tapping the notification deep-links straight to the review sheet (see
// CalendarScanNotificationDelegate below) — Settings → Calendar Scanning →
// "Review Pending Trips" is still there as the manual route, but the
// notification no longer just dumps the user on the home screen (Bob, 2026-07-03).

import Foundation
import UserNotifications

enum CalendarScanNotifier {

    /// Fixed identifier so a second notification replaces the first rather
    /// than stacking up multiple "new trips" banners. Also used by
    /// CalendarScanNotificationDelegate to recognize a tap on this specific
    /// notification (internal, not private, so the delegate can see it).
    static let requestIdentifier = "com.rmbartis.GeoNap.calendarScanNewTrips"

    /// Requests notification authorization if the user hasn't already decided
    /// (granted or denied). Safe to call repeatedly. Returns whether alerts
    /// can actually be delivered right now.
    @discardableResult
    static func requestAuthorizationIfNeeded() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        case .notDetermined:
            do {
                return try await center.requestAuthorization(options: [.alert, .sound, .badge])
            } catch {
                DebugLogger.shared.log("Notification authorization request failed: \(error.localizedDescription)", category: "CalendarScan")
                return false
            }
        @unknown default:
            return false
        }
    }

    /// Posts (or replaces) the "new trips found" notification. No-op if
    /// authorization isn't granted — this never re-prompts from a background
    /// task context; that only happens from the Settings toggle (see
    /// CalendarScanSettingsView).
    static func postNewTripsNotification(count: Int, bundle: Bundle) async {
        guard count > 0 else { return }
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized
            || settings.authorizationStatus == .provisional
            || settings.authorizationStatus == .ephemeral else {
            DebugLogger.shared.log("Skipping new-trips notification — not authorized.", category: "CalendarScan")
            return
        }

        let content = UNMutableNotificationContent()
        content.title = NSLocalizedString("settings.calendarScan.notificationTitle", bundle: bundle, comment: "")
        let bodyFormat = NSLocalizedString("settings.calendarScan.notificationBody", bundle: bundle, comment: "")
        content.body = String.localizedStringWithFormat(bodyFormat, count)
        content.sound = .default

        let request = UNNotificationRequest(identifier: requestIdentifier, content: content, trigger: nil)
        do {
            try await center.add(request)
            DebugLogger.shared.log("Posted new-trips notification (count=\(count)).", category: "CalendarScan")
        } catch {
            DebugLogger.shared.log("Failed to post new-trips notification: \(error.localizedDescription)", category: "CalendarScan")
        }
    }
}

// MARK: - Notification tap deep link

extension Notification.Name {
    /// Posted when the user taps the "new trips found" notification, so
    /// ContentView can present the Calendar Scanning review sheet directly
    /// instead of just opening to the home screen (Bob, 2026-07-03).
    static let calendarScanReviewRequested = Notification.Name("com.rmbartis.GeoNap.calendarScanReviewRequested")
}

/// UNUserNotificationCenterDelegate for the Calendar Scanning "new trips
/// found" notification. Two jobs:
///   1. Still show the banner/sound if the notification arrives while the
///      app is already in the foreground (system default is silent otherwise).
///   2. On tap, post `.calendarScanReviewRequested` so ContentView opens
///      straight to the review sheet rather than just the home screen.
/// Assigned as UNUserNotificationCenter's delegate at app launch
/// (NapStopApp.init) — must happen early enough to catch a cold-launch tap.
final class CalendarScanNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {

    static let shared = CalendarScanNotificationDelegate()

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                 willPresent notification: UNNotification,
                                 withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .badge])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                 didReceive response: UNNotificationResponse,
                                 withCompletionHandler completionHandler: @escaping () -> Void) {
        if response.notification.request.identifier == CalendarScanNotifier.requestIdentifier {
            DispatchQueue.main.async {
                DebugLogger.shared.log("New-trips notification tapped — deep-linking to review sheet.", category: "CalendarScan")
                NotificationCenter.default.post(name: .calendarScanReviewRequested, object: nil)
            }
        }
        completionHandler()
    }
}
