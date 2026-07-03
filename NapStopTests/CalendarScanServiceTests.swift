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
//   • CalendarScanGeocodeRetrier.geocodeWithRetry(...) — retry-on-failure logic (2026-07-03)
//   • CalendarScanRefreshInterval — rawValue/localizationKey/englishLabel mapping,
//     resolve(storedMinutes:) fallback behavior (2026-07-04)
//
// No EventKit permission or live calendar access is exercised here — those
// require a real device/simulator with calendar data and are out of scope
// for CI. This mirrors the "pure logic only" convention used elsewhere in
// this test target (see DebugLoggerTests's in-memory-only assertions). The
// Phase 2 pipeline (scanForCandidates) touches EKEventStore directly and is
// intentionally left untested here for the same reason — only the pure
// extraction/date-range/filtering logic it calls into is covered.
//
// The geocoding step is the one exception: CalendarScanGeocodeRetrier takes
// a CalendarScanGeocoding protocol rather than calling MapKit directly, so
// its retry behavior (Bob's 2026-07-03 fix for a manual scan silently
// missing an event that a later scan picked up) IS fully covered below using
// a fake geocoder — no network or MapKit dependency required.

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

// MARK: - CalendarScanRefreshInterval
//
// Regression guard for the user-configurable background-refresh interval
// (Bob, 2026-07-04): a picker in Settings lets the user choose how often
// Automatic Calendar Scanning is *allowed* to refresh (1/2/4/8 hours), backed
// by CalendarScanBackgroundTask reading CalendarScanRefreshInterval instead
// of a hardcoded 4-hour constant.

final class CalendarScanRefreshIntervalTests: XCTestCase {

    func test_allCases_hasExactlyFourOptions() {
        XCTAssertEqual(CalendarScanRefreshInterval.allCases.count, 4)
    }

    func test_rawValuesAreMinutes() {
        XCTAssertEqual(CalendarScanRefreshInterval.oneHour.rawValue, 60)
        XCTAssertEqual(CalendarScanRefreshInterval.twoHours.rawValue, 120)
        XCTAssertEqual(CalendarScanRefreshInterval.fourHours.rawValue, 240)
        XCTAssertEqual(CalendarScanRefreshInterval.eightHours.rawValue, 480)
    }

    func test_timeInterval_convertsMinutesToSeconds() {
        XCTAssertEqual(CalendarScanRefreshInterval.oneHour.timeInterval, 3600)
        XCTAssertEqual(CalendarScanRefreshInterval.twoHours.timeInterval, 7200)
        XCTAssertEqual(CalendarScanRefreshInterval.fourHours.timeInterval, 14400)
        XCTAssertEqual(CalendarScanRefreshInterval.eightHours.timeInterval, 28800)
    }

    func test_localizationKeysAndEnglishLabels() {
        XCTAssertEqual(CalendarScanRefreshInterval.oneHour.localizationKey, "calendarScan.refreshInterval.oneHour")
        XCTAssertEqual(CalendarScanRefreshInterval.oneHour.englishLabel, "1 Hour — Most Frequent")
        XCTAssertEqual(CalendarScanRefreshInterval.twoHours.localizationKey, "calendarScan.refreshInterval.twoHours")
        XCTAssertEqual(CalendarScanRefreshInterval.twoHours.englishLabel, "2 Hours — Frequent")
        XCTAssertEqual(CalendarScanRefreshInterval.fourHours.localizationKey, "calendarScan.refreshInterval.fourHours")
        XCTAssertEqual(CalendarScanRefreshInterval.fourHours.englishLabel, "4 Hours — Balanced")
        XCTAssertEqual(CalendarScanRefreshInterval.eightHours.localizationKey, "calendarScan.refreshInterval.eightHours")
        XCTAssertEqual(CalendarScanRefreshInterval.eightHours.englishLabel, "8 Hours — Best Battery Life")
    }

    func test_default_isFourHours() {
        // Must match CalendarScanBackgroundTask's old hardcoded 4-hour
        // constant so nobody's behavior silently changes on upgrade.
        XCTAssertEqual(CalendarScanRefreshInterval.default, .fourHours)
    }

    func test_resolve_validStoredMinutes_returnsMatchingCase() {
        for interval in CalendarScanRefreshInterval.allCases {
            XCTAssertEqual(CalendarScanRefreshInterval.resolve(storedMinutes: interval.rawValue), interval)
        }
    }

    func test_resolve_zeroOrMissing_fallsBackToDefault() {
        // 0 is what UserDefaults.integer(forKey:) returns for an absent key —
        // e.g. an install from before this feature existed.
        XCTAssertEqual(CalendarScanRefreshInterval.resolve(storedMinutes: 0), .default)
    }

    func test_resolve_corruptValue_fallsBackToDefault() {
        XCTAssertEqual(CalendarScanRefreshInterval.resolve(storedMinutes: 999), .default)
        XCTAssertEqual(CalendarScanRefreshInterval.resolve(storedMinutes: -30), .default)
    }

