// CalendarScanNotifier.swift
// Phase 3: posts a local "N new trips found" notification when a background
// (or manual) calendar scan turns up candidates the user hasn't seen before.
//
// This is deliberately NOT AlarmKit (see GeoAlarmScheduler.swift) — AlarmKit
// is reserved for the actual geofence alarm firing (full-screen, cuts through
// silent mode). A "here's what we found, come take a look" heads-up is a much
// lighter-weight interaction, so it uses the standard UNUserNotificationCenter
// local-notification API instead, matching how GeoNap's privacy text already
// describes notifications working ("local notifications entirely on-device
// using iOS's UNUserNotificationCenter" — see privacy.body.notifications).
//
// Tapping the notification just opens the app (default system behavior) —
// there's no deep link into the review sheet yet. The user reaches it via
// Settings → Calendar Scanning → "Review Pending Trips". Wiring a direct deep
// link is a reasonable follow-up but was left out of this pass to keep scope
// contained.

import Foundation
import UserNotifications

enum CalendarScanNotifier {

    /// Fixed identifier so a second notification replaces the first rather
    /// than stacking up multiple "new trips" banners.
    private static let requestIdentifier = "com.rmbartis.GeoNap.calendarScanNewTrips"

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
