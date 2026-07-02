// CalendarScanServiceTests.swift
// Unit tests for the Calendar Scanning feature's pure logic:
//   • CalendarScanStorage — Set<String> <-> JSON round-trip
//   • CalendarSourceGroup.isPrimaryCandidate — Option C default-seed heuristic
//   • CalendarScanService.label(forSourceTypeRaw:) — EKSourceType display labels
//   • CalendarScanMode — rawValue/localizationKey/englishLabel mapping
//
// No EventKit permission or live calendar access is exercised here — those
// require a real device/simulator with calendar data and are out of scope
// for CI. This mirrors the "pure logic only" convention used elsewhere in
// this test target (see DebugLoggerTests's in-memory-only assertions).

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
        ]
        XCTAssertTrue(keys.allSatisfy { !$0.isEmpty })
        XCTAssertEqual(Set(keys).count, keys.count, "AppStorage keys must be unique")
    }
}
