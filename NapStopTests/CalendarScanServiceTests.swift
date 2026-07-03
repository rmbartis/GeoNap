// CalendarScanServiceTests.swift
// Unit tests for the Calendar Scanning feature's pure logic:
//   • CalendarScanStorage — Set<String> <-> JSON round-trip
//   • CalendarSourceGroup.isPrimaryCandidate — Option C default-seed heuristic
//   • CalendarScanService.label(forSourceTypeRaw:) — EKSourceType display labels
//   • CalendarScanMode — rawValue/localizationKey/englishLabel mapping
//   • CalendarScanService.isScannable(sourceTypeRaw:) — Birthdays/Holidays filter (Phase 2)
//   • CalendarScanService.scanDateRange(from:lookaheadDays:calendar:) — look-ahead window math (Phase 2)
//   • CalendarScanLocationExtractor.extract(from:) — structuredLocation-first, geocode-fallback logic (Phase 2)
//   • CalendarTripCandidate.coordinate — computed CLLocationCoordinate2D (Phase 2)
//
// No EventKit permission or live calendar access is exercised here — those
// require a real device/simulator with calendar data and are out of scope
// for CI. This mirrors the "pure logic only" convention used elsewhere in
// this test target (see DebugLoggerTests's in-memory-only assertions). The
// Phase 2 pipeline (scanForCandidates) touches EKEventStore/CLGeocoder
// directly and is intentionally left untested here for the same reason —
// only the pure extraction/date-range/filtering logic it calls into is
// covered.

import XCTest
import EventKit
@testable import GeoNap

// MARK: - CalendarScanStorage

final class CalendarScanStorageTests: XCTestCase {

    func test_encodeDecode_roundTrip_preservesAllValues() {
        let original: Set<String> = ["cal-a", "cal-b", "cal-c"]
        let encoded = CalendarScanStorage.encodeStringSet(original)
        let decoded = CalendarScanStorage.decodeStringSet(encoded)
        XCTAssertEqual(decoded, original)
    }

    func test_encode_emptySet_producesEmptyArrayJSON() {
        let encoded = CalendarScanStorage.encodeStringSet([])
        XCTAssertEqual(encoded, "[]")
    }

    func test_decode_emptyArrayJSON_producesEmptySet() {
        XCTAssertEqual(CalendarScanStorage.decodeStringSet("[]"), [])
    }

    func test_decode_malformedJSON_returnsEmptySetRatherThanCrashing() {
        XCTAssertEqual(CalendarScanStorage.decodeStringSet("not json"), [])
        XCTAssertEqual(CalendarScanStorage.decodeStringSet(""), [])
    }

    func test_encode_isDeterministic_regardlessOfInsertionOrder() {
        let a = CalendarScanStorage.encodeStringSet(["z", "a", "m"])
        let b = CalendarScanStorage.encodeStringSet(["m", "z", "a"])
        XCTAssertEqual(a, b, "Encoding must sort before serializing so stored values are stable")
    }
}

// MARK: - CalendarSourceGroup.isPrimaryCandidate

final class CalendarSourceGroupPrimaryCandidateTests: XCTestCase {

    private func group(id: String = "id", title: String, sourceTypeRaw: Int) -> CalendarSourceGroup {
        CalendarSourceGroup(id: id, title: title, sourceTypeRaw: sourceTypeRaw, calendars: [])
    }

    func test_localSource_isPrimaryCandidate() {
        let g = group(title: "On My iPhone", sourceTypeRaw: EKSourceType.local.rawValue)
        XCTAssertTrue(g.isPrimaryCandidate)
    }

    func test_calDAVSourceNamedICloud_isPrimaryCandidate() {
        let g = group(title: "iCloud", sourceTypeRaw: EKSourceType.calDAV.rawValue)
        XCTAssertTrue(g.isPrimaryCandidate)
    }

