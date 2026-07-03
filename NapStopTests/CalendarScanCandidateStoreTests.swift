// CalendarScanCandidateStoreTests.swift
// Unit tests for Phase 3's dedup/re-offer logic:
//   • CalendarScanCandidateMerger.mergeScanResults(found:existingPending:handled:)
//   • CalendarScanCandidateMerger.applyDecision(_:to:pending:handled:)
//   • CalendarScanCandidateMerger.staleAlarm(for:in:) — stale-alarm-on-re-add fix (2026-07-03)
//   • CalendarScanCandidateMerger.reconcileHandled(_:existingAlarmEventIDs:) — deleted-alarm re-offer fix (2026-07-03)
//   • CalendarCandidateLocationSnapshot / CalendarScanHandledRecord Codable round-trip
//   • CalendarScanBackgroundTask.identifier / CalendarScanNotifier.requestIdentifier /
//     Notification.Name.calendarScanReviewRequested — cross-file identifier stability guards
//   • CalendarScanRefreshScheduling.shouldSubmit(force:existingEarliestDate:now:) —
//     background-refresh clock-reset-on-every-foreground fix (2026-07-03)
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

// MARK: - CalendarScanCandidateMerger.staleAlarm

/// Regression guard for the "old alarm not removed when the calendar event
/// changes" bug Bob reported 2026-07-03: a re-offered candidate (its event's
/// location changed since being added) needs its previous alarm found so it
/// can be replaced instead of left as a duplicate.
final class CalendarScanCandidateMergerStaleAlarmTests: XCTestCase {

    func test_matchingCalendarEventID_isFound() {
        let candidate = makeCandidate(id: "evt-1")
        let alarm = NapAlarm(name: "Old Location", latitude: 1, longitude: 1, calendarEventID: "evt-1")
        let result = CalendarScanCandidateMerger.staleAlarm(for: candidate, in: [alarm])
        XCTAssertEqual(result?.name, "Old Location")
    }

    func test_noMatchingAlarm_returnsNil() {
        let candidate = makeCandidate(id: "evt-1")
        let alarm = NapAlarm(name: "Unrelated", latitude: 1, longitude: 1, calendarEventID: "evt-2")
        XCTAssertNil(CalendarScanCandidateMerger.staleAlarm(for: candidate, in: [alarm]))
    }

    func test_ordinaryManuallyCreatedAlarms_areIgnored() {
        // Alarms not created via Calendar Scanning have calendarEventID == nil
        // and must never be matched, even against a malformed/empty candidate id.
        let candidate = makeCandidate(id: "evt-1")
        let manualAlarm = NapAlarm(name: "Manual Alarm", latitude: 1, longitude: 1)
        XCTAssertNil(manualAlarm.calendarEventID)
        XCTAssertNil(CalendarScanCandidateMerger.staleAlarm(for: candidate, in: [manualAlarm]))
    }

    func test_multipleAlarms_picksTheOneMatchingThisEvent() {
        let candidate = makeCandidate(id: "evt-2")
        let other = NapAlarm(name: "Other Event", latitude: 1, longitude: 1, calendarEventID: "evt-1")
        let match = NapAlarm(name: "Right Event", latitude: 2, longitude: 2, calendarEventID: "evt-2")
        let manual = NapAlarm(name: "Manual", latitude: 3, longitude: 3)
        let result = CalendarScanCandidateMerger.staleAlarm(for: candidate, in: [other, match, manual])
        XCTAssertEqual(result?.name, "Right Event")
    }

    func test_emptyAlarmList_returnsNil() {
        let candidate = makeCandidate(id: "evt-1")
        XCTAssertNil(CalendarScanCandidateMerger.staleAlarm(for: candidate, in: []))
    }
}

// MARK: - CalendarScanCandidateMerger.reconcileHandled

/// Regression guard for the "deleted alarm's event never re-offered" bug Bob
/// reported 2026-07-03: an "added" handled record must be cleared once its
/// alarm no longer exists, so the next scan (manual or automatic) treats the
/// event as new again instead of leaving it silently suppressed forever.
final class CalendarScanCandidateMergerReconcileHandledTests: XCTestCase {

