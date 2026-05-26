// AlarmManager.swift
// Owns the list of GeoAlarms, coordinates region monitoring via LocationManager,
// fires local notifications on region events, and persists via SwiftData.

import Foundation
import UserNotifications
import CoreLocation
import SwiftData
import CoreData
import Combine

@MainActor
final class AlarmManager: NSObject, ObservableObject {

    // MARK: - Published state
    @Published private(set) var alarms: [GeoAlarm] = []

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
        static let snooze10 = "SNOOZE_10"
        static let dismiss  = "DISMISS"
    }

    enum NotificationCategory {
        static let geoAlarm = "GEO_ALARM"
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
            } else {
                print(granted ? "✅ Notifications granted" : "⚠️ Notifications denied")
            }
        }
    }

    private func registerNotificationCategories() {
        let snoozeAction = UNNotificationAction(
            identifier: NotificationAction.snooze10,
            title: "Snooze 10 min",
            options: []                     // Works on Lock Screen and Apple Watch
        )
        let dismissAction = UNNotificationAction(
            identifier: NotificationAction.dismiss,
            title: "Dismiss",
            options: [.destructive]
        )
        let category = UNNotificationCategory(
            identifier: NotificationCategory.geoAlarm,
            actions: [snoozeAction, dismissAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
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

    func add(alarm: GeoAlarm) {
        // If already at the iOS 20-region cap, insert as inactive so monitoring
        // isn't attempted. The user can enable it after disabling another alarm.
        var toInsert = alarm
        if alarm.isActive && isAtRegionLimit {
            toInsert = GeoAlarm(
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
        }
        modelContext?.insert(toInsert)
        save()
        alarms.append(toInsert)
        if toInsert.isActive { startMonitoring(toInsert) }
    }

    /// Applies all editable fields from `alarm` (built by AlarmViewModel.buildAlarm())
    /// onto the existing SwiftData-managed object with the same UUID, then saves.
    /// buildAlarm() creates a new, uninserted instance — mutating the managed object
    /// in place is required for SwiftData to track and persist the changes.
    func update(alarm: GeoAlarm) {
        guard let existing = alarms.first(where: { $0.id == alarm.id }) else {
            // No existing record found (shouldn't happen) — fall back to insert.
            add(alarm: alarm)
            return
        }
        stopMonitoring(existing)
        existing.name          = alarm.name
        existing.latitude      = alarm.latitude
        existing.longitude     = alarm.longitude
        existing.radius        = alarm.radius
        existing.regionEvent   = alarm.regionEvent
        existing.note          = alarm.note
        existing.isRepeating   = alarm.isRepeating
        existing.hasTimeWindow = alarm.hasTimeWindow
        existing.windowStart   = alarm.windowStart
        existing.windowEnd     = alarm.windowEnd
        existing.state         = alarm.state
        existing.soundNameRaw  = alarm.soundNameRaw
        existing.activeDaysRaw = alarm.activeDaysRaw
        save()
        if existing.isActive { startMonitoring(existing) }
    }

    func delete(alarm: GeoAlarm) {
        stopMonitoring(alarm)
        modelContext?.delete(alarm)
        alarms.removeAll { $0.id == alarm.id }
        save()
    }

    func delete(at offsets: IndexSet) {
        offsets.forEach { stopMonitoring(alarms[$0]) }
        offsets.forEach { modelContext?.delete(alarms[$0]) }
        for index in offsets.reversed() {
            alarms.remove(at: index)
        }
        save()
    }

    func toggleActive(_ alarm: GeoAlarm) {
        alarm.state = alarm.isActive ? .inactive : .active
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
            fireNotification(for: alarms[index])
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
            print("🔄 Repeating alarm re-armed: \(alarms[index].name)")
        }
    }

    // MARK: - Local notification

    private func fireNotification(for alarm: GeoAlarm) {
        let content = UNMutableNotificationContent()
        content.title = "📍 \(alarm.name)"
        content.body = alarm.note.isEmpty
            ? "\(alarm.regionEvent.rawValue) detected."
            : alarm.note
        content.sound = alarm.notificationSound.unSound
        content.userInfo = ["alarmID": alarm.id.uuidString]

        content.categoryIdentifier = NotificationCategory.geoAlarm

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
    }

    // MARK: - Time window guard

    /// Schedules a timer that fires at windowEnd.
    /// If the alarm is still active or triggered at that point (user hasn't left
    /// the region), it is automatically deactivated — satisfying the guard condition.
    private func scheduleWindowEndGuard(for alarm: GeoAlarm) {
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
    func snooze(_ alarm: GeoAlarm, minutes: Int = 10) {
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
            CrashReporter.record(error, context: "SwiftData.save")
        }
        // Push latest state to paired Apple Watch after every save.
        WatchConnectivityManager.shared.updateWatch(with: alarms)
    }

    private func load() {
        guard let context = modelContext else { return }
        do {
            alarms = try context.fetch(
                FetchDescriptor<GeoAlarm>(sortBy: [SortDescriptor(\.name)])
            )
            CrashReporter.setKey("alarmCount", value: alarms.count)
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

        Task { @MainActor in
            switch action {
            case NotificationAction.snooze10:
                if let id = alarmID,
                   let alarm = alarms.first(where: { $0.id.uuidString == id }) {
                    snooze(alarm, minutes: 10)
                    print("😴 Snoozed: \(alarm.name) for 10 min")
                }
            default:
                break   // Dismiss and default tap need no extra handling
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