    func test_calDAVSourceNamedICloud_caseInsensitiveMatch() {
        let g = group(title: "ICLOUD", sourceTypeRaw: EKSourceType.calDAV.rawValue)
        XCTAssertTrue(g.isPrimaryCandidate)
    }

    func test_calDAVSourceNotICloud_isNotPrimaryCandidate() {
        let g = group(title: "Work CalDAV", sourceTypeRaw: EKSourceType.calDAV.rawValue)
        XCTAssertFalse(g.isPrimaryCandidate)
    }

    func test_exchangeSource_isNotPrimaryCandidate() {
        let g = group(title: "Work Exchange", sourceTypeRaw: EKSourceType.exchange.rawValue)
        XCTAssertFalse(g.isPrimaryCandidate)
    }

    func test_subscribedSource_isNotPrimaryCandidate() {
        let g = group(title: "Holidays", sourceTypeRaw: EKSourceType.subscribed.rawValue)
        XCTAssertFalse(g.isPrimaryCandidate)
    }
}

// MARK: - CalendarScanService.label(forSourceTypeRaw:)

final class CalendarScanServiceLabelTests: XCTestCase {

    func test_local_hasExpectedLabel() {
        XCTAssertEqual(CalendarScanService.label(forSourceTypeRaw: EKSourceType.local.rawValue), "On My iPhone")
    }

    func test_calDAV_hasExpectedLabel() {
        XCTAssertEqual(CalendarScanService.label(forSourceTypeRaw: EKSourceType.calDAV.rawValue), "iCloud / CalDAV")
    }

    func test_exchange_hasExpectedLabel() {
        XCTAssertEqual(CalendarScanService.label(forSourceTypeRaw: EKSourceType.exchange.rawValue), "Exchange")
    }

    func test_subscribed_hasExpectedLabel() {
        XCTAssertEqual(CalendarScanService.label(forSourceTypeRaw: EKSourceType.subscribed.rawValue), "Subscribed")
    }

    func test_birthdays_hasExpectedLabel() {
        XCTAssertEqual(CalendarScanService.label(forSourceTypeRaw: EKSourceType.birthdays.rawValue), "Birthdays")
    }

    func test_mobileMe_hasExpectedLabel() {
        XCTAssertEqual(CalendarScanService.label(forSourceTypeRaw: EKSourceType.mobileMe.rawValue), "iCloud (MobileMe)")
    }

    func test_unknownRawValue_fallsBackToOther() {
        XCTAssertEqual(CalendarScanService.label(forSourceTypeRaw: 9999), "Other")
    }
}

// MARK: - CalendarScanMode

final class CalendarScanModeTests: XCTestCase {

    func test_allCases_hasExactlyTwoModes() {
        XCTAssertEqual(CalendarScanMode.allCases.count, 2)
    }

    func test_automatic_rawValueAndKeys() {
        let mode = CalendarScanMode.automatic
        XCTAssertEqual(mode.rawValue, "automatic")
        XCTAssertEqual(mode.id, "automatic")
        XCTAssertEqual(mode.localizationKey, "calendarScan.mode.automatic")
        XCTAssertEqual(mode.englishLabel, "Automatic")
    }

    func test_manualOnly_rawValueAndKeys() {
        let mode = CalendarScanMode.manualOnly
        XCTAssertEqual(mode.rawValue, "manualOnly")
        XCTAssertEqual(mode.id, "manualOnly")
        XCTAssertEqual(mode.localizationKey, "calendarScan.mode.manualOnly")
        XCTAssertEqual(mode.englishLabel, "Manual Only")
    }

    func test_initFromRawValue_roundTrips() {
        for mode in CalendarScanMode.allCases {
            XCTAssertEqual(CalendarScanMode(rawValue: mode.rawValue), mode)
        }
    }
}

// MARK: - AppStorageKey defaults

final class CalendarScanAppStorageKeyTests: XCTestCase {

