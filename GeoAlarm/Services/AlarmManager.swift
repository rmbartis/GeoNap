// AlarmManager.swift
// Owns the list of NapAlarms, coordinates region monitoring via LocationManager,
// and presents alarms via AlarmKit (GeoAlarmScheduler) on region events.
// Persists via SwiftData.
//
// AlarmKit migration: the legacy alerting engine — local notifications, the
// looping AVAudioPlayer, the background-audio keep-alive session, CarPlay
// audio-repeat notifications, the in-app AlarmFiringView, and notification-based
// snooze — has been removed. AlarmKit now owns all alarm presentation, sound,
// lock-screen UI, silent-mode/Focus break-through, and snooze. The geofence
// trigger (LocationManager region events) is unchanged. Auto-Notify SMS is
// preserved and fires from `queueAutoNotify` at the moment an alarm triggers.

import Foundation
import CoreLocation
import SwiftData
import CoreData
import Combine
import MessageUI
import UIKit

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
                radius: alarm.radius,
                triggerMode: alarm.triggerMode, leadTimeMinutes: alarm.leadTimeMinutes,
                regionEvent: alarm.regionEvent,
                state: .inactive, note: alarm.note,
                isRepeating: alarm.isRepeating,
                hasTimeWindow: alarm.hasTimeWindow,
                windowStart: alarm.windowStart, windowEnd: alarm.windowEnd,
                activeDays: alarm.activeDays,
                notificationSound: alarm.notificationSound
            )
            DebugLogger.shared.log("Alarm '\(alarm.name)' inserted as INACTIVE — region monitoring limit reached (\(Self.regionMonitoringLimit))", category: "AlarmManager")
        }
        // Capture the chosen sound BEFORE handing the object to the SwiftData context.
        // When context.insert() registers a newly-created model, its context-managed
        // backing store can be initialised from the class-level property default
        // ("default") rather than the value set in NapAlarm's custom init.
        // Re-applying the captured value after insert ensures SwiftData tracks it as
        // a mutation and persists the user's selection.
        let soundRaw = toInsert.soundNameRaw
        modelContext?.insert(toInsert)
        if toInsert.soundNameRaw != soundRaw {
            DebugLogger.shared.log("⚠️ SwiftData backing-store init reset soundNameRaw '\(toInsert.soundNameRaw)' → reapplying '\(soundRaw)'", category: "AlarmManager")
        }
        toInsert.soundNameRaw = soundRaw
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
    func update(alarm: NapAlarm) {
        guard let existing = alarms.first(where: { $0.id == alarm.id }) else {
            print("[AlarmManager] update(alarm:) called with unknown alarm ID \(alarm.id) — ignored")
            return
        }
        stopMonitoring(existing)
        existing.name              = alarm.name
        existing.latitude          = alarm.latitude
        existing.longitude         = alarm.longitude
        existing.radius            = alarm.radius
        existing.triggerMode       = alarm.triggerMode
        existing.leadTimeMinutes   = alarm.leadTimeMinutes
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
        GeoAlarmScheduler.cancel(id: alarm.id)   // dismiss any presented AlarmKit alarm
        stopMonitoring(alarm)
        SpotlightManager.shared.deindex(alarm)
        modelContext?.delete(alarm)
        alarms.removeAll { $0.id == alarm.id }
        save()
    }

    func delete(at offsets: IndexSet) {
        offsets.forEach { GeoAlarmScheduler.cancel(id: alarms[$0].id) }
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
        // Inner ring: distance alarms fire on it directly; time alarms use it as the
        // proximity backstop if GPS/ETA can't fire (tunnels, lost fixes).
        locationManager?.startMonitoring(region: alarm.clRegion)
        // Time alarms additionally monitor an outer "warm-up" ring; entering it
        // starts continuous-GPS ETA tracking for the final approach.
        // NOTE: time alarms consume TWO of iOS's 20 region slots.
        if alarm.triggerMode == .time {
            locationManager?.startMonitoring(region: alarm.outerWarmupRegion)
        }
    }

    private func stopMonitoring(_ alarm: NapAlarm) {
        locationManager?.stopMonitoring(region: alarm.clRegion)
        if alarm.triggerMode == .time {
            locationManager?.stopMonitoring(region: alarm.outerWarmupRegion)
            stopETATracking(alarm.id)
        }
    }

    /// Re-register all active alarms — call on launch or after permission grant.
    func reregisterAllRegions() {
        deactivateExpiredWindowAlarms()   // backstop: clean up alarms whose window ended while suspended
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
        locationManager?.onLocationUpdate = { [weak self] loc in
            self?.handleLocationUpdate(loc)
        }
    }

    // MARK: - Time-based (ETA) tracking

    /// Per-alarm ETA estimators, keyed by alarm id. Non-empty only while one or
    /// more time-based alarms are inside their outer warm-up ring (final approach).
    private var etaEstimators: [UUID: ETAEstimator] = [:]

    /// Begin continuous-GPS ETA tracking for a time-based alarm whose outer ring
    /// was just entered.
    private func beginETATracking(_ alarm: NapAlarm) {
        guard etaEstimators[alarm.id] == nil else { return }   // already tracking
        etaEstimators[alarm.id] = ETAEstimator()
        locationManager?.startContinuousUpdates()
        DebugLogger.shared.log("⏱️ ETA tracking started for '\(alarm.name)' — entered warm-up ring (lead=\(alarm.leadTimeMinutes)m)", category: "AlarmManager")
    }

    private func stopETATracking(_ id: UUID) {
        guard etaEstimators[id] != nil else { return }
        etaEstimators[id] = nil
        if etaEstimators.isEmpty { locationManager?.stopContinuousUpdates() }
    }

    /// Feed every fix into the active estimators and fire when ETA ≤ lead time.
    private func handleLocationUpdate(_ loc: CLLocation) {
        guard !etaEstimators.isEmpty else { return }
        for id in Array(etaEstimators.keys) {
            guard var est = etaEstimators[id],
                  let alarm = alarms.first(where: { $0.id == id }) else { stopETATracking(id); continue }
            est.add(loc)
            etaEstimators[id] = est
            guard alarm.isActive, alarm.isWithinWindow() else { continue }
            if est.shouldFire(to: alarm.coordinate, leadTimeMinutes: alarm.leadTimeMinutes) {
                fireTimeBased(alarm, eta: est.eta(to: alarm.coordinate))
            }
        }
    }

    /// Fire a time-based alarm from the ETA path (mirrors the region-event fire).
    private func fireTimeBased(_ alarm: NapAlarm, eta: TimeInterval?) {
        alarm.state = .triggered
        alarm.lastTriggeredAt = Date()
        alarm.triggerCount += 1
        let etaStr = eta.map { "\(Int($0))s" } ?? "n/a"
        CrashReporter.log("Alarm triggered (time-based): \(alarm.name) ETA=\(etaStr)")
        DebugLogger.shared.log("🔔 Alarm TRIGGERED (time-based): '\(alarm.name)' ETA≈\(etaStr) lead=\(alarm.leadTimeMinutes)m", category: "AlarmManager")
        let firingID = alarm.id
        let firingTitle = alarm.name
        let firingSoundName = alarm.notificationSound.alarmKitSoundName
        Task { await GeoAlarmScheduler.fire(id: firingID, title: firingTitle, soundName: firingSoundName) }
        queueAutoNotify(for: alarm)
        scheduleWindowEndGuard(for: alarm)
        save()
        // Done: tear down this alarm's rings + tracking (non-repeating).
        stopMonitoring(alarm)
        stopETATracking(alarm.id)
    }

    func handleRegionEvent(regionID: String, event: RegionEvent) {

        // Outer warm-up ring of a time-based alarm: entering it starts continuous
        // ETA tracking. It never fires the alarm itself (the ETA loop / inner ring do).
        if regionID.hasSuffix(NapAlarm.warmupRegionSuffix) {
            let baseID = String(regionID.dropLast(NapAlarm.warmupRegionSuffix.count))
            if event == .onEntry,
               let alarm = alarms.first(where: { $0.id.uuidString == baseID && $0.isActive && $0.triggerMode == .time }) {
                beginETATracking(alarm)
            }
            return
        }

        // Opportunistic backstop: any region event means the app is awake, so
        // clean up windowed alarms whose window ended while we were suspended.
        deactivateExpiredWindowAlarms()

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
            // AlarmKit (iOS 26+): present the alarm via the system alarm engine. The
            // OS owns the lock-screen Stop/Snooze UI and the alert cuts through
            // silent mode / Focus. Capture Sendable primitives before the Task —
            // NapAlarm (SwiftData model) is not Sendable.
            let firingID    = alarms[index].id
            let firingTitle = alarms[index].name
            // Map the selection to AlarmKit's sound: bundled .wav → its filename,
            // "default"/"critical" → nil (AlarmKit default tone), and "vibrate" →
            // a silent tone so the alarm only vibrates. (Previously every system
            // preset, including vibrate, collapsed to nil → audible default sound.)
            let firingSound = alarms[index].notificationSound
            let firingSoundName: String? = firingSound.alarmKitSoundName
            Task { await GeoAlarmScheduler.fire(id: firingID, title: firingTitle, soundName: firingSoundName) }
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
            GeoAlarmScheduler.cancel(id: alarms[index].id)   // clear the prior AlarmKit alert before re-arming
            alarms[index].state = .active
            save()
            startMonitoring(alarms[index])   // keep iOS monitoring the region
            DebugLogger.shared.log("🔄 Repeating alarm re-armed: '\(alarms[index].name)'", category: "AlarmManager")
            print("🔄 Repeating alarm re-armed: \(alarms[index].name)")
        }
    }

    // MARK: - Auto-Notify (SMS to saved contacts)

    /// Sets `pendingContactMessage` immediately when an alarm fires so the SMS
    /// compose sheet appears as soon as the app is (or comes) in the foreground.
    private func queueAutoNotify(for alarm: NapAlarm) {
        let phones = alarm.notifyContactList.filter { !$0.isEmail }.map { $0.value }
        guard alarm.notifyContact, !phones.isEmpty else { return }

        let direction = alarm.regionEvent == .onEntry ? "Arrival" : "Departure"
        let verb      = alarm.regionEvent == .onEntry ? "arrived at" : "departed from"
        let timeStr   = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .short)
        var body = "[\(direction)] I \(verb) \(alarm.name) at \(timeStr)."
        if !alarm.note.isEmpty { body += " \(alarm.note)" }

        // Persist body + fire time for NotifyContactsIntent — lets the Shortcuts
        // "When GeoNap Is Opened" automation read the message and send SMS without
        // a compose sheet. The timestamp drives the intent's freshness guard.
        let defaults = UserDefaults.standard
        defaults.set(body, forKey: AutoNotifyDefaultsKey.pendingBody)
        defaults.set(Date().timeIntervalSince1970, forKey: AutoNotifyDefaultsKey.pendingBodyTimestamp)

        // If the user runs the hands-free Shortcuts automation, suppress the in-app
        // pre-filled compose sheet so the message isn't both auto-sent AND shown.
        // Otherwise queue the one-tap compose sheet for the next foreground.
        let automationActive = defaults.bool(forKey: AppStorageKey.autoSMSAutomationEnabled)
        if automationActive {
            DebugLogger.shared.log("Auto-Notify: body queued for Shortcuts automation; in-app sheet suppressed (\(phones.count) contact(s))", category: "AlarmManager")
        } else {
            pendingContactMessage = ContactMessage(phones: phones, body: body)
            DebugLogger.shared.log("Auto-Notify: SMS compose queued at alarm fire (\(phones.count) contact(s))", category: "AlarmManager")
        }
    }

    /// Builds an Auto-Notify payload (alarmID + optional phones/body).
    /// Retained for the Shortcuts NotifyContactsIntent and unit tests.
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
            DebugLogger.shared.log("Auto-Notify: \(phones.count) SMS contact(s) embedded for '\(alarm.name)'", category: "AlarmManager")
        }
        return userInfo
    }

    /// Recovers Auto-Notify contact data from a payload dictionary and sets
    /// `pendingContactMessage`. Retained for unit tests / Shortcuts integration.
    func recoverAutoNotify(from userInfo: [AnyHashable: Any]) {
        let body = userInfo["notifyBody"] as? String ?? ""
        if let phones = userInfo["notifyPhones"] as? [String], !phones.isEmpty {
            pendingContactMessage = ContactMessage(phones: phones, body: body)
            DebugLogger.shared.log("Auto-Notify: SMS compose queued from payload (\(phones.count) contact(s))", category: "AlarmManager")
        }
    }

    // MARK: - Time window guard

    /// Schedules a timer that fires at windowEnd. If the alarm is still active or
    /// triggered then, it is automatically deactivated.
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

    /// Reliable backstop for the time-window cleanup: deactivates any windowed
    /// alarm that fired (state == .triggered) and whose window has since ended.
    /// Runs on re-register, region events, and foregrounding.
    func deactivateExpiredWindowAlarms() {
        var changed = false
        for alarm in alarms where alarm.hasTimeWindow && alarm.state == .triggered {
            guard !alarm.isWithinWindow() else { continue }
            alarm.state = .inactive
            stopMonitoring(alarm)
            changed = true
            DebugLogger.shared.log("Window closed (sweep): '\(alarm.name)' auto-deactivated past window end", category: "AlarmManager")
        }
        if changed { save() }
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
            SpotlightManager.shared.reindexAll(alarms)
        } catch {
            print("❌ SwiftData load failed: \(error.localizedDescription)")
            CrashReporter.record(error, context: "SwiftData.load")
            alarms = []
        }
    }
}
