// AlarmManager.swift
// Owns the list of GeoAlarms, coordinates region monitoring via LocationManager,
// fires local notifications on region events, and persists via SwiftData.

import Foundation
import UserNotifications
import CoreLocation
import SwiftData
import Combine
import UIKit
import AVFoundation

@MainActor
final class AlarmManager: ObservableObject {

    // MARK: - Published state
    @Published private(set) var alarms: [GeoAlarm] = []

    /// Set when the user taps a Spotlight search result — AlarmListView scrolls to this alarm.
    @Published var spotlightAlarmID: UUID?

    // MARK: - Dependencies

    /// Set by LocationManager after both @StateObjects are created.
    weak var locationManager: LocationManager? {
        didSet { bindLocationEvents() }
    }

    /// Injected via setModelContext() on app launch (from RootView.onAppear).
    private var modelContext: ModelContext?

    /// Debug logger — defaults to the shared singleton; override in tests.
    var logger: DebugLogging = DebugLogger.shared

    // MARK: - Audio player (foreground + background alarms — bypasses silent switch)
    private let audioPlayer = AlarmAudioPlayer()

    // Background task that keeps the app alive while the alarm audio plays.
    // Required when the geo-fence fires with the screen locked so iOS doesn't
    // suspend us before the AVAudioSession has a chance to start.
    // Once the .playback session is active, iOS lets audio continue on its own
    // (provided 'audio' is listed in UIBackgroundModes in Info.plist).
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

    // MARK: - Init
    init() {}

    // MARK: - SwiftData setup

    func setModelContext(_ context: ModelContext) {
        modelContext = context
        load()
    }

    // MARK: - Notification identifiers

    enum NotificationAction {
        static let snooze10        = "SNOOZE_10"
        static let dismiss         = "DISMISS"
        static let notifyContacts  = "NOTIFY_CONTACTS"
    }

    enum NotificationCategory {
        static let geoAlarm           = "GEO_ALARM"
        static let geoAlarmAutoNotify = "GEO_ALARM_AUTONOTIFY"
    }

    // MARK: - Auto-notify helpers

    /// Returns the per-alarm contact list (decoded from JSON).
    private func resolvedContacts(for alarm: GeoAlarm) -> [NotifyContact] {
        alarm.notifyContactList
    }

    // MARK: - Notification permission + category setup

    func requestNotificationPermission() {
        let center = UNUserNotificationCenter.current()

        // Register category before requesting permission so the Snooze
        // button is available on the very first notification.
        registerNotificationCategories()

        // Become the delegate so we handle Snooze taps and show banners
        // while the app is foregrounded.
        center.delegate = self

        // .criticalAlert is required to bypass the ringer switch in background
        // notifications. iOS silently ignores it if the entitlement isn't present,
        // so it's safe to request now — no crash or rejection risk.
        center.requestAuthorization(options: [.alert, .sound, .badge, .criticalAlert]) { granted, error in
            if let error = error {
                print("❌ Notification permission error: \(error.localizedDescription)")
            } else {
                print(granted ? "✅ Notifications granted" : "⚠️ Notifications denied")
            }
        }
    }

