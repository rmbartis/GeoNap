// AlarmManager.swift
// Owns the list of GeoAlarms, coordinates region monitoring via LocationManager,
// fires local notifications on region events, and persists via SwiftData.

import Foundation
import UserNotifications
import CoreLocation
import SwiftData
import Combine

@MainActor
final class AlarmManager: ObservableObject {

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
    init() {}

    // MARK: - SwiftData setup

    func setModelContext(_ context: ModelContext) {
        modelContext = context
        load()
    }

    // MARK: - Notification permission

    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound, .badge]
        ) { granted, error in
            if let error = error {
                print("❌ Notification permission error: \(error.localizedDescription)")
            } else {
                print(granted ? "✅ Notifications granted" : "⚠️ Notifications denied")
            }
        }
    }

    // MARK: - CRUD

    func add(alarm: GeoAlarm) {
        modelContext?.insert(alarm)
        save()
        alarms.append(alarm)
        if alarm.isActive { startMonitoring(alarm) }
    }

    /// Call after mutating a GeoAlarm's properties directly (SwiftData tracks changes).
    func update(alarm: GeoAlarm) {
        save()
        stopMonitoring(alarm)
        if alarm.isActive { startMonitoring(alarm) }
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
        // Match an ACTIVE alarm whose trigger matches this event.
        if let index = alarms.firstIndex(where: {
            $0.id.uuidString == regionID && $0.isActive && $0.regionEvent == event
        }) {
            alarms[index].state = .triggered
            alarms[index].lastTriggeredAt = Date()
            fireNotification(for: alarms[index])
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
        content.sound = .defaultCritical
        content.userInfo = ["alarmID": alarm.id.uuidString]

        // Add a "Snooze 10 min" action
        content.categoryIdentifier = "GEO_ALARM"

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
        try? modelContext?.save()
    }

    private func load() {
        guard let context = modelContext else { return }
        alarms = (try? context.fetch(
            FetchDescriptor<GeoAlarm>(sortBy: [SortDescriptor(\.name)])
        )) ?? []
    }
}
