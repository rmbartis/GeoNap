// AlarmManager.swift
// Owns the list of NapAlarms, coordinates region monitoring via LocationManager,
// fires local notifications on region events, and persists via SwiftData.

import Foundation
import UserNotifications
import CoreLocation
import SwiftData
import CoreData
import Combine
import MessageUI

@MainActor
final class AlarmManager: NSObject, ObservableObject {

    // MARK: - Published state
    @Published private(set) var alarms: [NapAlarm] = []

    /// Set when an alarm fires and there are phone contacts to notify.
    /// ContentView observes this and presents the Messages compose sheet.
    @Published var pendingContactMessage: ContactMessage? = nil

    /// Set when the app is opened from a Spotlight search result.
    /// ContentView observes this and navigates to the matching AlarmDetailView.
    @Published var spotlightAlarmID: UUID? = nil

    // MARK: - Dependencies

    /// Set by LocationManager after both @StateObjects are created.
    weak var locationManager: LocationManager? {
        didSet { bindLocationEvents() }
    }

    /// Injected via setModelContext() on app launch (from RootView.onAppear).
    private var modelContext: ModelContext?

    // MARK: - Init
    override init() { super.init() }

    // MARK: - SwiftData setup

    func setModelContext(_ context: ModelContext) {
        modelContext = context
        load()
        observeRemoteChanges()
    }