    func test_initFromRawValue_roundTrips() {
        for interval in CalendarScanRefreshInterval.allCases {
            XCTAssertEqual(CalendarScanRefreshInterval(rawValue: interval.rawValue), interval)
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

// MARK: - CalendarScanGeocodeRetrier.geocodeWithRetry (2026-07-03)

/// Fails a configurable number of times before succeeding (or never
/// succeeds), and counts calls so tests can assert exactly how many attempts
/// the retry loop made. `retryDelay: 0` in every test below skips the real
/// backoff wait so this suite runs instantly.
private actor FakeGeocoder: CalendarScanGeocoding {
    private var failuresRemaining: Int
    private(set) var callCount = 0
    let coordinateOnSuccess: CLLocationCoordinate2D

    init(failuresBeforeSuccess: Int, coordinateOnSuccess: CLLocationCoordinate2D = CLLocationCoordinate2D(latitude: 1, longitude: 1)) {
        self.failuresRemaining = failuresBeforeSuccess
        self.coordinateOnSuccess = coordinateOnSuccess
    }

    func geocode(addressString: String) async -> CLLocationCoordinate2D? {
        callCount += 1
        guard failuresRemaining <= 0 else {
            failuresRemaining -= 1
            return nil
        }
        return coordinateOnSuccess
    }
}

/// Always fails — models an address that genuinely can't be geocoded (bad
/// address) as opposed to a transient hiccup.
private actor AlwaysFailingGeocoder: CalendarScanGeocoding {
    private(set) var callCount = 0
    func geocode(addressString: String) async -> CLLocationCoordinate2D? {
        callCount += 1
        return nil
    }
}

final class CalendarScanGeocodeRetrierTests: XCTestCase {

    func test_succeedsOnFirstAttempt_doesNotRetry() async {
        let geocoder = FakeGeocoder(failuresBeforeSuccess: 0)
        let result = await CalendarScanGeocodeRetrier.geocodeWithRetry(
            addressString: "123 Main St", geocoder: geocoder, maxRetries: 2, retryDelay: 0
        )
        XCTAssertNotNil(result)
        let calls = await geocoder.callCount
        XCTAssertEqual(calls, 1)
    }

    func test_failsOnceThenSucceeds_retriesExactlyOnce() async {
        // This is the exact scenario Bob hit: one transient failure that a
        // second attempt (moments later) resolves cleanly.
        let geocoder = FakeGeocoder(failuresBeforeSuccess: 1)
        let result = await CalendarScanGeocodeRetrier.geocodeWithRetry(
            addressString: "123 Main St", geocoder: geocoder, maxRetries: 2, retryDelay: 0
        )
        XCTAssertNotNil(result)
        let calls = await geocoder.callCount
        XCTAssertEqual(calls, 2, "First attempt failed, second succeeded — should stop retrying immediately on success")
    }

    func test_failsTwiceThenSucceeds_usesBothRetriesButStillSucceeds() async {
        let geocoder = FakeGeocoder(failuresBeforeSuccess: 2)
        let result = await CalendarScanGeocodeRetrier.geocodeWithRetry(
            addressString: "123 Main St", geocoder: geocoder, maxRetries: 2, retryDelay: 0
        )
        XCTAssertNotNil(result)
        let calls = await geocoder.callCount
        XCTAssertEqual(calls, 3, "Two failures + one final successful attempt = 3 total")
    }

    func test_alwaysFails_givesUpAfterMaxRetriesPlusOne_returnsNil() async {
        let geocoder = AlwaysFailingGeocoder()
        let result = await CalendarScanGeocodeRetrier.geocodeWithRetry(
            addressString: "123 Main St", geocoder: geocoder, maxRetries: 2, retryDelay: 0
        )
        XCTAssertNil(result, "A genuinely bad address should still be skipped, not retried forever")
        let calls = await geocoder.callCount
        XCTAssertEqual(calls, 3, "1 initial attempt + 2 retries = 3 total, then gives up")
    }

    func test_zeroMaxRetries_onlyTriesOnce() async {
        let geocoder = AlwaysFailingGeocoder()
        let result = await CalendarScanGeocodeRetrier.geocodeWithRetry(
            addressString: "123 Main St", geocoder: geocoder, maxRetries: 0, retryDelay: 0
        )
        XCTAssertNil(result)
        let calls = await geocoder.callCount
        XCTAssertEqual(calls, 1)
    }

    func test_returnedCoordinate_matchesGeocodersResult() async {
        let expected = CLLocationCoordinate2D(latitude: 43.6452, longitude: -79.3806)
        let geocoder = FakeGeocoder(failuresBeforeSuccess: 0, coordinateOnSuccess: expected)
        let result = await CalendarScanGeocodeRetrier.geocodeWithRetry(
            addressString: "Union Station", geocoder: geocoder, maxRetries: 2, retryDelay: 0
        )
        XCTAssertEqual(result?.latitude, expected.latitude)
        XCTAssertEqual(result?.longitude, expected.longitude)
    }
}

// MARK: - MapKitGeocoder

final class MapKitGeocoderTests: XCTestCase {
    func test_conformsToCalendarScanGeocoding() {
        // Compile-time guard: production code depends on this conformance to
        // inject MapKitGeocoder as CalendarScanService's default geocoder.
        let geocoder: CalendarScanGeocoding = MapKitGeocoder()
        XCTAssertNotNil(geocoder)
    }
}
