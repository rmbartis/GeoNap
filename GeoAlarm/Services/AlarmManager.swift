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
import UIKit
import AVFoundation

@MainActor
final class AlarmManager: NSObject, ObservableObject {

    // MARK: - Published state
    @Published private(set) var alarms: [NapAlarm] = []

    /// Set when an alarm fires — triggers AlarmFiringView in ContentView.
    /// Cleared when the user slides to dismiss, snoozes, or taps Dismiss on the notification.
    @Published var firingAlarm: NapAlarm? = nil

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

    // MARK: - Background task
    // Keeps the app alive long enough for the AVAudioSession to start when the
    // geo-fence fires with the screen locked. Once AVAudioPlayer is playing,
    // UIBackgroundModes:audio sustains it on its own — this task just bridges
    // the gap between wake-up and the first audio frame.
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

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
        // "Stop Alarm" is listed FIRST so it's the prominent button on the
        // notification — including on the CarPlay screen, where the driver taps it
        // to silence the looping alarm without unlocking or opening the phone.
        // It runs in the background (no .foreground) so silencing is instant and
        // safe while driving; the handler in didReceive stops the audio.
        let stopAction = UNNotificationAction(
            identifier: NotificationAction.dismiss,
            title: "Stop Alarm",
            options: [.destructive]
        )
        let snoozeAction = UNNotificationAction(
            identifier: NotificationAction.snooze10,
            title: "Snooze 10 min",
            options: []
        )

        // Single category for all alarms — contact messaging is triggered automatically,
        // not via a user-facing action button.
        // .customDismissAction also routes a swipe-away to our handler so the audio
        // stops if the driver dismisses the banner instead of tapping Stop Alarm.
        let standardCategory = UNNotificationCategory(
            identifier: NotificationCategory.geoAlarm,
            actions: [stopAction, snoozeAction],
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
        // Capture the chosen sound BEFORE handing the object to the SwiftData context.
        // When context.insert() registers a newly-created model, its context-managed
        // backing store can be initialised from the class-level property default
        // ("default") rather than the value set in NapAlarm's custom init.
        // Re-applying the captured value after insert ensures SwiftData tracks it as
        // a mutation and persists the user's selection — the same fix that resolved
        // the identical symptom for the edit path in update(alarm:).
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
        refreshKeepAlive()
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
        refreshKeepAlive()
    }

    func delete(alarm: NapAlarm) {
        DebugLogger.shared.log("Alarm deleted: '\(alarm.name)'", category: "AlarmManager")
        GeoAlarmScheduler.cancel(id: alarm.id)   // dismiss any presented AlarmKit alarm
        stopMonitoring(alarm)
        SpotlightManager.shared.deindex(alarm)
        modelContext?.delete(alarm)
        alarms.removeAll { $0.id == alarm.id }
        save()
        refreshKeepAlive()
    }

    func delete(at offsets: IndexSet) {
        offsets.forEach { stopMonitoring(alarms[$0]) }
        offsets.forEach { SpotlightManager.shared.deindex(alarms[$0]) }
        offsets.forEach { modelContext?.delete(alarms[$0]) }
        for index in offsets.reversed() {
            alarms.remove(at: index)
        }
        save()
        refreshKeepAlive()
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
        deactivateExpiredWindowAlarms()   // backstop: clean up alarms whose window ended while suspended
        locationManager?.stopMonitoringAll()
        alarms.filter(\.isActive).forEach { startMonitoring($0) }
        refreshKeepAlive()
    }

