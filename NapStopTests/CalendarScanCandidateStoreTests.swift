// CalendarScanCandidateStoreTests.swift
// Unit tests for Phase 3's dedup/re-offer logic:
//   • CalendarScanCandidateMerger.mergeScanResults(found:existingPending:handled:)
//   • CalendarScanCandidateMerger.applyDecision(_:to:pending:handled:)
//   • CalendarCandidateLocationSnapshot / CalendarScanHandledRecord Codable round-trip
//
// All of the above are pure (no UserDefaults, no EventKit) so they're tested
// directly, mirroring the "pure logic only" convention used throughout this
// feature (see CalendarScanServiceTests.swift). CalendarScanCandidateStore's
// load/save methods touch UserDefaults.standard directly (matching this
// project's existing AppStorage-based persistence pattern) and are
// intentionally NOT exercised here for the same reason live EventKit/
// CLGeocoder calls aren't — they're thin, side-effecting wrappers around
// JSONEncoder/Decoder with no branching logic worth testing in isolation.

import XCTest
@testable import GeoNap

// MARK: - Test helpers

private func makeCandidate(
    id: String,
    title: String = "Trip",
    startDate: Date = Date(timeIntervalSince1970: 0),
    calendarID: String = "cal-1",
    locationTitle: String = "Union Station",
    latitude: Double = 43.6452,
    longitude: Double = -79.3806
) -> CalendarTripCandidate {
    CalendarTripCandidate(
        id: id,
        title: title,
        startDate: startDate,
        calendarID: calendarID,
        locationTitle: locationTitle,
        latitude: latitude,
        longitude: longitude
    )
}

// MARK: - CalendarCandidateLocationSnapshot

final class CalendarCandidateLocationSnapshotTests: XCTestCase {

    func test_initFromCandidate_capturesLocationFields() {
        let candidate = makeCandidate(id: "a", locationTitle: "Pearson Airport", latitude: 43.6777, longitude: -79.6248)
        let snapshot = CalendarCandidateLocationSnapshot(candidate: candidate)
        XCTAssertEqual(snapshot.locationTitle, "Pearson Airport")
        XCTAssertEqual(snapshot.latitude, 43.6777)
        XCTAssertEqual(snapshot.longitude, -79.6248)
    }

    func test_equality_isBasedOnAllThreeFields() {
        let a = CalendarCandidateLocationSnapshot(locationTitle: "X", latitude: 1, longitude: 2)
        let b = CalendarCandidateLocationSnapshot(locationTitle: "X", latitude: 1, longitude: 2)
        let differentTitle = CalendarCandidateLocationSnapshot(locationTitle: "Y", latitude: 1, longitude: 2)
        let differentLat = CalendarCandidateLocationSnapshot(locationTitle: "X", latitude: 9, longitude: 2)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, differentTitle)
        XCTAssertNotEqual(a, differentLat)
    }

    func test_codableRoundTrip_preservesValues() throws {
        let snapshot = CalendarCandidateLocationSnapshot(locationTitle: "Union Station", latitude: 43.6452, longitude: -79.3806)
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(CalendarCandidateLocationSnapshot.self, from: data)
        XCTAssertEqual(decoded, snapshot)
    }
}

// MARK: - CalendarScanHandledRecord

final class CalendarScanHandledRecordTests: XCTestCase {

    func test_codableRoundTrip_preservesActionAndSnapshot() throws {
        let record = CalendarScanHandledRecord(
            action: .declined,
            snapshot: CalendarCandidateLocationSnapshot(locationTitle: "X", latitude: 1, longitude: 2)
        )
        let data = try JSONEncoder().encode(record)
        let decoded = try JSONDecoder().decode(CalendarScanHandledRecord.self, from: data)
        XCTAssertEqual(decoded, record)
    }

    func test_dictionaryOfRecords_codableRoundTrip() throws {
        // This is the actual shape persisted to UserDefaults — a dictionary
        // keyed by candidate id, not a single record.
        let dict: [String: CalendarScanHandledRecord] = [
            "evt-1": CalendarScanHandledRecord(action: .added, snapshot: CalendarCandidateLocationSnapshot(locationTitle: "A", latitude: 1, longitude: 1)),
            "evt-2": CalendarScanHandledRecord(action: .declined, snapshot: CalendarCandidateLocationSnapshot(locationTitle: "B", latitude: 2, longitude: 2)),
        ]
        let data = try JSONEncoder().encode(dict)
        let decoded = try JSONDecoder().decode([String: CalendarScanHandledRecord].self, from: data)
        XCTAssertEqual(decoded, dict)
    }
}

// MARK: - CalendarScanCandidateMerger.mergeScanResults

final class CalendarScanCandidateMergerTests: XCTestCase {