    /// Regression guard for the explicit product requirement: calendar
    /// scanning must be off until the user turns it on. This test doesn't
    /// read AppStorage (no @AppStorage in a plain XCTestCase), but it pins
    /// down the key string so a future rename doesn't silently orphan the
    /// stored default in UserDefaults.
    func test_calendarScanEnabledKey_isStable() {
        XCTAssertEqual(AppStorageKey.calendarScanEnabled, "calendarScanEnabled")
    }

    func test_allCalendarScanKeys_areNonEmptyAndUnique() {
        let keys = [
            AppStorageKey.calendarScanEnabled,
            AppStorageKey.calendarScanModeRaw,
            AppStorageKey.calendarScanNotifyOnResults,
            AppStorageKey.calendarScanLookaheadDays,
            AppStorageKey.calendarScanEnabledCalendarIDs,
            AppStorageKey.calendarScanHasCompletedFirstRun,
            AppStorageKey.calendarScanPendingCandidatesJSON,
            AppStorageKey.calendarScanHandledCandidatesJSON,
        ]
        XCTAssertTrue(keys.allSatisfy { !$0.isEmpty })
        XCTAssertEqual(Set(keys).count, keys.count, "AppStorage keys must be unique")
    }
}

// MARK: - CalendarScanService.isScannable(sourceTypeRaw:) (Phase 2)

/// Regression guard for Bob's 2026-07-02 decision to drop the synthetic
/// .birthdays source (Birthdays + Holidays calendars) from the scan picker,
/// since neither calendar ever carries a usable location.
final class CalendarScanServiceIsScannableTests: XCTestCase {

    func test_birthdays_isNotScannable() {
        XCTAssertFalse(CalendarScanService.isScannable(sourceTypeRaw: EKSourceType.birthdays.rawValue))
    }

    func test_local_isScannable() {
        XCTAssertTrue(CalendarScanService.isScannable(sourceTypeRaw: EKSourceType.local.rawValue))
    }

    func test_calDAV_isScannable() {
        XCTAssertTrue(CalendarScanService.isScannable(sourceTypeRaw: EKSourceType.calDAV.rawValue))
    }

    func test_exchange_isScannable() {
        XCTAssertTrue(CalendarScanService.isScannable(sourceTypeRaw: EKSourceType.exchange.rawValue))
    }

    func test_subscribed_isScannable() {
        XCTAssertTrue(CalendarScanService.isScannable(sourceTypeRaw: EKSourceType.subscribed.rawValue))
    }

    func test_mobileMe_isScannable() {
        XCTAssertTrue(CalendarScanService.isScannable(sourceTypeRaw: EKSourceType.mobileMe.rawValue))
    }

    func test_unknownRawValue_isScannable() {
        // EKSourceType(rawValue:) returns nil for unrecognized raw values,
        // and nil != .birthdays, so unknown types default to scannable
        // rather than silently being dropped.
        XCTAssertTrue(CalendarScanService.isScannable(sourceTypeRaw: 9999))
    }
}

// MARK: - CalendarScanService.isScannable(calendarTitle:) (Phase 3)

/// Regression guard for Bob's 2026-07-02 follow-up: "US Holidays" (a plain
/// .subscribed calendar, not the synthetic .birthdays source) was still
/// showing up in the live app's calendar picker and needed removing too.
final class CalendarScanServiceCalendarTitleScannableTests: XCTestCase {

    func test_usHolidays_isNotScannable() {
        XCTAssertFalse(CalendarScanService.isScannable(calendarTitle: "US Holidays"))
    }

    func test_holidaysInCountry_isNotScannable() {
        XCTAssertFalse(CalendarScanService.isScannable(calendarTitle: "Holidays in United States"))
    }

    func test_match_isCaseInsensitive() {
        XCTAssertFalse(CalendarScanService.isScannable(calendarTitle: "hOlIdAy Calendar"))
    }

    func test_ordinaryCalendarName_isScannable() {
        XCTAssertTrue(CalendarScanService.isScannable(calendarTitle: "Work"))
        XCTAssertTrue(CalendarScanService.isScannable(calendarTitle: "Family"))
        XCTAssertTrue(CalendarScanService.isScannable(calendarTitle: "Travel"))
    }