    /// Start or stop the audio keep-alive session based on whether any alarm is
    /// armed. The keep-alive holds the audio session open so a background-triggered
    /// alarm can sound without iOS blocking a fresh session start (OSStatus -50).
    /// Must be (re)evaluated whenever the set of active alarms changes.
    private func refreshKeepAlive() {
        if activeAlarmCount > 0 {
            AlarmAudioPlayer.shared.beginKeepAlive()
        } else {
            AlarmAudioPlayer.shared.endKeepAlive()
        }
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
            // AlarmKit migration (iOS 26+): present the alarm via the system alarm
            // engine instead of the legacy notification + AVAudioPlayer loop. The
            // OS owns the lock-screen Stop/Snooze UI and the alert cuts through
            // silent mode / Focus. Capture Sendable primitives before the Task —
            // NapAlarm (SwiftData model) is not Sendable.
            let firingID    = alarms[index].id
            let firingTitle = alarms[index].name
            // System presets (vibrate/default) → nil → AlarmKit default sound;
            // a bundled .wav passes its filename (installed in Library/Sounds).
            let firingSound = alarms[index].notificationSound
            let firingSoundName: String? = firingSound.isSystem ? nil : firingSound.id
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

    // MARK: - Local notification

    /// Builds the alarm notification content (title, body, sound, category, userInfo).
    /// Shared by the initial geo-fence fire and the snooze re-ring so they look and
    /// behave identically.
    private func makeAlarmContent(for alarm: NapAlarm) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = "📍 \(alarm.name)"
        content.body = alarm.note.isEmpty
            ? "\(alarm.regionEvent.rawValue) detected."
            : alarm.note
        content.sound = alarm.notificationSound.unSound
        // Time Sensitive lets the banner + sound break through Focus / Do Not
        // Disturb — including the Driving Focus that iOS auto-enables when the
        // phone connects to CarPlay. Without this, a default-level notification
        // is silently suppressed on CarPlay (no banner, no notification sound),
        // which is the CarPlay-only "no visual notification" symptom. No
        // entitlement required. (Upgrade to .critical only once Apple grants the
        // Critical Alerts entitlement, which also bypasses the ringer switch.)
        content.interruptionLevel = .timeSensitive
        content.categoryIdentifier = NotificationCategory.geoAlarm
        content.userInfo = buildNotifyUserInfo(for: alarm)
        return content
    }

