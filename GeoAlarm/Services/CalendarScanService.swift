// Copyright © 2026 Robert Bartis. All rights reserved.

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
import CoreLocation
import MapKit

// MARK: - CalendarSourceGroup

/// One calendar "account" (e.g. iCloud, a Google account, an Exchange
/// account) grouping the individual EKCalendars it owns. Used to build the
/// first-run "select calendars" sheet, grouped by source.
nonisolated struct CalendarSourceGroup: Identifiable, Equatable {
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
nonisolated struct CalendarInfo: Identifiable, Equatable {
    let id: String          // EKCalendar.calendarIdentifier
    let title: String
    let colorHex: String?
}

// MARK: - Trip candidates (Phase 2 scan pipeline)

/// A single alarm candidate produced by scanning calendars for events with a
/// resolvable location. Nothing is persisted until the user explicitly adds
/// it as an alarm from the review sheet — the scan itself never creates
/// alarms.
nonisolated struct CalendarTripCandidate: Identifiable, Equatable, Codable {
    /// EKEvent.eventIdentifier, or a generated UUID string for the rare event
    /// that doesn't have one (EventKit marks it optional).
    let id: String
    let title: String
    let startDate: Date
    let calendarID: String
    /// Human-readable location label, pre-filled as the new alarm's name.
    let locationTitle: String
    let latitude: Double
    let longitude: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

/// Where a candidate's coordinate came from — informational, useful for
/// logging why a particular event was or wasn't included.
nonisolated enum CalendarScanLocationSource: Equatable {
    /// Event had `structuredLocation` with its own `CLLocation` — no
    /// geocoding needed, and generally the more trustworthy of the two.
    case structured
    /// Event only had a plain-text `location` string; needs geocoding.
    case geocoded
}

/// The subset of an EKEvent's location-related fields the extractor needs,
/// pulled into a plain struct so extraction can be unit tested without a
/// live EventKit store (mirrors the "pure logic only" convention used
/// elsewhere in this test target).
nonisolated struct CalendarEventLocationInput: Equatable {
    let structuredLocationTitle: String?
    let structuredLocationLatitude: Double?
    let structuredLocationLongitude: Double?
    let plainLocation: String?

    init(structuredLocationTitle: String? = nil,
         structuredLocationLatitude: Double? = nil,
         structuredLocationLongitude: Double? = nil,
         plainLocation: String? = nil) {
        self.structuredLocationTitle = structuredLocationTitle
        self.structuredLocationLatitude = structuredLocationLatitude
        self.structuredLocationLongitude = structuredLocationLongitude
        self.plainLocation = plainLocation
    }
}

/// Result of extracting a usable location from an event. `latitude`/`longitude`
/// are nil when `source == .geocoded` and geocoding hasn't run yet — the
/// caller (CalendarScanService.scanForCandidates) resolves it via CLGeocoder.
nonisolated struct CalendarExtractedLocation: Equatable {
    let title: String
    let latitude: Double?
    let longitude: Double?
    let source: CalendarScanLocationSource
}

/// Pure, EventKit-free location-extraction logic. Kept as a standalone enum
/// (rather than a CalendarScanService instance method) so it's trivially
/// unit testable with no dependency on a live EKEventStore.
nonisolated enum CalendarScanLocationExtractor {

    /// Extracts the best available location from an event, preferring the
    /// geo-tagged `structuredLocation` over the plain-text `location` field.
    /// `notes` is intentionally never consulted — free-text parsing there is
    /// too high a false-positive risk (Bob's Phase 2 design decision, 2026-07-02).
    static func extract(from input: CalendarEventLocationInput) -> CalendarExtractedLocation? {
        if let lat = input.structuredLocationLatitude, let lon = input.structuredLocationLongitude,
           CLLocationCoordinate2DIsValid(CLLocationCoordinate2D(latitude: lat, longitude: lon)),
           !(lat == 0 && lon == 0) {
            let structuredTitle = input.structuredLocationTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
            let plainTitle = input.plainLocation?.trimmingCharacters(in: .whitespacesAndNewlines)
            let resolvedTitle = (structuredTitle?.isEmpty == false ? structuredTitle : nil)
                ?? (plainTitle?.isEmpty == false ? plainTitle : nil)
                ?? ""
            return CalendarExtractedLocation(title: resolvedTitle, latitude: lat, longitude: lon, source: .structured)
        }
        if let plain = input.plainLocation?.trimmingCharacters(in: .whitespacesAndNewlines), !plain.isEmpty {
            return CalendarExtractedLocation(title: plain, latitude: nil, longitude: nil, source: .geocoded)
        }
        return nil
    }
}

// MARK: - Geocoding (injectable for testing)

/// Abstraction over "resolve a text address to a coordinate, or fail." Lets
/// the retry logic in CalendarScanGeocodeRetrier be unit tested with a fake
/// that fails on command, without touching MapKit, the network, or any
/// actual geocoding service (mirrors the EventKit-free testing convention
/// used by CalendarScanLocationExtractor).
protocol CalendarScanGeocoding {
    func geocode(addressString: String) async -> CLLocationCoordinate2D?
}

/// Production geocoder — wraps MapKit's request-based geocoding API.
/// CLGeocoder.geocodeAddressString(_:) was deprecated in iOS 26 in favor of
/// this. A fresh MKGeocodingRequest per call, matching the "fresh request
/// per attempt" pattern used for GTFS feed reachability retries.
nonisolated struct MapKitGeocoder: CalendarScanGeocoding {
    func geocode(addressString: String) async -> CLLocationCoordinate2D? {
        guard let request = MKGeocodingRequest(addressString: addressString),
              let mapItems = try? await request.mapItems else { return nil }
        return mapItems.first?.location.coordinate
    }
}

/// Pure retry orchestration around a `CalendarScanGeocoding`, extracted as a
/// standalone enum (rather than inline in scanForCandidates) so it's
/// trivially unit testable with a fake geocoder — no live network or
/// EventKit dependency (mirrors CalendarScanLocationExtractor's "pure logic
/// only" convention).
///
/// A single failed geocoding attempt — a transient network hiccup, momentary
/// MapKit service error — previously dropped the event silently for the
/// whole scan; Bob observed a manual scan miss one of two events that a
/// later automatic scan picked up cleanly, consistent with exactly this
/// (2026-07-03).
enum CalendarScanGeocodeRetrier {
    /// Retries `geocoder.geocode(addressString:)` up to `maxRetries` extra
    /// times (1 + maxRetries attempts total) before giving up. `retryDelay`
    /// is nanoseconds between attempts — pass 0 in tests to skip the real
    /// wait instead of injecting a fake clock.
    static func geocodeWithRetry(
        addressString: String,
        geocoder: CalendarScanGeocoding,
        maxRetries: Int,
        retryDelay: UInt64
    ) async -> CLLocationCoordinate2D? {
        for attempt in 0...maxRetries {
            if let coordinate = await geocoder.geocode(addressString: addressString) {
                return coordinate
            }
            if attempt < maxRetries {
                try? await Task.sleep(nanoseconds: retryDelay)
            }
        }
        return nil
    }
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
    private let geocoder: CalendarScanGeocoding

    var isAuthorized: Bool { authorizationStatus == .fullAccess }

    /// Geocoding attempts (1 initial + this many retries) for a plain-text
    /// event location before giving up on that event for this scan — see
    /// CalendarScanGeocodeRetrier for the retry logic itself and its tests.
    private static let geocodeMaxRetries = 2
    private static let geocodeRetryDelay: UInt64 = 1_000_000_000 // 1 s

    // `geocoder` defaults to nil and is resolved inside the init body rather
    // than as a `= MapKitGeocoder()` default parameter expression. This used
    // to be required: default parameter expressions evaluate in a nonisolated
    // context regardless of the initializer's own isolation, and
    // MapKitGeocoder's synthesized init() was inferred @MainActor (project-
    // wide SWIFT_DEFAULT_ACTOR_ISOLATION), which produced a "main actor-
    // isolated initializer called in a synchronous nonisolated context"
    // warning. MapKitGeocoder is now declared `nonisolated` (2026-07-11,
    // CI-warnings cleanup — see CalendarScanGeocoding/MapKitGeocoder below),
    // which fixes that at the root; this resolve-in-body structure is no
    // longer required but is kept as-is since it's still correct and
    // changing it back has no warning benefit.
    init(store: EKEventStore = EKEventStore(), geocoder: CalendarScanGeocoding? = nil) {
        self.store = store
        self.geocoder = geocoder ?? MapKitGeocoder()
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
    ///
    /// Sources where `isScannable(sourceTypeRaw:)` is false are dropped
    /// entirely — currently just the synthetic `.birthdays` source, which
    /// bundles the "Birthdays" calendar and (iOS 17+) the "Holidays" calendar.
    /// Neither ever carries a usable location, so offering them in the
    /// calendar picker is pure noise (Bob, 2026-07-02).
    ///
    /// Individual calendars failing `isScannable(calendarTitle:)` are also
    /// dropped — this catches holiday calendars EventKit doesn't tag with a
    /// dedicated source type, e.g. iOS's auto-added "US Holidays" under a
    /// generic `.subscribed` source (Bob spotted this in the live app and
    /// asked for it to be removed too, 2026-07-02).
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
            guard CalendarScanService.isScannable(sourceTypeRaw: source.sourceType.rawValue) else { continue }
            guard CalendarScanService.isScannable(calendarTitle: cal.title) else { continue }
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

    /// Whether a calendar source should be offered for scanning. Excludes the
    /// synthetic `.birthdays` source — it contains the "Birthdays" calendar
    /// and, on iOS 17+, the "Holidays" calendar, neither of which ever have a
    /// location. Every other source type is scannable.
    nonisolated static func isScannable(sourceTypeRaw raw: Int) -> Bool {
        EKSourceType(rawValue: raw) != .birthdays
    }

    /// Whether an individual calendar should be offered for scanning, by
    /// title. Unlike Birthdays, holiday calendars aren't always tagged with a
    /// dedicated EKSourceType — iOS commonly auto-adds one (e.g. "US
    /// Holidays") as a plain `.subscribed` calendar, which `isScannable(sourceTypeRaw:)`
    /// has no way to catch. Holiday entries never carry a location either, so
    /// name-matching is the only signal available here.
    ///
    /// This is a case-insensitive substring match on "holiday" — English
    /// only. A calendar named "Feiertage" (German), "Jours fériés" (French),
    /// etc. would slip through; broadening this to match localized names
    /// would need a per-language list and hasn't been done. A calendar with
    /// "holiday" in its name for an unrelated reason (e.g. a legitimate
    /// "Holiday Party Planning" calendar with real venues) would also be
    /// excluded — an accepted false-positive per Bob (2026-07-02), since
    /// holiday calendars are common and planning calendars with that exact
    /// wording are not.
    nonisolated static func isScannable(calendarTitle title: String) -> Bool {
        !title.localizedCaseInsensitiveContains("holiday")
    }

    // MARK: - Scan pipeline (Phase 2)

    /// The [start, end) date range a scan should search, given "now" and a
    /// look-ahead window in days. Pulled out as a pure function so the
    /// look-ahead math is unit testable without touching EventKit.
    nonisolated static func scanDateRange(from now: Date, lookaheadDays: Int, calendar: Calendar = .current) -> (start: Date, end: Date)? {
        guard lookaheadDays > 0 else { return nil }
        guard let end = calendar.date(byAdding: .day, value: lookaheadDays, to: now) else { return nil }
        return (now, end)
    }

    /// Scans the given calendars for upcoming events with a resolvable
    /// location, within `lookaheadDays` of now. Geocodes events that only
    /// have a plain-text `location` (no `structuredLocation`) one at a time
    /// via CLGeocoder; events whose location can't be resolved — including
    /// geocoding failures — are silently skipped rather than surfaced as
    /// broken candidates.
    ///
    /// Nothing is persisted here — this only produces candidates for the
    /// caller's review sheet. Declined-candidate tracking/re-offer and
    /// background (BGAppRefreshTask) scanning are Phase 3, not implemented
    /// yet.
    func scanForCandidates(enabledCalendarIDs: Set<String>, lookaheadDays: Int) async -> [CalendarTripCandidate] {
        guard isAuthorized, !enabledCalendarIDs.isEmpty else { return [] }

        let calendars = store.calendars(for: .event).filter { enabledCalendarIDs.contains($0.calendarIdentifier) }
        guard !calendars.isEmpty else { return [] }

        guard let range = CalendarScanService.scanDateRange(from: Date(), lookaheadDays: lookaheadDays) else { return [] }
        let predicate = store.predicateForEvents(withStart: range.start, end: range.end, calendars: calendars)
        let events = store.events(matching: predicate)

        var candidates: [CalendarTripCandidate] = []

        for event in events {
            let input = CalendarEventLocationInput(
                structuredLocationTitle: event.structuredLocation?.title,
                structuredLocationLatitude: event.structuredLocation?.geoLocation?.coordinate.latitude,
                structuredLocationLongitude: event.structuredLocation?.geoLocation?.coordinate.longitude,
                plainLocation: event.location
            )
            guard let extracted = CalendarScanLocationExtractor.extract(from: input) else { continue }

            var lat = extracted.latitude
            var lon = extracted.longitude
            if extracted.source == .geocoded {
                guard let coordinate = await CalendarScanGeocodeRetrier.geocodeWithRetry(
                    addressString: extracted.title,
                    geocoder: geocoder,
                    maxRetries: Self.geocodeMaxRetries,
                    retryDelay: Self.geocodeRetryDelay
                ) else {
                    DebugLogger.shared.log("Calendar scan: skipped '\(event.title ?? "")' — geocoding failed after \(Self.geocodeMaxRetries + 1) attempt(s) for '\(extracted.title)'", category: "CalendarScan")
                    continue
                }
                lat = coordinate.latitude
                lon = coordinate.longitude
            }
            guard let resolvedLat = lat, let resolvedLon = lon else { continue }

            candidates.append(CalendarTripCandidate(
                id: event.eventIdentifier ?? UUID().uuidString,
                title: event.title ?? "",
                startDate: event.startDate,
                calendarID: event.calendar?.calendarIdentifier ?? "",
                locationTitle: extracted.title,
                latitude: resolvedLat,
                longitude: resolvedLon
            ))
        }

        DebugLogger.shared.log("Calendar scan found \(candidates.count) candidate(s) with resolvable locations.", category: "CalendarScan")
        return candidates
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