    func test_addedRecordWithExistingAlarm_isKept() {
        let handled: [String: CalendarScanHandledRecord] = [
            "evt-1": CalendarScanHandledRecord(action: .added, snapshot: CalendarCandidateLocationSnapshot(locationTitle: "X", latitude: 1, longitude: 1))
        ]
        let result = CalendarScanCandidateMerger.reconcileHandled(handled, existingAlarmEventIDs: ["evt-1"])
        XCTAssertNotNil(result["evt-1"])
    }

    func test_addedRecordWithDeletedAlarm_isRemoved() {
        let handled: [String: CalendarScanHandledRecord] = [
            "evt-1": CalendarScanHandledRecord(action: .added, snapshot: CalendarCandidateLocationSnapshot(locationTitle: "X", latitude: 1, longitude: 1))
        ]
        let result = CalendarScanCandidateMerger.reconcileHandled(handled, existingAlarmEventIDs: [])
        XCTAssertNil(result["evt-1"], "The alarm for this event no longer exists — it should be eligible for re-offer")
    }

    func test_declinedRecord_isNeverRemoved_regardlessOfAlarmExistence() {
        // Declines were never tied to any alarm, so alarm-existence is irrelevant to them.
        let handled: [String: CalendarScanHandledRecord] = [
            "evt-1": CalendarScanHandledRecord(action: .declined, snapshot: CalendarCandidateLocationSnapshot(locationTitle: "X", latitude: 1, longitude: 1))
        ]
        let result = CalendarScanCandidateMerger.reconcileHandled(handled, existingAlarmEventIDs: [])
        XCTAssertNotNil(result["evt-1"])
    }

    func test_mixedRecords_onlyStaleAddedRecordsAreRemoved() {
        let handled: [String: CalendarScanHandledRecord] = [
            "kept-added":  CalendarScanHandledRecord(action: .added,    snapshot: CalendarCandidateLocationSnapshot(locationTitle: "A", latitude: 1, longitude: 1)),
            "stale-added": CalendarScanHandledRecord(action: .added,    snapshot: CalendarCandidateLocationSnapshot(locationTitle: "B", latitude: 2, longitude: 2)),
            "declined":    CalendarScanHandledRecord(action: .declined, snapshot: CalendarCandidateLocationSnapshot(locationTitle: "C", latitude: 3, longitude: 3)),
        ]
        let result = CalendarScanCandidateMerger.reconcileHandled(handled, existingAlarmEventIDs: ["kept-added"])
        XCTAssertEqual(Set(result.keys), ["kept-added", "declined"])
    }

    func test_emptyHandled_returnsEmpty() {
        XCTAssertTrue(CalendarScanCandidateMerger.reconcileHandled([:], existingAlarmEventIDs: ["evt-1"]).isEmpty)
    }

    func test_emptyExistingAlarms_removesAllAddedRecords() {
        let handled: [String: CalendarScanHandledRecord] = [
            "a": CalendarScanHandledRecord(action: .added, snapshot: CalendarCandidateLocationSnapshot(locationTitle: "A", latitude: 1, longitude: 1)),
            "b": CalendarScanHandledRecord(action: .added, snapshot: CalendarCandidateLocationSnapshot(locationTitle: "B", latitude: 2, longitude: 2)),
        ]
        XCTAssertTrue(CalendarScanCandidateMerger.reconcileHandled(handled, existingAlarmEventIDs: []).isEmpty)
    }

    /// Integration-style test at the pure-logic level: reconciling a deleted
    /// alarm's record, then feeding the result into mergeScanResults, should
    /// re-surface the event as newly-pending — exactly what a subsequent
    /// scan (manual or automatic) needs to do end-to-end.
    func test_reconciledThenMerged_reOffersTheDeletedAlarmsEvent() {
        let candidate = makeCandidate(id: "evt-1", locationTitle: "Union Station")
        let handled: [String: CalendarScanHandledRecord] = [
            "evt-1": CalendarScanHandledRecord(action: .added, snapshot: CalendarCandidateLocationSnapshot(candidate: candidate))
        ]
        let reconciled = CalendarScanCandidateMerger.reconcileHandled(handled, existingAlarmEventIDs: [])
        let result = CalendarScanCandidateMerger.mergeScanResults(found: [candidate], existingPending: [], handled: reconciled)
        XCTAssertEqual(result.pending.map(\.id), ["evt-1"])
        XCTAssertEqual(result.newlyPendingIDs, ["evt-1"], "Should be treated as new again, same as a never-before-seen event")
    }

