// CalendarScanService.swift
// EventKit wrapper for the Calendar Scanning feature — lets GeoNap scan the
// user's calendars for upcoming events with a location, and suggest
// location-based alarms for them.
//
// Scanning is strictly opt-in: AppStorageKey.calendarScanEnabled defaults to
// false, and this service does nothing until the user explicitly enables it
// in Settings → Calendar Scanning.

import Foundation
import Combine
import EventKit

// MARK: - CalendarSourceGroup

/// One calendar "account" (e.g. iCloud, a Google account, an Exchange
/// account) grouping the individual EKCalendars it owns. Used to build the
/// first-run "select calendars" sheet, grouped by source.
struct CalendarSourceGroup: Identifiable, Equatable {
    let id: String                 // EKSource.sourceIdentifier
    let title: String              // EKSource.title
    let sourceTypeRaw: Int         // EKSource.sourceType.rawValue
    let calendars: [CalendarInfo]

    var sourceTypeLabel: String {
        CalendarScanService.label(forSourceTypeRaw: sourceTypeRaw)
    }

    /// True for the source that should be pre-checked by default in the
    /// first-run sheet — the on-device (.local) source, or an iCloud
    /// (.calDAV) source. Everything else starts unchecked (Option C).
    var isPrimaryCandidate: Bool {
        if sourceTypeRaw == EKSourceType.local.rawValue { return true }
        if sourceTypeRaw == EKSourceType.calDAV.rawValue,
           title.localizedCaseInsensitiveContains("icloud") {
            return true
        }
        return false
    }
}

/// A single EKCalendar, reduced to the fields the scan UI needs.
struct CalendarInfo: Identifiable, Equatable {
    let id: String          // EKCalendar.calendarIdentifier
    let title: String
    let colorHex: String?
}

// MARK: - Persistence helpers

/// JSON Set<String> encode/decode for the calendarScanEnabledCalendarIDs
/// AppStorage key. Sorted before encoding so the stored value is
/// deterministic (stable diffs, easier debugging).
enum CalendarScanStorage {
    static func decodeStringSet(_ raw: String) -> Set<String> {
        guard let data = raw.data(using: .utf8),
              let array = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return Set(array)
    }

    static func encodeStringSet(_ set: Set<String>) -> String {
        let sorted = set.sorted()
        guard let data = try? JSONEncoder().encode(sorted),
              let string = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return string
    }
}

// MARK: - CalendarScanService

@MainActor
final class CalendarScanService: ObservableObject {

    @Published private(set) var authorizationStatus: EKAuthorizationStatus
    @Published private(set) var sourceGroups: [CalendarSourceGroup] = []

    private let store: EKEventStore

    var isAuthorized: Bool { authorizationStatus == .fullAccess }

    init(store: EKEventStore = EKEventStore()) {
        self.store = store
        self.authorizationStatus = EKEventStore.authorizationStatus(for: .event)
    }

    // MARK: - Authorization

    /// Requests full calendar access. Returns true only if the user granted
    /// access; updates `authorizationStatus` either way.
    func requestAccess() async -> Bool {
        do {
            let granted = try await store.requestFullAccessToEvents()
            authorizationStatus = EKEventStore.authorizationStatus(for: .event)
            DebugLogger.shared.log("Calendar access request result: \(granted)", category: "CalendarScan")
            return granted
        } catch {
            authorizationStatus = EKEventStore.authorizationStatus(for: .event)
            DebugLogger.shared.log("Calendar access request failed: \(error.localizedDescription)", category: "CalendarScan")
            return false
        }
    }

    // MARK: - Source / calendar discovery

    /// Refreshes `sourceGroups` from the current set of EKCalendars, grouped
    /// by EKSource. Call after access is granted and whenever the first-run
    /// sheet or Settings screen appears, in case calendars changed.
    func refreshSourceGroups() {
        guard isAuthorized else {
            sourceGroups = []
            return
        }
        let calendars = store.calendars(for: .event)
        var bySource: [String: (source: EKSource, calendars: [CalendarInfo])] = [:]
        for cal in calendars {
            // EKCalendar.source is optional on some SDK versions — skip any
            // calendar that (unexpectedly) has no owning source rather than
            // crashing or silently mis-grouping it.
            guard let source = cal.source else { continue }
            let info = CalendarInfo(
                id: cal.calendarIdentifier,
                title: cal.title,
                colorHex: UIColorHex.hexString(from: cal.cgColor)
            )
            bySource[source.sourceIdentifier, default: (source, [])].calendars.append(info)
        }
        sourceGroups = bySource.values.map { entry in
            CalendarSourceGroup(
                id: entry.source.sourceIdentifier,
                title: entry.source.title,
                sourceTypeRaw: entry.source.sourceType.rawValue,
                calendars: entry.calendars.sorted { $0.title < $1.title }
            )
        }.sorted { $0.title < $1.title }
    }

    /// The source identifier that should be pre-checked in the first-run
    /// sheet (Option C: only the primary/iCloud source starts checked).
    var primarySourceID: String? {
        sourceGroups.first(where: \.isPrimaryCandidate)?.id
    }

    // MARK: - Source type labels

    /// Human-readable label for an EKSourceType, by raw value (so callers
    /// don't need to import EventKit just to switch on it).
    /// NOTE: mobileMe vs. calDAV "iCloud" labeling has not been verified
    /// on-device — iCloud calendars typically report as .calDAV with the
    /// source title "iCloud", but this should be confirmed against a real
    /// iCloud account before shipping.
    nonisolated static func label(forSourceTypeRaw raw: Int) -> String {
        switch EKSourceType(rawValue: raw) {
        case .local:        return "On My iPhone"
        case .calDAV:       return "iCloud / CalDAV"
        case .exchange:     return "Exchange"
        case .subscribed:   return "Subscribed"
        case .birthdays:    return "Birthdays"
        case .mobileMe:     return "iCloud (MobileMe)"
        default:            return "Other"
        }
    }
}

// MARK: - CGColor → hex (local, tiny helper — avoids pulling in UIKit color utils)

private enum UIColorHex {
    static func hexString(from color: CGColor) -> String? {
        guard let components = color.components, components.count >= 3 else { return nil }
        let r = Int((components[0] * 255).rounded())
        let g = Int((components[1] * 255).rounded())
        let b = Int((components[2] * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