    func test_emptyTitle_isScannable() {
        XCTAssertTrue(CalendarScanService.isScannable(calendarTitle: ""))
    }
}

// MARK: - CalendarScanService.scanDateRange(from:lookaheadDays:calendar:) (Phase 2)

final class CalendarScanServiceDateRangeTests: XCTestCase {

    private let calendar = Calendar(identifier: .gregorian)

    func test_zeroLookaheadDays_returnsNil() {
        XCTAssertNil(CalendarScanService.scanDateRange(from: Date(), lookaheadDays: 0, calendar: calendar))
    }

    func test_negativeLookaheadDays_returnsNil() {
        XCTAssertNil(CalendarScanService.scanDateRange(from: Date(), lookaheadDays: -5, calendar: calendar))
    }

    func test_positiveLookaheadDays_startEqualsNow() {
        let now = Date()
        let range = CalendarScanService.scanDateRange(from: now, lookaheadDays: 14, calendar: calendar)
        XCTAssertEqual(range?.start, now)
    }

    func test_fourteenDayLookahead_endIsFourteenDaysLater() {
        let now = Date()
        guard let range = CalendarScanService.scanDateRange(from: now, lookaheadDays: 14, calendar: calendar) else {
            return XCTFail("Expected a non-nil range for a positive lookahead")
        }
        let expectedEnd = calendar.date(byAdding: .day, value: 14, to: now)
        XCTAssertEqual(range.end, expectedEnd)
    }

    func test_oneDayLookahead_endIsOneDayLater() {
        let now = Date()
        guard let range = CalendarScanService.scanDateRange(from: now, lookaheadDays: 1, calendar: calendar) else {
            return XCTFail("Expected a non-nil range for a positive lookahead")
        }
        let expectedEnd = calendar.date(byAdding: .day, value: 1, to: now)
        XCTAssertEqual(range.end, expectedEnd)
    }
}

// MARK: - CalendarScanLocationExtractor.extract(from:) (Phase 2)

final class CalendarScanLocationExtractorTests: XCTestCase {

    func test_validStructuredLocation_preferredOverPlainLocation() {
        let input = CalendarEventLocationInput(
            structuredLocationTitle: "Union Station",
            structuredLocationLatitude: 43.6452,
            structuredLocationLongitude: -79.3806,
            plainLocation: "Some other address"
        )
        let result = CalendarScanLocationExtractor.extract(from: input)
        XCTAssertEqual(result?.title, "Union Station")
        XCTAssertEqual(result?.latitude, 43.6452)
        XCTAssertEqual(result?.longitude, -79.3806)
        XCTAssertEqual(result?.source, .structured)
    }

    func test_structuredLocationWithoutTitle_fallsBackToPlainLocationForTitle() {
        let input = CalendarEventLocationInput(
            structuredLocationTitle: nil,
            structuredLocationLatitude: 43.6452,
            structuredLocationLongitude: -79.3806,
            plainLocation: "123 Front St"
        )
        let result = CalendarScanLocationExtractor.extract(from: input)
        XCTAssertEqual(result?.title, "123 Front St")
        XCTAssertEqual(result?.source, .structured)
    }

    func test_structuredLocationWithBlankTitleAndNoPlainLocation_producesEmptyTitle() {
        let input = CalendarEventLocationInput(
            structuredLocationTitle: "   ",
            structuredLocationLatitude: 43.6452,
            structuredLocationLongitude: -79.3806,
            plainLocation: nil
        )
        let result = CalendarScanLocationExtractor.extract(from: input)
        XCTAssertEqual(result?.title, "")
        XCTAssertEqual(result?.source, .structured)
    }