    func test_brandNewCandidate_isAddedToPendingAndFlaggedAsNew() {
        let candidate = makeCandidate(id: "evt-1")
        let result = CalendarScanCandidateMerger.mergeScanResults(found: [candidate], existingPending: [], handled: [:])
        XCTAssertEqual(result.pending.map(\.id), ["evt-1"])
        XCTAssertEqual(result.newlyPendingIDs, ["evt-1"])
        XCTAssertTrue(result.handled.isEmpty)
    }

    func test_alreadyPendingCandidateFoundAgainUnchanged_staysPending_notFlaggedAsNew() {
        let candidate = makeCandidate(id: "evt-1")
        let result = CalendarScanCandidateMerger.mergeScanResults(found: [candidate], existingPending: [candidate], handled: [:])
        XCTAssertEqual(result.pending.map(\.id), ["evt-1"])
        XCTAssertTrue(result.newlyPendingIDs.isEmpty, "Already-pending candidates shouldn't be re-flagged as new")
    }

    func test_handledCandidateWithUnchangedLocation_isSkippedEntirely() {
        let candidate = makeCandidate(id: "evt-1", locationTitle: "Union Station", latitude: 43.6452, longitude: -79.3806)
        let handled: [String: CalendarScanHandledRecord] = [
            "evt-1": CalendarScanHandledRecord(action: .added, snapshot: CalendarCandidateLocationSnapshot(candidate: candidate))
        ]
        let result = CalendarScanCandidateMerger.mergeScanResults(found: [candidate], existingPending: [], handled: handled)
        XCTAssertTrue(result.pending.isEmpty)
        XCTAssertTrue(result.newlyPendingIDs.isEmpty)
        XCTAssertEqual(result.handled.count, 1, "The handled record should be preserved, not dropped")
    }

    func test_declinedCandidateWithChangedLocation_isReOfferedAndOldRecordCleared() {
        let original = makeCandidate(id: "evt-1", locationTitle: "Old Address", latitude: 1, longitude: 1)
        let moved = makeCandidate(id: "evt-1", locationTitle: "New Address", latitude: 2, longitude: 2)
        let handled: [String: CalendarScanHandledRecord] = [
            "evt-1": CalendarScanHandledRecord(action: .declined, snapshot: CalendarCandidateLocationSnapshot(candidate: original))
        ]
        let result = CalendarScanCandidateMerger.mergeScanResults(found: [moved], existingPending: [], handled: handled)
        XCTAssertEqual(result.pending.map(\.id), ["evt-1"])
        XCTAssertEqual(result.pending.first?.locationTitle, "New Address")
        XCTAssertEqual(result.newlyPendingIDs, ["evt-1"], "A re-offered candidate counts as new for notification purposes")
        XCTAssertTrue(result.handled.isEmpty, "The stale handled record must be cleared so it can be re-offered")
    }

    func test_addedCandidateWithChangedLocation_isAlsoReOffered() {
        // Re-offer-on-change applies to both added and declined candidates —
        // an event whose location moved after being turned into an alarm is
        // still worth re-surfacing (e.g. a meeting moved to a new building).
        let original = makeCandidate(id: "evt-1", latitude: 1, longitude: 1)
        let moved = makeCandidate(id: "evt-1", latitude: 2, longitude: 2)
        let handled: [String: CalendarScanHandledRecord] = [
            "evt-1": CalendarScanHandledRecord(action: .added, snapshot: CalendarCandidateLocationSnapshot(candidate: original))
        ]
        let result = CalendarScanCandidateMerger.mergeScanResults(found: [moved], existingPending: [], handled: handled)
        XCTAssertEqual(result.pending.map(\.id), ["evt-1"])
        XCTAssertTrue(result.handled.isEmpty)
    }

    func test_pendingCandidateNoLongerFound_isDroppedFromPending() {
        // Simulates a previously-scanned event that was deleted, or whose
        // date rolled outside the look-ahead window.
        let stillThere = makeCandidate(id: "evt-1")
        let deleted = makeCandidate(id: "evt-2")
        let result = CalendarScanCandidateMerger.mergeScanResults(
            found: [stillThere],
            existingPending: [stillThere, deleted],
            handled: [:]
        )
        XCTAssertEqual(result.pending.map(\.id), ["evt-1"])
    }

    func test_pendingIsSortedByStartDateAscending() {
        let later = makeCandidate(id: "later", startDate: Date(timeIntervalSince1970: 2000))
        let earlier = makeCandidate(id: "earlier", startDate: Date(timeIntervalSince1970: 1000))
        let result = CalendarScanCandidateMerger.mergeScanResults(found: [later, earlier], existingPending: [], handled: [:])
        XCTAssertEqual(result.pending.map(\.id), ["earlier", "later"])
    }

