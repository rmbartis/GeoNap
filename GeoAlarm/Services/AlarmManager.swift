// AlarmManager.swift
// Owns the list of GeoAlarms, coordinates region monitoring via LocationManager,
// and fires local notifications when a region event matches an active alarm.

import Foundation
import UserNotifications
internal import CoreLocation
import Combine
internal import SwiftUI

final class AlarmManager: ObservableObject {

    // MARK: - Published state
    @Published private(set) var alarms: [GeoAlarm] = []

    // MARK: - Dependencies
    // Injected after init so both objects can be @StateObject in the App entry point.
    weak var locationManager: LocationManager? {
        didSet { bindLocationEvents() }
    }

    // MARK: - Persistence
    private let persistenceKey = "geo_alarms_v1"

    // MARK: - Init
    init() {
        load()
    }

    // MARK: - Permission

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
        alarms.append(alarm)
        if alarm.isActive { startMonitoring(alarm) }
        save()
    }

    func update(alarm: GeoAlarm) {
        guard let index = alarms.firstIndex(where: { $0.id == alarm.id }) else { return }
        let old = alarms[index]
        alarms[index] = alarm

        // Re-register region monitoring if anything changed
        stopMonitoring(old)
        if alarm.isActive { startMonitoring(alarm) }
        save()
    }

    func delete(alarm: GeoAlarm) {
        stopMonitoring(alarm)
        alarms.removeAll { $0.id == alarm.id }
        save()
    }

    func delete(at offsets: IndexSet) {
        offsets.forEach { stopMonitoring(alarms[$0]) }
        alarms.remove(atOffsets: offsets)
        save()
    }

    func toggleActive(_ alarm: GeoAlarm) {
        var modified = alarm
        modified.state = alarm.isActive ? .inactive : .active
        update(alarm: modified)
    }

    // MARK: - Region monitoring helpers

    private func startMonitoring(_ alarm: GeoAlarm) {
        locationManager?.startMonitoring(region: alarm.clRegion)
    }

    private func stopMonitoring(_ alarm: GeoAlarm) {
        locationManager?.stopMonitoring(region: alarm.clRegion)
    }

    /// Re-register all active alarms (call after app launch or permission grant).
    func reregisterAllRegions() {
        locationManager?.stopMonitoringAll()
        alarms.filter(\.isActive).forEach { startMonitoring($0) }
    }

    // MARK: - Region event handling

    private func bindLocationEvents() {
        locationManager?.onRegionEntered = { [weak self] regionID in
            self?.handleRegionEvent(regionID: regionID, event: .onEntry)
        }
        locationManager?.onRegionExited = { [weak self] regionID in
            self?.handleRegionEvent(regionID: regionID, event: .onExit)
        }
    }

    func handleRegionEvent(regionID: String, event: RegionEvent) {
        guard let index = alarms.firstIndex(where: {
            $0.id.uuidString == regionID && $0.isActive && $0.regionEvent == event
        }) else { return }

        alarms[index].state = .triggered
        alarms[index].lastTriggeredAt = Date()
        fireNotification(for: alarms[index])
        save()
    }

    // MARK: - Local notification

    private func fireNotification(for alarm: GeoAlarm) {
        let content = UNMutableNotificationContent()
        content.title = "📍 \(alarm.name)"
        content.body = alarm.note.isEmpty
            ? "\(alarm.regionEvent.rawValue) detected."
            : alarm.note
        content.sound = .defaultCritical  // Plays even in Do Not Disturb
        content.categoryIdentifier = "GEO_ALARM"

        // Deliver immediately (the region event is our trigger)
        let request = UNNotificationRequest(
            identifier: alarm.id.uuidString,
            content: content,
            trigger: nil   // nil = deliver right now
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("❌ Notification scheduling failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Snooze

    /// Temporarily suppress an alarm and re-arm it after `minutes` minutes.
    func snooze(_ alarm: GeoAlarm, minutes: Int = 10) {
        guard let index = alarms.firstIndex(where: { $0.id == alarm.id }) else { return }
        alarms[index].state = .snoozed
        save()

        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(minutes * 60)) { [weak self] in
            guard let self, let idx = self.alarms.firstIndex(where: { $0.id == alarm.id }),
                  self.alarms[idx].state == .snoozed else { return }
            self.alarms[idx].state = .active
            self.startMonitoring(self.alarms[idx])
            self.save()
        }
    }

    // MARK: - Persistence (UserDefaults — swap for CoreData/SwiftData as needed)

    private func save() {
        guard let data = try? JSONEncoder().encode(alarms) else { return }
        UserDefaults.standard.set(data, forKey: persistenceKey)
    }

    private func load() {
        guard
            let data = UserDefaults.standard.data(forKey: persistenceKey),
            let saved = try? JSONDecoder().decode([GeoAlarm].self, from: data)
        else { return }
        alarms = saved
    }
}
