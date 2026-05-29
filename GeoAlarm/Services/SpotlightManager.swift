// SpotlightManager.swift
// Indexes NapAlarm entries in CoreSpotlight so they appear in on-device search.
// Each alarm is stored as a CSSearchableItem keyed by its UUID.
// Tapping a result sends an NSUserActivity that NapStopApp routes to AlarmDetailView.

import CoreSpotlight
import CoreLocation
import UIKit

final class SpotlightManager {

    static let shared = SpotlightManager()

    /// Domain groups all NapStop alarm items — lets us delete them all at once if needed.
    static let domainIdentifier = "com.rmbartis.NapStop.alarm"

    /// Must match NSUserActivityTypes in Info.plist.
    static let activityType = "com.rmbartis.NapStop.viewAlarm"

    /// UserInfo key carrying the alarm UUID string inside the NSUserActivity.
    static let alarmIDKey = "alarmID"

    private let index = CSSearchableIndex.default()

    private init() {}

    // MARK: - Public API

    /// Index or re-index a single alarm.
    func index(_ alarm: NapAlarm) {
        let item = makeItem(for: alarm)
        index.indexSearchableItems([item]) { error in
            if let error {
                print("⚠️ Spotlight index error for '\(alarm.name)': \(error.localizedDescription)")
            }
        }
    }

    /// Replace the entire Spotlight index with the current alarm list.
    /// Called on launch after alarms are loaded from SwiftData.
    func reindexAll(_ alarms: [NapAlarm]) {
        let items = alarms.map { makeItem(for: $0) }
        // Delete stale entries first, then add fresh ones.
        index.deleteSearchableItems(withDomainIdentifiers: [Self.domainIdentifier]) { [weak self] _ in
            guard let self else { return }
            self.index.indexSearchableItems(items) { error in
                if let error {
                    print("⚠️ Spotlight reindexAll error: \(error.localizedDescription)")
                }
            }
        }
    }

    /// Remove a single alarm from the Spotlight index.
    func deindex(_ alarm: NapAlarm) {
        index.deleteSearchableItems(withIdentifiers: [alarm.id.uuidString]) { error in
            if let error {
                print("⚠️ Spotlight deindex error for '\(alarm.name)': \(error.localizedDescription)")
            }
        }
    }

    /// Remove every NapStop alarm from Spotlight (e.g. on sign-out or reset).
    func deindexAll() {
        index.deleteSearchableItems(withDomainIdentifiers: [Self.domainIdentifier]) { error in
            if let error {
                print("⚠️ Spotlight deindexAll error: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Private helpers

    private func makeItem(for alarm: NapAlarm) -> CSSearchableItem {
        let attrs = CSSearchableItemAttributeSet(contentType: .item)

        // Primary text
        attrs.title = alarm.name

        // Secondary line: trigger · radius · note
        var parts: [String] = [alarm.regionEvent.rawValue]
        parts.append("\(Int(alarm.radius)) m radius")
        if !alarm.note.isEmpty { parts.append(alarm.note) }
        attrs.contentDescription = parts.joined(separator: " · ")

        // Geographic coordinates — Spotlight can show a map preview
        attrs.latitude  = NSNumber(value: alarm.latitude)
        attrs.longitude = NSNumber(value: alarm.longitude)
        attrs.namedLocation = alarm.name

        // Keywords drive search matching beyond the title
        var keywords = ["location alarm", "geo alarm", "arrival alert",
                        "napstop", "commuter", "transit", "geofence", alarm.name]
        if alarm.isTransitAlarm {
            keywords += ["train alarm", "bus alarm", "transit alarm"]
        }
        attrs.keywords = keywords

        // Thumbnail: tinted SF Symbol rendered to PNG
        let symbolName = alarm.isTransitAlarm ? "tram.fill" : "location.circle.fill"
        let tint: UIColor = alarm.isActive ? .systemBlue : .systemGray
        if let img = UIImage(systemName: symbolName)?
                        .withTintColor(tint, renderingMode: .alwaysOriginal) {
            attrs.thumbnailData = img.pngData()
        }

        return CSSearchableItem(
            uniqueIdentifier: alarm.id.uuidString,
            domainIdentifier: Self.domainIdentifier,
            attributeSet: attrs
        )
    }
}