    func test_emptyFound_withExistingPending_dropsEverythingNotRefound() {
        // If a scan finds nothing at all (e.g. calendars temporarily
        // inaccessible), previously pending candidates are NOT force-kept —
        // they're only retained if re-found. This matches "pending reflects
        // what's currently in the calendar" rather than accumulating forever.
        let stale = makeCandidate(id: "evt-1")
        let result = CalendarScanCandidateMerger.mergeScanResults(found: [], existingPending: [stale], handled: [:])
        XCTAssertTrue(result.pending.isEmpty)
    }

    func test_multipleCandidates_mixedScenario() {
        let new = makeCandidate(id: "new")
        let stillPending = makeCandidate(id: "still-pending")
        let handledUnchanged = makeCandidate(id: "handled-unchanged", latitude: 5, longitude: 5)
        let handledChanged = makeCandidate(id: "handled-changed", latitude: 9, longitude: 9)
        let handledChangedOriginal = makeCandidate(id: "handled-changed", latitude: 8, longitude: 8)

        let handled: [String: CalendarScanHandledRecord] = [
            "handled-unchanged": CalendarScanHandledRecord(action: .declined, snapshot: CalendarCandidateLocationSnapshot(candidate: handledUnchanged)),
            "handled-changed": CalendarScanHandledRecord(action: .declined, snapshot: CalendarCandidateLocationSnapshot(candidate: handledChangedOriginal)),
        ]

        let result = CalendarScanCandidateMerger.mergeScanResults(
            found: [new, stillPending, handledUnchanged, handledChanged],
            existingPending: [stillPending],
            handled: handled
        )

        let pendingIDs = Set(result.pending.map(\.id))
        XCTAssertEqual(pendingIDs, ["new", "still-pending", "handled-changed"])
        XCTAssertEqual(result.newlyPendingIDs, ["new", "handled-changed"])
        XCTAssertEqual(result.handled.count, 1)
        XCTAssertNotNil(result.handled["handled-unchanged"])
        XCTAssertNil(result.handled["handled-changed"], "Cleared because its location changed")
    }
}

// MARK: - CalendarScanCandidateMerger.applyDecision

final class CalendarScanCandidateMergerApplyDecisionTests: XCTestCase {

    func test_addDecision_removesFromPendingAndRecordsHandled() {
        let candidate = makeCandidate(id: "evt-1")
        let other = makeCandidate(id: "evt-2")
        let (pending, handled) = CalendarScanCandidateMerger.applyDecision(
            .added, to: candidate, pending: [candidate, other], handled: [:]
        )
        XCTAssertEqual(pending.map(\.id), ["evt-2"])
        XCTAssertEqual(handled["evt-1"]?.action, .added)
        XCTAssertEqual(handled["evt-1"]?.snapshot, CalendarCandidateLocationSnapshot(candidate: candidate))
    }

    func test_declineDecision_removesFromPendingAndRecordsHandled() {
        let candidate = makeCandidate(id: "evt-1")
        let (pending, handled) = CalendarScanCandidateMerger.applyDecision(
            .declined, to: candidate, pending: [candidate], handled: [:]
        )
        XCTAssertTrue(pending.isEmpty)
        XCTAssertEqual(handled["evt-1"]?.action, .declined)
    }

    func test_decision_overwritesAnyPriorHandledRecordForSameID() {
        let candidate = makeCandidate(id: "evt-1")
        let priorHandled: [String: CalendarScanHandledRecord] = [
            "evt-1": CalendarScanHandledRecord(action: .declined, snapshot: CalendarCandidateLocationSnapshot(locationTitle: "Old", latitude: 0, longitude: 0))
        ]
        let (_, handled) = CalendarScanCandidateMerger.applyDecision(
            .added, to: candidate, pending: [candidate], handled: priorHandled
        )
        XCTAssertEqual(handled["evt-1"]?.action, .added)
        XCTAssertEqual(handled["evt-1"]?.snapshot, CalendarCandidateLocationSnapshot(candidate: candidate))
    }
}

// MARK: - CalendarScanBackgroundTask identifier stability

/// Regression guard: the identifier must stay in sync with Info.plist's
/// BGTaskSchedulerPermittedIdentifiers and the `.backgroundTask(.appRefresh(_:))`
/// registration in NapStopApp.swift — a silent rename in one place but not the
/// others means the OS drops the scheduled task with no error.
final class CalendarScanBackgroundTaskIdentifierTests: XCTestCase {
    func test_identifier_isStable() {
        XCTAssertEqual(CalendarScanBackgroundTask.identifier, "com.rmbartis.GeoNap.calendarScanRefresh")
    }
}