    func test_zeroZeroStructuredCoordinate_treatedAsInvalid_fallsBackToPlainLocation() {
        // (0, 0) is a real coordinate off the coast of Africa but is almost
        // always a sentinel/uninitialized value from a mis-tagged event —
        // fall back to geocoding the plain-text location instead.
        let input = CalendarEventLocationInput(
            structuredLocationTitle: "Bad Tag",
            structuredLocationLatitude: 0,
            structuredLocationLongitude: 0,
            plainLocation: "456 King St"
        )
        let result = CalendarScanLocationExtractor.extract(from: input)
        XCTAssertEqual(result?.title, "456 King St")
        XCTAssertNil(result?.latitude)
        XCTAssertNil(result?.longitude)
        XCTAssertEqual(result?.source, .geocoded)
    }

    func test_zeroZeroStructuredCoordinateAndNoPlainLocation_returnsNil() {
        let input = CalendarEventLocationInput(
            structuredLocationTitle: "Bad Tag",
            structuredLocationLatitude: 0,
            structuredLocationLongitude: 0,
            plainLocation: nil
        )
        XCTAssertNil(CalendarScanLocationExtractor.extract(from: input))
    }

    func test_onlyPlainLocation_producesGeocodedSourceWithNilCoordinates() {
        let input = CalendarEventLocationInput(plainLocation: "789 Bay St")
        let result = CalendarScanLocationExtractor.extract(from: input)
        XCTAssertEqual(result?.title, "789 Bay St")
        XCTAssertNil(result?.latitude)
        XCTAssertNil(result?.longitude)
        XCTAssertEqual(result?.source, .geocoded)
    }

    func test_plainLocation_isTrimmedOfWhitespace() {
        let input = CalendarEventLocationInput(plainLocation: "  789 Bay St  \n")
        let result = CalendarScanLocationExtractor.extract(from: input)
        XCTAssertEqual(result?.title, "789 Bay St")
    }

    func test_blankPlainLocationAndNoStructuredLocation_returnsNil() {
        let input = CalendarEventLocationInput(plainLocation: "   ")
        XCTAssertNil(CalendarScanLocationExtractor.extract(from: input))
    }

    func test_noLocationDataAtAll_returnsNil() {
        let input = CalendarEventLocationInput()
        XCTAssertNil(CalendarScanLocationExtractor.extract(from: input))
    }

    func test_onlyOneOfLatLonPresent_ignoresStructuredLocation_fallsBackToPlain() {
        // A partially-populated structuredLocation (e.g. latitude without
        // longitude) should never be treated as valid.
        let input = CalendarEventLocationInput(
            structuredLocationTitle: "Half Tagged",
            structuredLocationLatitude: 43.6452,
            structuredLocationLongitude: nil,
            plainLocation: "Fallback Address"
        )
        let result = CalendarScanLocationExtractor.extract(from: input)
        XCTAssertEqual(result?.title, "Fallback Address")
        XCTAssertEqual(result?.source, .geocoded)
    }

    /// `notes` is intentionally excluded as a location source (Bob's Phase 2
    /// design decision, 2026-07-02) — structurally guaranteed here since
    /// CalendarEventLocationInput has no `notes` field at all, so there's no
    /// runtime path by which it could leak into extraction.
    func test_eventLocationInput_hasNoNotesField() {
        let mirror = Mirror(reflecting: CalendarEventLocationInput())
        let fieldNames = mirror.children.compactMap(\.label)
        XCTAssertFalse(fieldNames.contains("notes"))
    }
}

// MARK: - CalendarTripCandidate.coordinate (Phase 2)

final class CalendarTripCandidateTests: XCTestCase {

    func test_coordinate_matchesLatitudeAndLongitudeFields() {
        let candidate = CalendarTripCandidate(
            id: "evt-1",
            title: "Flight to YYZ",
            startDate: Date(),
            calendarID: "cal-1",
            locationTitle: "Pearson Airport",
            latitude: 43.6777,
            longitude: -79.6248
        )
        XCTAssertEqual(candidate.coordinate.latitude, 43.6777)
        XCTAssertEqual(candidate.coordinate.longitude, -79.6248)
    }
}