    /// Listens for CloudKit remote-change notifications so alarms stay in sync
    /// when another device adds, edits, or deletes an alarm via iCloud.
    private func observeRemoteChanges() {
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name.NSPersistentStoreRemoteChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.load()
                self.reregisterAllRegions()
                print("☁️ iCloud sync received — alarms reloaded")
            }
        }
    }

    // MARK: - Notification identifiers

    enum NotificationAction {
        static let snooze10       = "SNOOZE_10"
        static let dismiss        = "DISMISS"
        static let notifyContact  = "NOTIFY_CONTACT"
    }

    enum NotificationCategory {
        /// Standard alarm — no contact action.
        static let geoAlarm        = "GEO_ALARM"
        /// Alarm with a contact set — includes "Notify Contact" action.
        static let geoAlarmContact = "GEO_ALARM_CONTACT"
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

        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("❌ Notification permission error: \(error.localizedDescription)")
                DebugLogger.shared.log("Notification permission error: \(error.localizedDescription)", category: "Notifications")
            } else {
                let msg = granted ? "Notification permission granted" : "Notification permission denied"
                print(granted ? "✅ Notifications granted" : "⚠️ Notifications denied")
                DebugLogger.shared.log(msg, category: "Notifications")
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

        // Single category for all alarms — contact messaging is triggered automatically,
        // not via a user-facing action button.
        let standardCategory = UNNotificationCategory(
            identifier: NotificationCategory.geoAlarm,
            actions: [snoozeAction, dismissAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        UNUserNotificationCenter.current().setNotificationCategories([standardCategory])
    }

    // MARK: - Region limit

    /// iOS caps CLLocationManager region monitoring at 20 simultaneous regions.
    static let regionMonitoringLimit = 20

    /// Number of currently active (monitored) alarms.
    var activeAlarmCount: Int { alarms.filter(\.isActive).count }

    /// True when one or two slots remain — show a caution warning.
    var isNearRegionLimit: Bool { activeAlarmCount >= Self.regionMonitoringLimit - 2 }

    /// True when all slots are full — block adding new active alarms.
    var isAtRegionLimit: Bool  { activeAlarmCount >= Self.regionMonitoringLimit }

    // MARK: - CRUD

    func add(alarm: NapAlarm) {
        // If already at the iOS 20-region cap, insert as inactive so monitoring
        // isn't attempted. The user can enable it after disabling another alarm.
        var toInsert = alarm
        if alarm.isActive && isAtRegionLimit {
            toInsert = NapAlarm(
                id: alarm.id, name: alarm.name,
                latitude: alarm.latitude, longitude: alarm.longitude,
                radius: alarm.radius, regionEvent: alarm.regionEvent,
                state: .inactive, note: alarm.note,
                isRepeating: alarm.isRepeating,
                hasTimeWindow: alarm.hasTimeWindow,
                windowStart: alarm.windowStart, windowEnd: alarm.windowEnd,
                activeDays: alarm.activeDays,
                notificationSound: alarm.notificationSound
            )
            DebugLogger.shared.log("Alarm '\(alarm.name)' inserted as INACTIVE — region monitoring limit reached (\(Self.regionMonitoringLimit))", category: "AlarmManager")
        }
        modelContext?.insert(toInsert)
        save()
        alarms.append(toInsert)
        SpotlightManager.shared.index(toInsert)
        if toInsert.isActive {
            startMonitoring(toInsert)
            DebugLogger.shared.log("Alarm added + monitoring started: '\(toInsert.name)' radius=\(Int(toInsert.radius))m event=\(toInsert.regionEvent.rawValue) lat=\(toInsert.latitude) lon=\(toInsert.longitude)", category: "AlarmManager")
        } else {
            DebugLogger.shared.log("Alarm added (inactive): '\(toInsert.name)'", category: "AlarmManager")
        }
    }

    /// Applies all editable fields from `alarm` (built by AlarmViewModel.buildAlarm())
    /// onto the existing SwiftData-managed object with the same UUID, then saves.
    /// buildAlarm() creates a new, uninserted instance — mutating the managed object
    /// in place is required for SwiftData to track and persist the changes.
    func update(alarm: NapAlarm) {
        guard let existing = alarms.first(where: { $0.id == alarm.id }) else {
            // No existing record found — this is a programmer error; do nothing.
            print("[AlarmManager] update(alarm:) called with unknown alarm ID \(alarm.id) — ignored")
            return
        }
        stopMonitoring(existing)
        existing.name              = alarm.name
        existing.latitude          = alarm.latitude
        existing.longitude         = alarm.longitude
        existing.radius            = alarm.radius
        existing.regionEvent       = alarm.regionEvent
        existing.note              = alarm.note
        existing.isRepeating       = alarm.isRepeating
        existing.hasTimeWindow     = alarm.hasTimeWindow
        existing.windowStart       = alarm.windowStart
        existing.windowEnd         = alarm.windowEnd
        existing.state             = alarm.state
        existing.soundNameRaw      = alarm.soundNameRaw
        existing.activeDaysRaw     = alarm.activeDaysRaw
        existing.notifyContact     = alarm.notifyContact
        existing.notifyContactsJSON = alarm.notifyContactsJSON
        save()
        SpotlightManager.shared.index(existing)
        if existing.isActive { startMonitoring(existing) }
    }

    func delete(alarm: NapAlarm) {
        DebugLogger.shared.log("Alarm deleted: '\(alarm.name)'", category: "AlarmManager")
        stopMonitoring(alarm)
        SpotlightManager.shared.deindex(alarm)
        modelContext?.delete(alarm)
        alarms.removeAll { $0.id == alarm.id }
        save()
    }

    func delete(at offsets: IndexSet) {
        offsets.forEach { stopMonitoring(alarms[$0]) }
        offsets.forEach { SpotlightManager.shared.deindex(alarms[$0]) }
        offsets.forEach { modelContext?.delete(alarms[$0]) }
        for index in offsets.reversed() {
            alarms.remove(at: index)
        }
        save()
    }

    func toggleActive(_ alarm: NapAlarm) {
        alarm.state = alarm.isActive ? .inactive : .active
        update(alarm: alarm)
    }

    // MARK: - Region monitoring helpers

    private func startMonitoring(_ alarm: NapAlarm) {
        locationManager?.startMonitoring(region: alarm.clRegion)
    }

    private func stopMonitoring(_ alarm: NapAlarm) {
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
        // Match an ACTIVE alarm whose trigger matches this event AND whose
        // time window (if set) includes the current time.
        if let index = alarms.firstIndex(where: {
            $0.id.uuidString == regionID && $0.isActive && $0.regionEvent == event
        }) {
            guard alarms[index].isWithinWindow() else {
                print("⏰ Alarm '\(alarms[index].name)' skipped — outside time window")
                return
            }
            alarms[index].state = .triggered
            alarms[index].lastTriggeredAt = Date()
            alarms[index].triggerCount += 1
            CrashReporter.log("Alarm triggered: \(alarms[index].name) (\(event.rawValue))")
            CrashReporter.setKey("lastTriggeredAlarm", value: alarms[index].name)
            DebugLogger.shared.log("🔔 Alarm TRIGGERED: '\(alarms[index].name)' event=\(event.rawValue) triggerCount=\(alarms[index].triggerCount) regionID=\(regionID)", category: "AlarmManager")
            fireNotification(for: alarms[index])
            queueAutoNotify(for: alarms[index])
            scheduleWindowEndGuard(for: alarms[index])
            save()
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
            DebugLogger.shared.log("🔄 Repeating alarm re-armed: '\(alarms[index].name)'", category: "AlarmManager")
            print("🔄 Repeating alarm re-armed: \(alarms[index].name)")
        }
    }

    // MARK: - Local notification

    private func fireNotification(for alarm: NapAlarm) {
        let content = UNMutableNotificationContent()
        content.title = "📍 \(alarm.name)"
        content.body = alarm.note.isEmpty
            ? "\(alarm.regionEvent.rawValue) detected."
            : alarm.note
        content.sound = alarm.notificationSound.unSound
        content.categoryIdentifier = NotificationCategory.geoAlarm
        content.userInfo = buildNotifyUserInfo(for: alarm)

        let request = UNNotificationRequest(
            identifier: alarm.id.uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("❌ Notification failed: \(error.localizedDescription)")
                DebugLogger.shared.log("Notification delivery failed: \(error.localizedDescription)", category: "AlarmManager")
            }
        }
    }

    /// Sets `pendingContactMessage` immediately when an alarm fires so the SMS
    /// compose sheet appears as soon as the app is (or comes) in the foreground.
    ///
    /// This is separate from the notification-tap recovery path in `didReceive`
    /// (which handles the background → tap → relaunch case).  Having both ensures
    /// the compose sheet is never missed:
    ///   • App in foreground: sheet appears immediately via this call.
    ///   • App in background: user taps notification → `didReceive` sets it as backup.
    private func queueAutoNotify(for alarm: NapAlarm) {
        let phones = alarm.notifyContactList.filter { !$0.isEmail }.map { $0.value }
        guard alarm.notifyContact, !phones.isEmpty else { return }

        let direction = alarm.regionEvent == .onEntry ? "Arrival" : "Departure"
        let verb      = alarm.regionEvent == .onEntry ? "arrived at" : "departed from"
        let timeStr   = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .short)
        var body = "[\(direction)] I \(verb) \(alarm.name) at \(timeStr)."
        if !alarm.note.isEmpty { body += " \(alarm.note)" }

        pendingContactMessage = ContactMessage(phones: phones, body: body)
        DebugLogger.shared.log("Auto-Notify: SMS compose queued at alarm fire (\(phones.count) contact(s))", category: "AlarmManager")
    }

    /// Builds the userInfo dictionary for a notification.
    /// Always contains "alarmID". When Auto-Notify is enabled with phone contacts,
    /// also embeds "notifyPhones" and "notifyBody" so that contact data survives
    /// an app relaunch triggered by tapping the notification.
    ///
    /// Exposed `internal` (not `private`) so unit tests can verify the output
    /// without going through UNUserNotificationCenter.
    func buildNotifyUserInfo(for alarm: NapAlarm) -> [String: Any] {
        var userInfo: [String: Any] = ["alarmID": alarm.id.uuidString]
        guard alarm.notifyContact, !alarm.notifyContactList.isEmpty else { return userInfo }

        let timeStr   = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .short)
        let direction = alarm.regionEvent == .onEntry ? "Arrival" : "Departure"
        let verb      = alarm.regionEvent == .onEntry ? "arrived at" : "departed from"
        var msgBody   = "[\(direction)] I \(verb) \(alarm.name) at \(timeStr)."
        if !alarm.note.isEmpty { msgBody += " \(alarm.note)" }

        let phones = alarm.notifyContactList.filter { !$0.isEmail }.map { $0.value }

        if !phones.isEmpty {
            userInfo["notifyPhones"] = phones
            userInfo["notifyBody"]   = msgBody
            DebugLogger.shared.log("Auto-Notify: \(phones.count) SMS contact(s) embedded in notification for '\(alarm.name)'", category: "AlarmManager")
        }
        return userInfo
    }

    /// Recovers Auto-Notify contact data from a notification's userInfo dictionary
    /// and sets `pendingContactMessage` accordingly.
    /// Called from the notification-tap response handler so that the SMS compose
    /// sheet appears even when the app was fully relaunched by tapping the notification.
    ///
    /// Exposed `internal` so unit tests can verify recovery without needing a real
    /// `UNNotificationResponse` object.
    func recoverAutoNotify(from userInfo: [AnyHashable: Any]) {
        let body = userInfo["notifyBody"] as? String ?? ""

        if let phones = userInfo["notifyPhones"] as? [String], !phones.isEmpty {
            pendingContactMessage = ContactMessage(phones: phones, body: body)
            DebugLogger.shared.log("Auto-Notify: SMS compose queued from notification tap (\(phones.count) contact(s))", category: "AlarmManager")
        }
    }

    // MARK: - Time window guard

    /// Schedules a timer that fires at windowEnd.
    /// If the alarm is still active or triggered at that point (user hasn't left
    /// the region), it is automatically deactivated — satisfying the guard condition.
    private func scheduleWindowEndGuard(for alarm: NapAlarm) {
        guard alarm.hasTimeWindow, let end = alarm.windowEnd else { return }

        let cal = Calendar.current
        let now = Date()
        let endHour   = cal.component(.hour,   from: end)
        let endMinute = cal.component(.minute, from: end)

        guard var fireDate = cal.date(bySettingHour: endHour,
                                      minute: endMinute,
                                      second: 0,
                                      of: now) else { return }
        // If the end time has already passed today, fire tomorrow
        // (handles overnight windows where end is past midnight).
        if fireDate <= now {
            fireDate = cal.date(byAdding: .day, value: 1, to: fireDate) ?? fireDate
        }

        let delay = fireDate.timeIntervalSince(now)
        let alarmID = alarm.id

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self,
                  let index = self.alarms.firstIndex(where: { $0.id == alarmID }),
                  self.alarms[index].hasTimeWindow else { return }

            let currentState = self.alarms[index].state
            guard currentState == .active || currentState == .triggered else { return }

            self.alarms[index].state = .inactive
            self.stopMonitoring(self.alarms[index])
            self.save()
            print("⏰ Window closed: '\(self.alarms[index].name)' auto-deactivated")
            CrashReporter.log("Window end guard fired: \(self.alarms[index].name)")
        }
    }

    // MARK: - Snooze

    /// Suppress a triggered alarm and re-arm it after `minutes` minutes.
    func snooze(_ alarm: NapAlarm, minutes: Int = 10) {
        alarm.state = .snoozed
        save()
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
        do {
            try modelContext?.save()
        } catch {
            print("❌ SwiftData save failed: \(error.localizedDescription)")
            DebugLogger.shared.log("SwiftData save FAILED: \(error.localizedDescription)", category: "AlarmManager")
            CrashReporter.record(error, context: "SwiftData.save")
        }
        // Push latest state to paired Apple Watch after every save.
        WatchConnectivityManager.shared.updateWatch(with: alarms)
    }

    private func load() {
        guard let context = modelContext else { return }
        do {
            alarms = try context.fetch(
                FetchDescriptor<NapAlarm>(sortBy: [SortDescriptor(\.name)])
            )
            CrashReporter.setKey("alarmCount", value: alarms.count)
            // Rebuild Spotlight index to match current alarms on every launch.
            SpotlightManager.shared.reindexAll(alarms)
        } catch {
            print("❌ SwiftData load failed: \(error.localizedDescription)")
            CrashReporter.record(error, context: "SwiftData.load")
            alarms = []
        }
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension AlarmManager: UNUserNotificationCenterDelegate {

    /// Called when the user taps an action button (Snooze / Dismiss) —
    /// works on iPhone lock screen, notification banner, and Apple Watch.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let alarmID = response.notification.request.content.userInfo["alarmID"] as? String
        let action  = response.actionIdentifier

        // Extract only the Sendable values we need before crossing into the Task.
        // [AnyHashable: Any] is not Sendable, so we must not capture `userInfo` directly.
        let notifyPhones = response.notification.request.content.userInfo["notifyPhones"] as? [String]
        let notifyBody   = response.notification.request.content.userInfo["notifyBody"]   as? String ?? ""

        Task { @MainActor in
            switch action {
            case NotificationAction.snooze10:
                if let id = alarmID,
                   let alarm = alarms.first(where: { $0.id.uuidString == id }) {
                    snooze(alarm, minutes: 10)
                    print("😴 Snoozed: \(alarm.name) for 10 min")
                    DebugLogger.shared.log("Alarm snoozed 10 min via notification action: '\(alarm.name)'", category: "AlarmManager")
                }

            default:
                // Recover Auto-Notify contact data from the notification's userInfo.
                // This handles the case where the app was fully relaunched by tapping
                // the notification and in-memory pendingContactMessage/pendingMailMessage was lost.
                if let phones = notifyPhones, !phones.isEmpty {
                    pendingContactMessage = ContactMessage(phones: phones, body: notifyBody)
                    DebugLogger.shared.log("Auto-Notify: SMS compose queued from notification tap (\(phones.count) contact(s))", category: "AlarmManager")
                }
            }
            completionHandler()
        }
    }

    /// Show banner + sound even when the app is open in the foreground.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
    }
}