    private func registerNotificationCategories() {
        let snoozeAction = UNNotificationAction(
            identifier: NotificationAction.snooze10,
            title: "Snooze 10 min",
            options: []
        )
        let dismissAction = UNNotificationAction(
            identifier: NotificationAction.dismiss,
            title: "Dismiss",
            options: [.destructive]
        )
        let notifyContactsAction = UNNotificationAction(
            identifier: NotificationAction.notifyContacts,
            title: "Notify Contacts",
            options: [.foreground]          // Brings app to foreground to open compose UI
        )

        // Standard category — no auto-notify action
        let standard = UNNotificationCategory(
            identifier: NotificationCategory.geoAlarm,
            actions: [snoozeAction, dismissAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )

        // Auto-notify category — includes "Notify Contacts" action
        let autoNotify = UNNotificationCategory(
            identifier: NotificationCategory.geoAlarmAutoNotify,
            actions: [notifyContactsAction, snoozeAction, dismissAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )

        UNUserNotificationCenter.current().setNotificationCategories([standard, autoNotify])
    }

    // MARK: - CRUD

    func add(alarm: GeoAlarm) {
        modelContext?.insert(alarm)
        save()
        alarms.append(alarm)
        if alarm.isActive { startMonitoring(alarm) }
        logger.log(.alarmAdded(alarm.name))
    }

    /// Call after mutating a GeoAlarm's properties directly (SwiftData tracks changes).
    func update(alarm: GeoAlarm) {
        save()
        stopMonitoring(alarm)
        if alarm.isActive { startMonitoring(alarm) }
        logger.log(.alarmUpdated(alarm.name))
    }

    func delete(alarm: GeoAlarm) {
        let name = alarm.name
        stopMonitoring(alarm)
        modelContext?.delete(alarm)
        alarms.removeAll { $0.id == alarm.id }
        save()
        logger.log(.alarmDeleted(name))
    }

    func delete(at offsets: IndexSet) {
        offsets.forEach { stopMonitoring(alarms[$0]) }
        offsets.forEach { modelContext?.delete(alarms[$0]) }
        alarms.remove(atOffsets: offsets)
        save()
    }

    func toggleActive(_ alarm: GeoAlarm) {
        alarm.state = alarm.isActive ? .inactive : .active
        // Log before calling update() so the toggled state is reflected.
        logger.log(.alarmToggled(name: alarm.name, isActive: alarm.isActive))
        update(alarm: alarm)
    }

    // MARK: - Region monitoring helpers

    private func startMonitoring(_ alarm: GeoAlarm) {
        locationManager?.startMonitoring(region: alarm.clRegion)
    }

    private func stopMonitoring(_ alarm: GeoAlarm) {
        locationManager?.stopMonitoring(region: alarm.clRegion)
    }

    /// Re-register all active alarms — call on launch or after permission grant.
    func reregisterAllRegions() {
        locationManager?.stopMonitoringAll()
        alarms.filter(\.isActive).forEach { startMonitoring($0) }
    }

    // MARK: - Region event handling

    private func bindLocationEvents() {
        locationManager?.onRegionEntered = { [weak self] id in
            self?.handleRegionEvent(regionID: id, event: .onEntry)
        }
        locationManager?.onRegionExited = { [weak self] id in
            self?.handleRegionEvent(regionID: id, event: .onExit)
        }
    }

    func handleRegionEvent(regionID: String, event: RegionEvent) {

        // ── 1. Fire the alarm ──────────────────────────────────────────────
        // Match an ACTIVE alarm whose trigger matches this event.
        if let index = alarms.firstIndex(where: {
            $0.id.uuidString == regionID && $0.isActive && $0.regionEvent == event
        }) {
            alarms[index].state = .triggered
            alarms[index].lastTriggeredAt = Date()
            fireNotification(for: alarms[index])
            save()
            logger.log(.alarmTriggered(name: alarms[index].name))
            print("🔔 Alarm triggered: \(alarms[index].name)")
        }

        // ── 2. Hysteresis reset for repeating alarms ───────────────────────
        // A triggered, repeating alarm resets when the user crosses the
        // boundary in the OPPOSITE direction:
        //   onEntry alarm → resets on EXIT  (user left the station)
        //   onExit  alarm → resets on ENTRY (user returned to the origin)
        if let index = alarms.firstIndex(where: {
            $0.id.uuidString == regionID &&
            $0.state == .triggered &&
            $0.isRepeating &&
            $0.regionEvent != event        // opposite direction
        }) {
            alarms[index].state = .active
            save()
            startMonitoring(alarms[index])   // keep iOS monitoring the region
            logger.log(.alarmRearmed(name: alarms[index].name))
            print("🔄 Repeating alarm re-armed: \(alarms[index].name)")
        }
    }

    // MARK: - Local notification

    private func fireNotification(for alarm: GeoAlarm) {
        // ── ORDERING IS DELIBERATE ──────────────────────────────────────────
        // Schedule the local notification FIRST, before touching the audio
        // session. The visual banner + system notification must never depend on
        // the audio path succeeding.
        //
        // CarPlay / Bluetooth connect events generate a burst of audio
        // interruption & route-change callbacks exactly when an alarm fires.
        // Previously audio was started before the notification was scheduled, so
        // any stall or crash in that audio burst suppressed the notification
        // entirely — no banner AND no sound, specifically over CarPlay.
        // Scheduling first guarantees the user always gets the visual + system
        // notification regardless of what the audio session does afterward.

        let content = UNMutableNotificationContent()
        content.title = "📍 \(alarm.name)"
        content.body = alarm.note.isEmpty
            ? "\(alarm.regionEvent.rawValue) detected."
            : alarm.note
        // Set the notification sound. nil means no audio (vibrate-only alarms).
        // .defaultCritical bypasses the silent switch once Apple grants the
        // Critical Alerts entitlement; custom .wav files fall back to the
        // system default if not found in the bundle (no crash, just audible).
        content.sound = alarm.notificationSound.unSound

        // Time Sensitive breaks through Focus / Do Not Disturb on iOS 15+.
        // No entitlement required. Once the Critical Alerts entitlement is
        // granted, upgrade this to .critical so it also bypasses the ringer switch.
        content.interruptionLevel = .timeSensitive

        // Resolve contacts first so they can go into both userInfo and categoryIdentifier.
        let contacts = resolvedContacts(for: alarm)
        content.userInfo = [
            "alarmID":   alarm.id.uuidString,
            "alarmName": alarm.name,
            "latitude":  alarm.latitude,
            "longitude": alarm.longitude,
            "contacts":  contacts.toJSON()   // JSON-encoded [NotifyContact] for the delegate
        ]

        // Use the auto-notify category when the alarm has auto-notify on and contacts exist.
        content.categoryIdentifier = (alarm.autoNotify && !contacts.isEmpty)
            ? NotificationCategory.geoAlarmAutoNotify
            : NotificationCategory.geoAlarm

        let request = UNNotificationRequest(
            identifier: alarm.id.uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("❌ Notification failed: \(error.localizedDescription)")
            }
        }

        // ── Now start the bypass-silent-switch audio ────────────────────────
        // AVAudioPlayer with .playback category bypasses the ringer/silent switch —
        // unlike UNNotificationSound which obeys it. When the screen is locked the
        // app is in .background; a UIBackgroundTask keeps us alive long enough for
        // the audio session to start, after which iOS sustains it automatically
        // (requires 'audio' in UIBackgroundModes — see Xcode target → Signing &
        // Capabilities → Background Modes → Audio, AirPlay, and Picture in Picture).
        beginAudioBackgroundTask()
        audioPlayer.play(alarm.notificationSound)

        // Linked Shortcut can only be opened while the app is foregrounded.
        if UIApplication.shared.applicationState == .active {
            let shortcutName = alarm.linkedShortcut.trimmingCharacters(in: .whitespaces)
            if !shortcutName.isEmpty,
               let encoded = shortcutName.addingPercentEncoding(
                   withAllowedCharacters: .urlQueryAllowed),
               let url = URL(string: "shortcuts://run-shortcut?name=\(encoded)") {
                UIApplication.shared.open(url)
                print("🔗 Opening Shortcut: \(shortcutName)")
            }
        }

        // Refresh Siri / Shortcuts parameter list so the system knows
        // which alarms exist (used by AlarmFiredIntent suggestions).
        GeoNapShortcuts.updateAppShortcutParameters()
    }

    // MARK: - Background task management

    private func beginAudioBackgroundTask() {
        endAudioBackgroundTask()   // cancel any prior task
        backgroundTask = UIApplication.shared.beginBackgroundTask(
            withName: "GeoAlarmAudioPlayback"
        ) { [weak self] in
            // Expiry handler — iOS is about to suspend the app.
            // Do NOT stop the audio player here: once the .playback AVAudioSession
            // is active, iOS sustains it independently (requires 'audio' in
            // UIBackgroundModes). Stopping here would silence the alarm on lock screen.
            // Just end the task token so iOS doesn't terminate us for holding it.
            self?.endAudioBackgroundTask()
        }
    }

    private func endAudioBackgroundTask() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }

    // MARK: - Auto-notify contact dispatch

    /// Opens a pre-composed SMS or email so the user can send their location to contacts.
    /// Called on the main actor after the user taps "Notify Contacts" in the notification banner.
    func sendAutoNotification(alarmName: String, latitude: Double, longitude: Double,
                               contactsJSON: String = "") {
        let contacts = [NotifyContact].fromJSON(contactsJSON)
        guard !contacts.isEmpty else { return }

        let mapsURL = "https://maps.apple.com/?ll=\(latitude),\(longitude)"
        let message = "🔔 GeoAlarm fired: \"\(alarmName)\"\nMy location: \(mapsURL)"

        let phones = contacts.filter { !$0.isEmail }.map(\.value)
        let emails = contacts.filter {  $0.isEmail }.map(\.value)

        // Prefer SMS — supports comma-separated recipients in one URL.
        if !phones.isEmpty {
            let recipients  = phones.joined(separator: ",")
            let encodedBody = message.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            if let url = URL(string: "sms:\(recipients)&body=\(encodedBody)") {
                UIApplication.shared.open(url)
                return
            }
        }

        // Fall back to Mail for email-only contacts.
        if !emails.isEmpty {
            let to      = emails.joined(separator: ",")
            let subject = "GeoAlarm: \(alarmName)"
                .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            let body    = message
                .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            if let url = URL(string: "mailto:\(to)?subject=\(subject)&body=\(body)") {
                UIApplication.shared.open(url)
            }
        }
    }

