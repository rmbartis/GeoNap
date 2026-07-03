// CalendarScanCandidateStore.swift
// Phase 3: persistence + dedup/re-offer logic for calendar scan candidates.
//
// A scan (manual "Scan Now" or background) can run many times against the
// same events. Without this layer, every run would re-surface every trip the
// user already added or declined. This file tracks what's been "handled"
// (added or declined) along with the location it had at the time, so:
//   • an unchanged, already-handled candidate is silently skipped on future
//     scans (no repeat notifications/review-sheet entries), and
//   • a candidate whose event location changed AFTER being handled is
//     treated as new again and re-offered — Bob's explicit design decision
//     from the original Calendar Scanning doc (2026-07-01): "Declined events
//     are re-offered if the calendar event's location field later changes."
//
// All merge logic below is pure (no EventKit, no UserDefaults) so it's fully
// unit testable, mirroring the "pure logic only" convention used elsewhere in
// this feature (see CalendarScanLocationExtractor).

import Foundation

// MARK: - Location snapshot

/// A candidate's location at a point in time, used to detect whether the
/// underlying calendar event's location changed since it was last handled.
struct CalendarCandidateLocationSnapshot: Codable, Equatable {
    let locationTitle: String
    let latitude: Double
    let longitude: Double

    init(locationTitle: String, latitude: Double, longitude: Double) {
        self.locationTitle = locationTitle
        self.latitude = latitude
        self.longitude = longitude
    }

    init(candidate: CalendarTripCandidate) {
        self.locationTitle = candidate.locationTitle
        self.latitude = candidate.latitude
        self.longitude = candidate.longitude
    }
}

// MARK: - Handled record

/// What the user did with a candidate, and the location snapshot it had at
/// that time — the snapshot is what makes re-offer-on-change possible.
enum CalendarScanCandidateAction: String, Codable {
    case added
    case declined
}

struct CalendarScanHandledRecord: Codable, Equatable {
    let action: CalendarScanCandidateAction
    let snapshot: CalendarCandidateLocationSnapshot
}

// MARK: - Pure merge logic

/// Combines a fresh scan's results with the existing pending list and handled
/// records to decide what should actually be shown to the user next.
enum CalendarScanCandidateMerger {

    struct Result: Equatable {
        let pending: [CalendarTripCandidate]
        let handled: [String: CalendarScanHandledRecord]
        /// Candidate ids present in `pending` that were NOT in `existingPending`
        /// before this merge — i.e. genuinely new-to-the-user this run. Used to
        /// decide whether a background scan should post a notification, and
        /// what count to show in it.
        let newlyPendingIDs: Set<String>
    }

    /// - Parameters:
    ///   - found: candidates produced by this scan run.
    ///   - existingPending: candidates already awaiting a decision from a prior run.
    ///   - handled: every candidate the user has already added/declined, by id.
    static func mergeScanResults(
        found: [CalendarTripCandidate],
        existingPending: [CalendarTripCandidate],
        handled: [String: CalendarScanHandledRecord]
    ) -> Result {
        var updatedHandled = handled
        var pendingByID = Dictionary(uniqueKeysWithValues: existingPending.map { ($0.id, $0) })
        let existingPendingIDs = Set(pendingByID.keys)

        for candidate in found {
            let snapshot = CalendarCandidateLocationSnapshot(candidate: candidate)
            if let record = handled[candidate.id] {
                if record.snapshot == snapshot {
                    // Already handled and nothing about its location changed — skip.
                    continue
                }
                // Location changed since it was added/declined — clear the old
                // record so it can be re-offered as a fresh candidate.
                updatedHandled.removeValue(forKey: candidate.id)
            }
            pendingByID[candidate.id] = candidate
        }

        // Drop any previously-pending candidate whose event no longer appears
        // in this scan (deleted event, or its date rolled out of the
        // look-ahead window) — keeps the pending list from growing stale.
        let foundIDs = Set(found.map(\.id))
        pendingByID = pendingByID.filter { foundIDs.contains($0.key) }

        let pending = pendingByID.values.sorted { $0.startDate < $1.startDate }
        let newlyPendingIDs = Set(pendingByID.keys).subtracting(existingPendingIDs)

        return Result(pending: pending, handled: updatedHandled, newlyPendingIDs: newlyPendingIDs)
    }

    /// Records a user decision (add or decline) for a candidate: removes it
    /// from `pending` and stores its current location snapshot in `handled`
    /// so it won't be re-offered unless the location later changes.
    static func applyDecision(
        _ action: CalendarScanCandidateAction,
        to candidate: CalendarTripCandidate,
        pending: [CalendarTripCandidate],
        handled: [String: CalendarScanHandledRecord]
    ) -> (pending: [CalendarTripCandidate], handled: [String: CalendarScanHandledRecord]) {
        var updatedHandled = handled
        updatedHandled[candidate.id] = CalendarScanHandledRecord(
            action: action,
            snapshot: CalendarCandidateLocationSnapshot(candidate: candidate)
        )
        let updatedPending = pending.filter { $0.id != candidate.id }
        return (updatedPending, updatedHandled)
    }
}

// MARK: - Persistence

/// JSON UserDefaults persistence for the pending list and handled-record map.
/// Mirrors the encode/decode-defensively convention used by CalendarScanStorage.
enum CalendarScanCandidateStore {

    static func loadPending() -> [CalendarTripCandidate] {
        decode([CalendarTripCandidate].self, key: AppStorageKey.calendarScanPendingCandidatesJSON) ?? []
    }

    static func savePending(_ candidates: [CalendarTripCandidate]) {
        encode(candidates, key: AppStorageKey.calendarScanPendingCandidatesJSON)
    }

    static func loadHandled() -> [String: CalendarScanHandledRecord] {
        decode([String: CalendarScanHandledRecord].self, key: AppStorageKey.calendarScanHandledCandidatesJSON) ?? [:]
    }

    static func saveHandled(_ handled: [String: CalendarScanHandledRecord]) {
        encode(handled, key: AppStorageKey.calendarScanHandledCandidatesJSON)
    }

    // MARK: Private helpers

    private static func decode<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let raw = UserDefaults.standard.string(forKey: key),
              let data = raw.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private static func encode<T: Encodable>(_ value: T, key: String) {
        guard let data = try? JSONEncoder().encode(value),
              let string = String(data: data, encoding: .utf8) else { return }
        UserDefaults.standard.set(string, forKey: key)
    }
}