    private func fireNotification(for alarm: NapAlarm) {
        let request = UNNotificationRequest(
            identifier: alarm.id.uuidString,
            content: makeAlarmContent(for: alarm),
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("❌ Notification failed: \(error.localizedDescription)")
                DebugLogger.shared.log("Notification delivery failed: \(error.localizedDescription)", category: "AlarmManager")
            }
        }
    }

    // MARK: - CarPlay audible-repeat fallback
    //
    // On CarPlay with NO other audio playing, iOS blocks our looping AVAudioPlayer
    // from being audible (the app lacks the CarPlay audio entitlement). The only
    // sound iOS will play to the car in that case is a NOTIFICATION's own sound.
    // Since a notification sound plays once (not looped), we schedule a short
    // series of follow-up notifications so the alarm tone RE-RINGS through the car
    // until the user acts. These are cancelled the moment the alarm is stopped.

    private static let carPlayRepeatCount = 6
    private static let carPlayRepeatInterval: TimeInterval = 6   // seconds between rings

    private func carPlayRepeatID(_ id: UUID, _ i: Int) -> String { "\(id.uuidString)-carplay-\(i)" }

    /// Schedules repeat alarm-sound notifications ONLY when needed: the current
    /// output is CarPlay and nothing else is playing (so our loop is inaudible).
    private func scheduleCarPlayAudioRepeatsIfNeeded(for alarm: NapAlarm) {
        let session = AVAudioSession.sharedInstance()
        let onCarPlay = session.currentRoute.outputs.contains { $0.portType == .carAudio }
        guard onCarPlay, !session.isOtherAudioPlaying else { return }
        guard alarm.notificationSound.unSound != nil else { return }   // vibrate-only: no sound to repeat

        let center = UNUserNotificationCenter.current()
        for i in 1...Self.carPlayRepeatCount {
            let content = UNMutableNotificationContent()
            content.title = "📍 \(alarm.name)"
            content.body = alarm.note.isEmpty ? "\(alarm.regionEvent.rawValue) detected." : alarm.note
            content.sound = alarm.notificationSound.unSound
            content.interruptionLevel = .timeSensitive
            content.categoryIdentifier = NotificationCategory.geoAlarm
            content.userInfo = ["alarmID": alarm.id.uuidString]
            let trigger = UNTimeIntervalNotificationTrigger(
                timeInterval: Self.carPlayRepeatInterval * Double(i), repeats: false)
            center.add(UNNotificationRequest(identifier: carPlayRepeatID(alarm.id, i),
                                             content: content, trigger: trigger))
        }
        DebugLogger.shared.log("CarPlay silent-car: scheduled \(Self.carPlayRepeatCount) audio-repeat notifications for '\(alarm.name)'", category: "AlarmManager")
    }

    /// Cancels any pending/delivered CarPlay repeat notifications for an alarm.
    private func cancelCarPlayAudioRepeats(forAlarmID idString: String) {
        guard let uuid = UUID(uuidString: idString) else { return }
        let ids = (1...Self.carPlayRepeatCount).map { carPlayRepeatID(uuid, $0) }
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ids)
        center.removeDeliveredNotifications(withIdentifiers: ids)
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

        // Persist for NotifyContactsIntent — lets a Shortcuts Personal Automation
        // read the data and send SMS via "Send Message" without a compose sheet.
        // Persist body for NotifyContactsIntent — lets a Shortcuts Personal Automation
        // read the message and send SMS via "Send Message" without a compose sheet.
        UserDefaults.standard.set(body, forKey: AutoNotifyDefaultsKey.pendingBody)

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

    // MARK: - Alarm ringing (looping sound + full-screen UI)

    private func startAlarmRinging(for alarm: NapAlarm) {
        // Request a background task BEFORE starting the audio session.
        // When the geo-fence fires with the screen locked, the app is in
        // .background and iOS can suspend it at any moment. The background
        // task gives us ~30 s of guaranteed execution time — enough for
        // AVAudioPlayer to open the session and play the first audio frame.
        // After that, UIBackgroundModes:audio sustains playback on its own.
        beginAudioBackgroundTask()
        // Start the looping sound (continues in background via UIBackgroundModes: audio).
        AlarmAudioPlayer.shared.play(sound: alarm.notificationSound)
        // On CarPlay with no other audio, the loop above is inaudible; fall back to
        // repeating notification sounds (the only audio iOS plays to the car there).
        scheduleCarPlayAudioRepeatsIfNeeded(for: alarm)
        // Show AlarmFiringView — ContentView observes this property.
        firingAlarm = alarm
        DebugLogger.shared.log("Alarm ringing started: '\(alarm.name)'", category: "AlarmManager")
    }

    /// Called by the slide-to-dismiss gesture in AlarmFiringView.
    func dismissFiringAlarm() {
        AlarmAudioPlayer.shared.stop()
        endAudioBackgroundTask()
        if let id = firingAlarm?.id.uuidString {
            cancelCarPlayAudioRepeats(forAlarmID: id)
            cancelSnoozeReFire(forAlarmID: id)
        }
        firingAlarm = nil
        DebugLogger.shared.log("Alarm dismissed by user (slider)", category: "AlarmManager")
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

    /// Reliable backstop for the time-window cleanup above. The in-memory timer in
    /// scheduleWindowEndGuard(...) does not run once the app is suspended or
    /// terminated in the background, so a windowed alarm that fired could stay
    /// "triggered" and keep its region monitored past the window's end. This sweep
    /// deactivates any windowed alarm that has fired (state == .triggered) and
    /// whose active window has since ended, and runs whenever the app re-registers
    /// regions, handles a region event, or returns to the foreground.
    ///
    /// Note: this is cleanup only. Whether an alarm can FIRE is already gated every
    /// time by isWithinWindow() in handleRegionEvent, so the time window is enforced
    /// regardless of whether this sweep has run. It deliberately ignores .active
    /// alarms so a not-yet-fired daily windowed alarm is never disabled just because
    /// the app happens to be open outside its window.
    func deactivateExpiredWindowAlarms() {
        var changed = false
        for alarm in alarms where alarm.hasTimeWindow && alarm.state == .triggered {
            guard !alarm.isWithinWindow() else { continue }
            alarm.state = .inactive
            stopMonitoring(alarm)
            changed = true
            DebugLogger.shared.log("Window closed (sweep): '\(alarm.name)' auto-deactivated past window end", category: "AlarmManager")
        }
        if changed { save(); refreshKeepAlive() }
    }

    // MARK: - Background task helpers

    private func beginAudioBackgroundTask() {
        endAudioBackgroundTask()
        backgroundTask = UIApplication.shared.beginBackgroundTask(
            withName: "GeoAlarmAudioPlayback"
        ) { [weak self] in
            // Expiry: iOS is about to suspend the app.
            // Do NOT stop the audio player here — once AVAudioPlayer is running
            // with .playback category, UIBackgroundModes:audio sustains it on its
            // own without needing the background task. Stopping here would silence
            // the looping alarm on the lock screen after ~30 s.
            // Just release the task token so iOS doesn't terminate us for holding it.
            self?.endAudioBackgroundTask()
        }
    }

    /// Wrapper so the expiry handler can call stop without triggering
    /// the full dismissFiringAlarm flow (which touches @Published state).
    private func AlarmAudioPlayer_stop() {
        AlarmAudioPlayer.shared.stop()
    }

    private func endAudioBackgroundTask() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }

    // MARK: - Snooze

    /// Suppress a triggered alarm and re-arm it after `minutes` minutes.
    private func snoozeID(_ id: UUID) -> String { "\(id.uuidString)-snooze" }

    /// In-app timers that re-fire snoozed alarms. Kept so they can be cancelled
    /// when the user stops the alarm or re-snoozes.
    private var snoozeWorkItems: [UUID: DispatchWorkItem] = [:]

    func snooze(_ alarm: NapAlarm, minutes: Int = 10) {
        AlarmAudioPlayer.shared.stop()      // stops the alarm; resumes the silent keep-alive
        endAudioBackgroundTask()
        cancelCarPlayAudioRepeats(forAlarmID: alarm.id.uuidString)
        cancelSnoozeReFire(forAlarmID: alarm.id.uuidString)   // clear any prior snooze for this alarm
        firingAlarm = nil
        alarm.state = .snoozed
        save()
        DebugLogger.shared.log("Alarm snoozed \(minutes) min: '\(alarm.name)'", category: "AlarmManager")

        // Keep the silent keep-alive session running through the snooze so the app
        // stays alive in the background. That lets the SAME looping-alarm path the
        // geo-fence uses run when the snooze expires — full audio through the lock
        // screen, not just a one-shot notification sound.
        AlarmAudioPlayer.shared.beginKeepAlive()

        let alarmID = alarm.id
        let interval = max(1, Double(minutes) * 60)

        // PRIMARY: an in-app timer that restarts the full looping alarm. This runs
        // because the keep-alive audio keeps the app alive in the background.
        let work = DispatchWorkItem { [weak self] in
            self?.handleSnoozeReFire(alarmID: alarmID.uuidString)
        }
        snoozeWorkItems[alarmID] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + interval, execute: work)

        // FALLBACK: a scheduled notification, fired 2 s later, in case the app was
        // suspended/terminated before the timer could run (e.g. the audio session
        // was interrupted). The timer cancels this notification when it fires; if
        // the timer couldn't run, the notification rings the alarm and restarts the
        // loop when the app is next foregrounded or opened.
        let content = makeAlarmContent(for: alarm)
        var info = content.userInfo
        info["snoozeReFire"] = true
        content.userInfo = info
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval + 2, repeats: false)
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: snoozeID(alarmID), content: content, trigger: trigger)) { error in
            if let error = error {
                DebugLogger.shared.log("Snooze re-ring fallback scheduling FAILED: \(error.localizedDescription)", category: "AlarmManager")
            }
        }
    }

    /// Restarts the full looping alarm when a snooze expires — via the in-app timer
    /// (app alive) or the fallback notification (app was suspended). The state guard
    /// ensures it runs only once even if both paths fire.
    private func handleSnoozeReFire(alarmID: String?) {
        guard let id = alarmID,
              let alarm = alarms.first(where: { $0.id.uuidString == id }),
              alarm.state == .snoozed else { return }
        cancelSnoozeReFire(forAlarmID: id)   // stop the other re-fire mechanism from also firing
        alarm.state = .triggered
        alarm.lastTriggeredAt = Date()
        save()
        startAlarmRinging(for: alarm)   // looping audio + firing view + CarPlay repeats
        DebugLogger.shared.log("Snooze re-fire: '\(alarm.name)' ringing again", category: "AlarmManager")
    }

    /// Cancels a pending snooze re-fire (both the in-app timer and the fallback
    /// notification) — when the user stops/dismisses the alarm or re-snoozes.
    private func cancelSnoozeReFire(forAlarmID idString: String) {
        guard let uuid = UUID(uuidString: idString) else { return }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [snoozeID(uuid)])
        snoozeWorkItems[uuid]?.cancel()
        snoozeWorkItems[uuid] = nil
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
        let isSnoozeReFire = response.notification.request.content.userInfo["snoozeReFire"] as? Bool ?? false

        Task { @MainActor in
            switch action {
            case NotificationAction.snooze10:
                if let id = alarmID,
                   let alarm = alarms.first(where: { $0.id.uuidString == id }) {
                    snooze(alarm, minutes: 10)   // also stops audio + clears firingAlarm
                    print("😴 Snoozed: \(alarm.name) for 10 min")
                    DebugLogger.shared.log("Alarm snoozed 10 min via notification action: '\(alarm.name)'", category: "AlarmManager")
                }

            case NotificationAction.dismiss,
                 UNNotificationDismissActionIdentifier:
                // User tapped Stop Alarm or swiped away the notification —
                // stop the looping sound and clear the full-screen alarm view.
                AlarmAudioPlayer.shared.stop()
                endAudioBackgroundTask()
                if let id = alarmID {
                    cancelCarPlayAudioRepeats(forAlarmID: id)
                    cancelSnoozeReFire(forAlarmID: id)   // don't let it ring again after Stop
                }
                firingAlarm = nil
                DebugLogger.shared.log("Alarm dismissed via notification action", category: "AlarmManager")

            default:
                // UNNotificationDefaultActionIdentifier — user tapped the banner to open the app.
                // If this is a snooze re-ring the user opened, restart the full alarm.
                if isSnoozeReFire { handleSnoozeReFire(alarmID: alarmID) }
                // Otherwise the original alarm's AlarmFiringView is already showing
                // (firingAlarm is set) and the user slides to dismiss from there.
                //
                // Recover Auto-Notify contact data so the SMS compose sheet appears on relaunch.
                if let phones = notifyPhones, !phones.isEmpty {
                    pendingContactMessage = ContactMessage(phones: phones, body: notifyBody)
                    DebugLogger.shared.log("Auto-Notify: SMS compose queued from notification tap (\(phones.count) contact(s))", category: "AlarmManager")
                }
            }
            completionHandler()
        }
    }

    /// Show banner + play sound even when the app is in the foreground.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // If a snooze re-ring is delivered while the app is foregrounded, restart
        // the full looping alarm + firing screen (a scheduled notification alone
        // only plays its sound once).
        let isSnoozeReFire = notification.request.content.userInfo["snoozeReFire"] as? Bool ?? false
        let alarmID = notification.request.content.userInfo["alarmID"] as? String
        if isSnoozeReFire {
            Task { @MainActor in self.handleSnoozeReFire(alarmID: alarmID) }
        }
        completionHandler([.banner, .sound, .badge])
    }
}