    // MARK: - Snooze

    /// Suppress a triggered alarm and re-arm it after `minutes` minutes.
    func snooze(_ alarm: GeoAlarm, minutes: Int = 10) {
        alarm.state = .snoozed
        save()
        logger.log(.alarmSnoozed(name: alarm.name, minutes: minutes))
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(minutes * 60)) { [weak self] in
            guard let self,
                  let index = self.alarms.firstIndex(where: { $0.id == alarm.id }),
                  self.alarms[index].state == .snoozed else { return }
            self.alarms[index].state = .active
            self.startMonitoring(self.alarms[index])
            self.save()
        }
    }

    // MARK: - SwiftData persistence

    private func save() {
        try? modelContext?.save()
    }

    private func load() {
        guard let context = modelContext else { return }
        alarms = (try? context.fetch(
            FetchDescriptor<GeoAlarm>(sortBy: [SortDescriptor(\.name)])
        )) ?? []
    }
}

// MARK: - Preview support

#if DEBUG
    /// Directly sets the alarms array — for SwiftUI Previews only.
    func injectPreviewAlarms(_ previewAlarms: [GeoAlarm]) {
        alarms = previewAlarms
    }

    static var preview: AlarmManager {
        let mgr = AlarmManager()
        mgr.injectPreviewAlarms(GeoAlarm.samples)
        return mgr
    }
#endif

// MARK: - UNUserNotificationCenterDelegate

extension AlarmManager: UNUserNotificationCenterDelegate {

    /// Called when the user taps an action button (Snooze / Dismiss) on the
    /// notification — on iPhone, iPad, or Apple Watch.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo  = response.notification.request.content.userInfo
        let alarmID   = userInfo["alarmID"] as? String
        let action    = response.actionIdentifier

        Task { @MainActor in
            switch action {
            case NotificationAction.snooze10:
                audioPlayer.stop()
                endAudioBackgroundTask()
                if let id = alarmID,
                   let alarm = alarms.first(where: { $0.id.uuidString == id }) {
                    snooze(alarm, minutes: 10)
                    print("😴 Snoozed alarm: \(alarm.name) for 10 min")
                }

            case NotificationAction.notifyContacts:
                let info         = response.notification.request.content.userInfo
                let name         = info["alarmName"] as? String ?? "Alarm"
                let latitude     = info["latitude"]  as? Double ?? 0
                let longitude    = info["longitude"] as? Double ?? 0
                let contactsJSON = info["contacts"]  as? String ?? ""
                sendAutoNotification(alarmName: name, latitude: latitude, longitude: longitude,
                                     contactsJSON: contactsJSON)
                print("📤 Auto-notify contacts for alarm: \(name)")

            case NotificationAction.dismiss,
                 UNNotificationDismissActionIdentifier:
                audioPlayer.stop()
                endAudioBackgroundTask()

            case UNNotificationDefaultActionIdentifier:
                // User tapped the notification to open the app (e.g. from the
                // lock screen). When the alarm fired in the background, the
                // audio player was skipped (app wasn't active), so the custom
                // sound never played. Play it now that the app is foregrounded.
                if let id = alarmID,
                   let alarm = alarms.first(where: { $0.id.uuidString == id }) {
                    audioPlayer.play(alarm.notificationSound)
                    print("🔔 Playing alarm sound after notification opened: \(alarm.name)")
                }

            default:
                break
            }
            completionHandler()
        }
    }

    /// Show notification banners even when the app is in the foreground
    /// (e.g. the user is looking at the alarm list when they arrive).
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
    }
}
