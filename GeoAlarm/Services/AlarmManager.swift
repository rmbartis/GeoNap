// Copyright © 2026 Robert Bartis. All rights reserved.

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

    // MARK: - Free-tier alarm cap (added 2026-07-11)

    /// Free tier is capped at one active alarm (see monetization-tier-pricing
    /// memory). Silver+ removes this cap entirely — only the iOS
    /// `regionMonitoringLimit` above still applies from that point on.
    static let freeTierActiveAlarmLimit = 1

    /// True when a Free-tier device already has its one allowed active alarm
    /// — block adding another until the user upgrades or disables the
    /// existing one. Always false at Silver+, regardless of count. Mirrors
    /// `isAtRegionLimit`'s naming/shape deliberately — same UX treatment
    /// (disable the "+" button, reduced opacity) applies at both call sites
    /// in ContentView.swift.
    var isAtFreeTierLimit: Bool {
        EntitlementManager.isEntitled(to: .silver) ? false : activeAlarmCount >= Self.freeTierActiveAlarmLimit
    }

    // MARK: - CRUD

    func add(alarm: NapAlarm) {
        // If already at the iOS 20-region cap OR the Free-tier 1-alarm cap,
        // insert as inactive so monitoring isn't attempted. The user can
        // enable it after disabling another alarm (or, for the tier cap,
        // after upgrading).
        var toInsert = alarm
        if alarm.isActive && (isAtRegionLimit || isAtFreeTierLimit) {
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
                notificationSound: alarm.notificationSound,
                calendarEventID: alarm.calendarEventID,
                deadReckoningEnabled: alarm.deadReckoningEnabled
            )
            let reason = isAtRegionLimit
                ? "region monitoring limit reached (\(Self.regionMonitoringLimit))"
                : "Free-tier active alarm limit reached (\(Self.freeTierActiveAlarmLimit))"
            DebugLogger.shared.log("Alarm '\(alarm.name)' inserted as INACTIVE — \(reason)", category: "AlarmManager")
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
        // Append BEFORE save() — save() reads self.alarms and hands it to
        // WatchConnectivityManager.updateWatch(with:), so if the new alarm
        // isn't in the array yet when save() runs, the Watch push silently
        // omits it entirely (not filtered out — just never included). This
        // is why editing an existing alarm always synced to the Watch but
        // creating a brand-new one never did: update(alarm:) mutates an
        // object that's already array-resident before calling save(), but
        // add(alarm:) was appending after. Found 2026-07-11 debugging a
        // Watch sync gap — see NapStopWatch Watch App/WATCH_SETUP.md.
        alarms.append(toInsert)
        save()
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
        existing.deadReckoningEnabled = alarm.deadReckoningEnabled
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
            // If we're ALREADY inside the outer ring (the alarm was created close to
            // the destination, the ring is large, or we relaunched mid-trip), iOS
            // delivers NO "entered" event — so ETA tracking would never start and the
            // alarm would fall through to the 200 m inner backstop (firing ~seconds
            // out instead of the requested lead time). Start tracking now in that case.
            if Self.isAlreadyInsideWarmupRing(alarm: alarm, currentLocation: locationManager?.currentLocation) {
                beginETATracking(alarm)
            }
        }
        // Platinum-tier Live Activity (see LiveActivityManager.swift) — silent
        // no-op below Platinum or if the system declined. Distance-mode alarms
        // have no other reason to run continuous GPS updates, so only
        // request them here if a Live Activity actually started; time-mode
        // alarms' own ETA tracking already requests continuous updates
        // separately (see beginETATracking above) — liveActivityTrackedIDs
        // and etaEstimators both feed the same combined stop condition in
        // stopMonitoring/stopETATracking so neither tears down updates the
        // other still needs.
        if LiveActivityManager.shared.start(for: alarm) {
            liveActivityTrackedIDs.insert(alarm.id)
            locationManager?.startContinuousUpdates()
        }
    }

    /// Alarms with a currently-running Live Activity (see
    /// LiveActivityManager.swift) — tracked separately from `etaEstimators`
    /// since a Live Activity can run for either trigger mode, but
    /// etaEstimators only ever exists for time-mode alarms inside their
    /// warm-up ring.
    private var liveActivityTrackedIDs: Set<UUID> = []

    /// Pure decision logic extracted from `startMonitoring` so it's unit
    /// testable without a real CLLocationManager: true when `currentLocation`
    /// is already within `alarm`'s outer warm-up ring radius. Returns false
    /// when there's no current fix yet (nothing to compare against).
    static func isAlreadyInsideWarmupRing(alarm: NapAlarm, currentLocation: CLLocation?) -> Bool {
        guard let here = currentLocation else { return false }
        let dest = CLLocation(latitude: alarm.latitude, longitude: alarm.longitude)
        return here.distance(from: dest) <= alarm.outerRingRadius()
    }

    private func stopMonitoring(_ alarm: NapAlarm) {
        LiveActivityManager.shared.end(alarmID: alarm.id)
        liveActivityTrackedIDs.remove(alarm.id)
        locationManager?.stopMonitoring(region: alarm.clRegion)
        if alarm.triggerMode == .time {
            locationManager?.stopMonitoring(region: alarm.outerWarmupRegion)
            stopETATracking(alarm.id)   // also re-checks the combined continuous-updates condition below
        } else if etaEstimators.isEmpty && liveActivityTrackedIDs.isEmpty {
            // A distance-mode alarm's Live Activity was the only reason
            // continuous updates were running for it — stop them now that
            // it's gone, unless some OTHER tracked alarm (time-mode ETA or
            // another Live Activity) still needs them.
            locationManager?.stopContinuousUpdates()
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
        // Dead reckoning (opt-in, per-alarm): bridges brief signal-loss gaps
        // for alarms with deadReckoningEnabled == true. See
        // docs/dead-reckoning-design.md.
        locationManager?.onLocationUnavailableChanged = { [weak self] isUnavailable in
            self?.handleLocationAvailabilityChanged(isUnavailable)
        }
    }

    // MARK: - Time-based (ETA) tracking

    /// Per-alarm ETA estimators, keyed by alarm id. Non-empty only while one or
    /// more time-based alarms are inside their outer warm-up ring (final approach).
    private var etaEstimators: [UUID: ETAEstimator] = [:]

    /// Distinguishes whether a time-based fire came from a live GPS-derived ETA
    /// or a dead-reckoning extrapolation during a signal-loss gap — logged
    /// distinctly so an "this fired too early" report is diagnosable.
    /// (docs/dead-reckoning-design.md)
    enum TimeBasedFireSource: String { case liveGPS, deadReckoning }

    /// Snapshot taken at the moment a signal-loss gap begins for a dead-reckoning-
    /// enabled alarm. Extrapolation is a straight scalar projection from this
    /// snapshot — deliberately NOT re-sampled during the gap (there's nothing to
    /// re-sample). See docs/dead-reckoning-design.md §5.
    private struct DeadReckoningSnapshot {
        let gapStartedAt: Date
        let lastDistance: CLLocationDistance
        let closingRate: Double        // m/s; may be negative (moving away)
        let lastSpeed: CLLocationSpeed
        let minSpeed: CLLocationSpeed
        let graceCap: TimeInterval
    }

    /// Per-alarm dead-reckoning state, populated only while a DR-enabled,
    /// currently-tracked alarm is bridging an active signal-loss gap.
    private var deadReckoning: [UUID: DeadReckoningSnapshot] = [:]
    private var deadReckoningTimers: [UUID: Timer] = [:]

    /// Begin continuous-GPS ETA tracking for a time-based alarm whose outer ring
    /// was just entered.
    private func beginETATracking(_ alarm: NapAlarm) {
        guard etaEstimators[alarm.id] == nil else { return }   // already tracking
        etaEstimators[alarm.id] = ETAEstimator()
        locationManager?.startContinuousUpdates()
        DebugLogger.shared.log("⏱️ ETA tracking started for '\(alarm.name)' — entered warm-up ring (lead=\(alarm.leadTimeMinutes)m)", category: "AlarmManager")
    }

    private func stopETATracking(_ id: UUID) {
        // Dead-reckoning bookkeeping must never outlive ETA tracking for this
        // alarm — clear unconditionally before the early-return below.
        deadReckoningTimers[id]?.invalidate()
        deadReckoningTimers[id] = nil
        deadReckoning[id] = nil
        guard etaEstimators[id] != nil else { return }
        etaEstimators[id] = nil
        // Combined condition (added for Live Activities, 2026-07-11): only
        // stop continuous updates once NEITHER ETA tracking NOR any Platinum
        // Live Activity still needs them — see liveActivityTrackedIDs.
        if etaEstimators.isEmpty && liveActivityTrackedIDs.isEmpty {
            locationManager?.stopContinuousUpdates()
        }
    }

    // MARK: - Dead reckoning (signal-loss bridging)

    /// Reacts to LocationManager.isLocationUnavailable transitions. Internal
    /// (not private) so the test target can drive it directly — mirrors the
    /// handleRegionEvent/handleLocationUpdate test-seam convention.
    func handleLocationAvailabilityChanged(_ isUnavailable: Bool) {
        if isUnavailable {
            beginDeadReckoningForTrackedAlarms()
        } else {
            // A fresh real fix is either already here or about to arrive via
            // handleLocationUpdate — normal ETA tracking resumes on its own.
            // Only the DR bridging state needs to be torn down.
            clearAllDeadReckoning(reason: "real fix resumed")
        }
    }

    /// Starts a bounded dead-reckoning snapshot for every currently-tracked,
    /// DR-enabled alarm that doesn't already have one in progress. Guarding on
    /// `deadReckoning[id] == nil` means a repeated/duplicate "unavailable"
    /// signal can't reset an in-progress gap's clock and extend the grace
    /// period indefinitely.
    private func beginDeadReckoningForTrackedAlarms() {
        for id in Array(etaEstimators.keys) {
            guard deadReckoning[id] == nil,
                  let alarm = alarms.first(where: { $0.id == id }),
                  alarm.deadReckoningEnabled,
                  let estimator = etaEstimators[id],
                  let lastLocation = estimator.lastLocation,
                  let closingRate = estimator.closingRate(to: alarm.coordinate),
                  let lastSpeed = estimator.averageSpeed
            else { continue }

            let dest = CLLocation(latitude: alarm.latitude, longitude: alarm.longitude)
            let snapshot = DeadReckoningSnapshot(
                gapStartedAt: Date(),
                lastDistance: lastLocation.distance(from: dest),
                closingRate: closingRate,
                lastSpeed: lastSpeed,
                minSpeed: estimator.minSpeed,
                graceCap: NapAlarm.deadReckoningGracePeriod(leadTimeMinutes: alarm.leadTimeMinutes)
            )
            deadReckoning[id] = snapshot
            DebugLogger.shared.log("🛰️ Dead reckoning gap started for '\(alarm.name)' — bridging up to \(Int(snapshot.graceCap))s", category: "AlarmManager")

            let timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
                guard let self else { return }
                Task { @MainActor in self.evaluateDeadReckoning(for: id, now: Date()) }
            }
            deadReckoningTimers[id] = timer
        }
    }

    /// Clears dead-reckoning state for every alarm. `isLocationUnavailable` is a
    /// single, app-wide flag (there's only one CLLocationManager delivering
    /// fixes), so "signal restored" is inherently a global event — this does
    /// NOT touch `etaEstimators`; live ETA tracking continues normally.
    private func clearAllDeadReckoning(reason: String) {
        guard !deadReckoning.isEmpty else { return }
        for id in Array(deadReckoning.keys) {
            deadReckoningTimers[id]?.invalidate()
            deadReckoningTimers[id] = nil
            deadReckoning[id] = nil
        }
        DebugLogger.shared.log("Dead reckoning cleared for all tracked alarms (\(reason))", category: "AlarmManager")
    }

    /// Evaluates one dead-reckoning snapshot at `now`: expires it past the grace
    /// cap (reverting to the geofence backstop), and fires the alarm if the
    /// extrapolated distance now projects an ETA within the lead time. Injectable
    /// `now` (mirrors `AddAlarmView.freshLocation`'s pattern) so tests don't
    /// depend on real wall-clock timing or a live Timer. Internal (not private)
    /// so the test target can drive it directly without waiting on the 5s ticker.
    func evaluateDeadReckoning(for id: UUID, now: Date = Date()) {
        guard let snapshot = deadReckoning[id],
              let alarm = alarms.first(where: { $0.id == id }) else {
            deadReckoningTimers[id]?.invalidate()
            deadReckoningTimers[id] = nil
            deadReckoning[id] = nil
            return
        }

        let elapsed = now.timeIntervalSince(snapshot.gapStartedAt)
        if elapsed >= snapshot.graceCap {
            DebugLogger.shared.log("⏱️ Dead reckoning grace period expired for '\(alarm.name)' — reverting to geofence backstop", category: "AlarmManager")
            deadReckoningTimers[id]?.invalidate()
            deadReckoningTimers[id] = nil
            deadReckoning[id] = nil
            return
        }

        // Stopped (or below the "moving" threshold) at the moment signal was
        // lost — extrapolating a fixed closing rate from a near-zero speed is
        // the worst-case scenario called out in the design doc. Never fire on
        // dead reckoning alone in that case; wait for a real fix or the
        // geofence backstop.
        guard snapshot.lastSpeed >= snapshot.minSpeed else { return }

        guard alarm.isActive, alarm.isWithinWindow() else { return }

        let virtualDistance = max(0, snapshot.lastDistance - snapshot.closingRate * elapsed)
        let virtualETA = virtualDistance / snapshot.lastSpeed

        if virtualETA <= Double(alarm.leadTimeMinutes) * 60 {
            fireTimeBased(alarm, eta: virtualETA, source: .deadReckoning)
        }
    }

    /// Feed every fix into the active estimators and fire when ETA ≤ lead time.
    /// Internal (not private) so the test target can drive it directly via a
    /// `simulateLocationUpdate(_:)` seam — mirrors `handleRegionEvent`, which
    /// is internal for the same reason (Bob, 2026-07-05).
    func handleLocationUpdate(_ loc: CLLocation) {
        for id in Array(etaEstimators.keys) {
            guard var est = etaEstimators[id],
                  let alarm = alarms.first(where: { $0.id == id }) else { stopETATracking(id); continue }
            est.add(loc)
            etaEstimators[id] = est
            let eta = est.eta(to: alarm.coordinate)
            LiveActivityManager.shared.update(
                alarmID: id,
                distanceRemaining: loc.distance(from: CLLocation(latitude: alarm.latitude, longitude: alarm.longitude)),
                etaSeconds: eta
            )
            guard alarm.isActive, alarm.isWithinWindow() else { continue }
            if est.shouldFire(to: alarm.coordinate, leadTimeMinutes: alarm.leadTimeMinutes) {
                fireTimeBased(alarm, eta: eta)
            }
        }

        // Distance-mode alarms with a running Live Activity have no ETA
        // estimator (ETA tracking only exists for time-mode alarms) —
        // update their live distance readout straight from this GPS fix.
        let distanceOnlyIDs = liveActivityTrackedIDs.subtracting(etaEstimators.keys)
        guard !distanceOnlyIDs.isEmpty else { return }
        for id in distanceOnlyIDs {
            guard let alarm = alarms.first(where: { $0.id == id }) else { continue }
            LiveActivityManager.shared.update(
                alarmID: id,
                distanceRemaining: loc.distance(from: CLLocation(latitude: alarm.latitude, longitude: alarm.longitude)),
                etaSeconds: nil
            )
        }
    }

    /// Fire a time-based alarm from the ETA path (mirrors the region-event fire).
    /// `source` distinguishes a live-GPS fire from a dead-reckoning fire for
    /// diagnostics (docs/dead-reckoning-design.md).
    private func fireTimeBased(_ alarm: NapAlarm, eta: TimeInterval?, source: TimeBasedFireSource = .liveGPS) {
        alarm.state = .triggered
        alarm.lastTriggeredAt = Date()
        alarm.triggerCount += 1
        let etaStr = eta.map { "\(Int($0))s" } ?? "n/a"
        CrashReporter.log("Alarm triggered (time-based, \(source.rawValue)): \(alarm.name) ETA=\(etaStr)")
        DebugLogger.shared.log("🔔 Alarm TRIGGERED (time-based, \(source.rawValue)): '\(alarm.name)' ETA≈\(etaStr) lead=\(alarm.leadTimeMinutes)m", category: "AlarmManager")
        let firingID = alarm.id
        let firingTitle = alarm.name
        let firingSoundName = alarm.notificationSound.alarmKitSoundName
        Task { await GeoAlarmScheduler.fire(id: firingID, title: firingTitle, soundName: firingSoundName) }
        queueAutoNotify(for: alarm)
        runShortcutIfConfigured(for: alarm)
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
            // Unlike fireTimeBased, this path does NOT call stopMonitoring —
            // a non-repeating alarm stays region-registered (state ==
            // .triggered, not .active) until edited/deleted, and a
            // repeating alarm needs to keep monitoring the SAME region to
            // detect the opposite-direction crossing that re-arms it below.
            // Either way there's no more live progress to show once fired,
            // so end the Live Activity explicitly here rather than letting
            // it linger — the exact "stale Live Activity" failure mode
            // already documented for AlarmKit's own system banner (see
            // NapStopApp.swift). Re-arming (below) calls startMonitoring
            // again, which starts a fresh one for the next leg.
            LiveActivityManager.shared.end(alarmID: alarms[index].id)
            liveActivityTrackedIDs.remove(alarms[index].id)
            if etaEstimators.isEmpty && liveActivityTrackedIDs.isEmpty {
                locationManager?.stopContinuousUpdates()
            }
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
            runShortcutIfConfigured(for: alarms[index])
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

        // Contact notify (even prompted/tap-to-send) requires Silver+ (see
        // monetization-tier-pricing memory). Defense in depth: the per-alarm
        // Auto-Notify toggle is already tierGated(minimumTier: .silver) in
        // AddAlarmView/TransitAlarmView so a Free-tier user can't newly
        // enable this, but an alarm edited/saved while on a higher tier
        // could still have notifyContact == true sitting in its data if the
        // device is later simulated down to Free — this guard is what
        // actually stops delivery in that case, not just the UI.
        guard EntitlementManager.isEntitled(to: .silver) else {
            DebugLogger.shared.log("Auto-Notify: skipped — current tier (\(EntitlementManager.currentTier)) is below Silver", category: "AlarmManager")
            return
        }

        let direction = alarm.regionEvent == .onEntry ? "Arrival" : "Departure"
        let verb      = alarm.regionEvent == .onEntry ? "arrived at" : "departed from"
        let timeStr   = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .short)
        var body = "[\(direction)] I \(verb) \(alarm.name) at \(timeStr)."
        if !alarm.note.isEmpty { body += " \(alarm.note)" }

        // Persist body + recipients + fire time for NotifyContactsIntent — lets the
        // Shortcuts "When GeoNap Is Opened" automation read both the message and
        // the phone numbers (sourced from this alarm's own Auto-Notify contacts,
        // same list used for the in-app compose sheet below) and send SMS without
        // a compose sheet or a manually configured recipient list. The timestamp
        // marks that an alarm has fired (vs. an ordinary app-open with nothing
        // pending) — no staleness cutoff as of 2026-07-11, so a slow app-open
        // still sends rather than silently dropping the message. NOTE: this
        // single set of keys holds only one pending message at a time — if a
        // second alarm fires before the user opens the app after the first,
        // this overwrites the first alarm's message, so only the most recent
        // alarm's notification goes out. Both behaviors are called out in
        // Settings' Auto-SMS help text (`help.body.autoNotify`).
        //
        // TODO(multi-alarm queue, discussed 2026-07-11, not yet approved/built):
        // Replace this single pending slot with a small queue instead of one
        // body/phones/timestamp triple. `queueAutoNotify` would APPEND a
        // {body, phones, firedAt} entry per firing alarm rather than overwrite.
        // On next app-open, NotifyContactsIntent.perform() reads the whole
        // queue, clears it in one shot (same one-shot guarantee as today), then
        // collapses it into a single body/recipients pair before returning —
        // so the existing Shortcuts automation needs NO changes:
        //   • Body: join each queued alarm's own line with "\n", in fire order,
        //     e.g. "[Departure] I departed from Amandas at 5:07 PM.\n[Arrival]
        //     I arrived at Darryl's at 5:35 PM."
        //   • Recipients: union of every queued alarm's phone numbers,
        //     deduplicated — the automation's existing "Repeat with Each" loop
        //     already sends one individual text per recipient, so a contact on
        //     multiple queued alarms just gets the combined message once.
        // Tradeoff (why this is a TODO and not yet built): a contact only on
        // alarm A's list would now also see alarm B's line if both are queued
        // together — there's no way to give different recipients different
        // bodies without returning an array of alarm/recipient pairs instead
        // of one pair, which would require the Personal Automation itself to
        // be rebuilt with a nested "Repeat with Each" (over alarms, then over
        // each alarm's recipients) — that part can't be done from GeoNap's
        // code, only manually in the Shortcuts app. Should also cap the queue
        // (e.g. last 10 unconsumed alarms) so it can't grow unbounded if the
        // app goes unopened for days. Mirror the same queue change in
        // `pendingContactMessage` below for the non-automation compose-sheet
        // path, which has the identical overwrite behavior.
        let defaults = UserDefaults.standard
        defaults.set(body, forKey: AutoNotifyDefaultsKey.pendingBody)
        defaults.set(phones, forKey: AutoNotifyDefaultsKey.pendingPhones)
        defaults.set(Date().timeIntervalSince1970, forKey: AutoNotifyDefaultsKey.pendingBodyTimestamp)

        // If the user runs the hands-free Shortcuts automation, suppress the in-app
        // pre-filled compose sheet so the message isn't both auto-sent AND shown.
        // Otherwise queue the one-tap compose sheet for the next foreground.
        //
        // Hands-free requires Gold+ (Silver only gets prompted/tap-to-send —
        // see monetization-tier-pricing memory). The autoSMSAutomationEnabled
        // toggle itself is tierGated(minimumTier: .gold) in SettingsView, so
        // an ordinary Silver-tier user can't turn this on — but read it
        // gated here too rather than trusting the stored flag blindly: if
        // it's somehow true on a sub-Gold device (stale value from a
        // simulated downgrade, since this flag persists across tier
        // changes), fall back to the compose sheet instead of silently
        // suppressing it with nothing to replace it — that would be a
        // worse outcome than just not gating this at all.
        let automationActive = EntitlementManager.isEntitled(to: .gold)
            && defaults.bool(forKey: AppStorageKey.autoSMSAutomationEnabled)
        if automationActive {
            DebugLogger.shared.log("Auto-Notify: body queued for Shortcuts automation; in-app sheet suppressed (\(phones.count) contact(s))", category: "AlarmManager")
        } else {
            pendingContactMessage = ContactMessage(phones: phones, body: body)
            DebugLogger.shared.log("Auto-Notify: SMS compose queued at alarm fire (\(phones.count) contact(s))", category: "AlarmManager")
        }
    }

    // MARK: - Run Shortcut on Alarm

    /// Triggers the per-alarm "Run Shortcut" feature (help.body.runShortcut).
    /// GeoNap only stores a Shortcut's name — it never inspects what the
    /// Shortcut does, so this can drive HomeKit scenes, an email, a webhook,
    /// or anything else the Shortcuts app supports.
    ///
    /// Two paths, same dual-path shape as queueAutoNotify above:
    ///   1. Reliable path (always runs): queue the name + fire time for
    ///      RunAlarmShortcutIntent to read on the next app-open — mirrors
    ///      NotifyContactsIntent exactly, including its one-shot read/clear
    ///      and lack of a staleness cutoff (a late open still runs it).
    ///   2. Best-effort immediate path: if GeoNap happens to already be
    ///      foregrounded at this exact instant, also open the
    ///      shortcuts://run-shortcut URL directly so it runs right away
    ///      instead of waiting for the next open. This is the one case where
    ///      "runs the moment the alarm fires" is literally true — uncommon,
    ///      since a location alarm typically fires while the phone is locked.
    ///
    /// Same known limitation as Auto-Notify (single pending slot — a second
    /// alarm with Run Shortcut firing before the user opens the app after the
    /// first overwrites the first alarm's pending name, so only the most
    /// recently fired alarm's Shortcut runs). Documented in help text rather
    /// than fixed; see the queue TODO on queueAutoNotify above, which would
    /// need a matching change here if ever built.
    private func runShortcutIfConfigured(for alarm: NapAlarm) {
        let name = alarm.runShortcutName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }

        // Platinum-tier gate — Run Shortcut is a Platinum feature (see
        // monetization-tier-pricing memory / EntitlementManager.swift). This
        // is defense in depth, not the enforcement point: even if this check
        // were skipped, RunAlarmShortcutIntent.perform() gates independently
        // since it's reachable directly from a Shortcuts automation. Gating
        // here too avoids queuing a name a non-entitled device will never be
        // allowed to run, and keeps the immediate-foreground `shortcuts://`
        // open from firing for locked-out users.
        guard EntitlementManager.isEntitled(to: .platinum) else {
            DebugLogger.shared.log("Run Shortcut: '\(name)' skipped — current tier (\(EntitlementManager.currentTier)) is below Platinum", category: "AlarmManager")
            return
        }

        let defaults = UserDefaults.standard
        defaults.set(name, forKey: RunShortcutDefaultsKey.pendingShortcutName)
        defaults.set(Date().timeIntervalSince1970, forKey: RunShortcutDefaultsKey.pendingShortcutFiredAt)
        DebugLogger.shared.log("Run Shortcut: '\(name)' queued for next app-open", category: "AlarmManager")

        guard UIApplication.shared.applicationState == .active,
              let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "shortcuts://run-shortcut?name=\(encoded)") else { return }
        UIApplication.shared.open(url)
        DebugLogger.shared.log("Run Shortcut: '\(name)' opened immediately (app was foregrounded)", category: "AlarmManager")
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