    /// Companion case: if the alarm still exists, reconciliation must be a
    /// no-op and the event should stay suppressed as "already handled" —
    /// guards against reconcileHandled over-clearing.
    func test_reconciledThenMerged_stillSuppressesWhenAlarmStillExists() {
        let candidate = makeCandidate(id: "evt-1", locationTitle: "Union Station")
        let handled: [String: CalendarScanHandledRecord] = [
            "evt-1": CalendarScanHandledRecord(action: .added, snapshot: CalendarCandidateLocationSnapshot(candidate: candidate))
        ]
        let reconciled = CalendarScanCandidateMerger.reconcileHandled(handled, existingAlarmEventIDs: ["evt-1"])
        let result = CalendarScanCandidateMerger.mergeScanResults(found: [candidate], existingPending: [], handled: reconciled)
        XCTAssertTrue(result.pending.isEmpty, "Alarm still exists — the event must stay suppressed")
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

// MARK: - CalendarScanRefreshScheduling
//
// Regression guard for the "clock keeps resetting on every app foreground"
// fix (Bob, 2026-07-03): scheduleNextRefresh() used to unconditionally
// cancel + resubmit with `earliestBeginDate = now + 4h` on every call,
// including from RootView.onAppear, which fires on every foreground — not
// just cold launch. For anyone who opens the app more than once every 4
// hours, the window kept getting pushed out and the background scan could
// never actually become eligible to run. shouldSubmit() is the pure decision
// that fixes this: only submit a fresh request if none is pending yet, its
// window has already opened, or the caller explicitly forces it.
final class CalendarScanRefreshSchedulingTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func test_noExistingRequest_submits() {
        XCTAssertTrue(CalendarScanRefreshScheduling.shouldSubmit(force: false, existingEarliestDate: nil, now: now))
    }

    func test_existingRequestStillInFuture_doesNotResubmit() {
        // This is the exact scenario that produced Bob's bug: a request is
        // already pending 3 hours out, and scheduleNextRefresh() gets called
        // again (e.g. app foregrounded) before that window opens.
        let threeHoursOut = now.addingTimeInterval(3 * 60 * 60)
        XCTAssertFalse(CalendarScanRefreshScheduling.shouldSubmit(force: false, existingEarliestDate: threeHoursOut, now: now))
    }

    func test_existingRequestInPast_resubmits() {
        // The tracked date can lag reality (e.g. a run() that hasn't reached
        // its own reschedule yet) — once the window has already opened, it's
        // safe (and correct) to submit a fresh one.
        let oneHourAgo = now.addingTimeInterval(-60 * 60)
        XCTAssertTrue(CalendarScanRefreshScheduling.shouldSubmit(force: false, existingEarliestDate: oneHourAgo, now: now))
    }

    func test_existingRequestExactlyNow_resubmits() {
        XCTAssertTrue(CalendarScanRefreshScheduling.shouldSubmit(force: false, existingEarliestDate: now, now: now))
    }

    func test_force_alwaysResubmitsRegardlessOfExistingDate() {
        let farFuture = now.addingTimeInterval(3 * 60 * 60)
        XCTAssertTrue(CalendarScanRefreshScheduling.shouldSubmit(force: true, existingEarliestDate: farFuture, now: now))
        XCTAssertTrue(CalendarScanRefreshScheduling.shouldSubmit(force: true, existingEarliestDate: nil, now: now))
    }
}

// MARK: - Notification tap deep link identifier stability
//
// Regression guard for the notification-tap deep link (Bob, 2026-07-03):
// CalendarScanNotifier posts the "new trips found" notification under
// `requestIdentifier`, and CalendarScanNotificationDelegate compares an
// incoming tap's identifier against that same constant to decide whether to
// post `.calendarScanReviewRequested`. A silent rename on either side would
// break the deep link with no compiler error and no visible symptom besides
// "tapping the notification does nothing."
final class CalendarScanNotifierIdentifierTests: XCTestCase {
    func test_requestIdentifier_isStable() {
        XCTAssertEqual(CalendarScanNotifier.requestIdentifier, "com.rmbartis.GeoNap.calendarScanNewTrips")
    }
}

final class CalendarScanReviewRequestedNotificationNameTests: XCTestCase {
    func test_notificationName_isStable() {
        XCTAssertEqual(Notification.Name.calendarScanReviewRequested.rawValue, "com.rmbartis.GeoNap.calendarScanReviewRequested")
    }
}
