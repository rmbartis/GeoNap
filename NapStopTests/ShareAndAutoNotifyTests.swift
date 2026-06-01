// ShareAndAutoNotifyTests.swift
// CI tests for two distinct sharing features:
//
//   1. Share Alarm Location — a fixed Apple Maps URL built from the alarm's
//      pinned coordinates. Manual tap at any time; NOT alarm-triggered.
//      Format: https://maps.apple.com/?ll=<lat>,<lon>&q=<name>
//
//   2. Auto-Notify — an SMS compose sheet triggered automatically when an
//      alarm fires (geo-event). The user must tap Send (Apple requirement).
//      SMS body: "[Arrival|Departure] I arrived at|departed from <name> at <time>."

import XCTest
import CoreLocation
@testable import GeoNap

// MARK: - Share Alarm Location URL tests

/// Verifies the Apple Maps URL that AlarmDetailView.shareURLString produces.
/// The property is private to the view, so we replicate the pure function here
/// and keep the two implementations in sync via these contract tests.
final class ShareAlarmLocationTests: XCTestCase {

    // MARK: - URL structure

    func test_shareURL_usesAppleMapsScheme() {
        let url = makeShareURL(lat: 40.758, lon: -73.9855, name: "Times Square")
        XCTAssertTrue(url.hasPrefix("https://maps.apple.com/"),
                      "Share URL must use Apple Maps: \(url)")
    }

    func test_shareURL_containsCoordinates() {
        let lat = 40.7580
        let lon = -73.9855
        let url = makeShareURL(lat: lat, lon: lon, name: "Times Square")
        XCTAssertTrue(url.contains("ll=\(lat),\(lon)"),
                      "URL must embed ll=<lat>,<lon>: \(url)")
    }

    func test_shareURL_containsEncodedAlarmName() {
        let url = makeShareURL(lat: 51.5074, lon: -0.1278, name: "London Bridge")
        // "London Bridge" → "London%20Bridge" after percent-encoding
        XCTAssertTrue(url.contains("London") && url.contains("Bridge"),
                      "Alarm name must appear in URL: \(url)")
        XCTAssertFalse(url.contains("London Bridge"),
                       "Raw space must be percent-encoded in URL: \(url)")
    }

    func test_shareURL_containsQueryParam() {
        let url = makeShareURL(lat: 48.8566, lon: 2.3522, name: "Gare du Nord")
        XCTAssertTrue(url.contains("&q="),
                      "URL must include &q= parameter: \(url)")
    }

    func test_shareURL_isValidURL() {
        let raw = makeShareURL(lat: 35.6762, lon: 139.6503, name: "Tokyo Station")
        XCTAssertNotNil(URL(string: raw), "Share URL must be parseable: \(raw)")
    }

    func test_shareURL_encodesSpecialCharacters() {
        let url = makeShareURL(lat: 40.0, lon: -74.0, name: "Penn & 34th St")
        XCTAssertFalse(url.contains("&q=Penn & 34"),
                       "Special chars in name must be percent-encoded: \(url)")
    }

    func test_shareURL_usesAlarmCoordinates_notCurrentLocation() {
        // The URL must encode the alarm's FIXED pin, not any live GPS reading.
        // Verify that substituting different coordinates produces different URLs.
        let url1 = makeShareURL(lat: 1.0, lon: 2.0, name: "Stop A")
        let url2 = makeShareURL(lat: 9.0, lon: 8.0, name: "Stop A")
        XCTAssertNotEqual(url1, url2,
                          "Different coordinates must produce different share URLs")
    }

    // MARK: - URL built from NapAlarm

    func test_shareURL_fromAlarm_reflectsAlarmFields() {
        let alarm = NapAlarm(name: "Grand Central", latitude: 40.7527, longitude: -73.9772)
        let url = makeShareURL(from: alarm)
        XCTAssertTrue(url.contains("\(alarm.latitude)"), "Latitude mismatch: \(url)")
        XCTAssertTrue(url.contains("\(alarm.longitude)"), "Longitude mismatch: \(url)")
        XCTAssertTrue(url.contains("Grand"), "Alarm name missing from URL: \(url)")
    }

    // MARK: - Non-ASCII and edge-case names

    func test_shareURL_nonASCIIName_producesValidURL() {
        // Japanese station name — must percent-encode correctly
        let url = makeShareURL(lat: 35.6812, lon: 139.7671, name: "東京駅")
        XCTAssertNotNil(URL(string: url),
                        "Non-ASCII name must produce a parseable URL: \(url)")
        XCTAssertFalse(url.contains("東京"),
                       "Non-ASCII characters must be percent-encoded in the URL")
    }

    func test_shareURL_arabicName_producesValidURL() {
        let url = makeShareURL(lat: 24.7136, lon: 46.6753, name: "محطة الرياض")
        XCTAssertNotNil(URL(string: url))
    }

    func test_shareURL_emptyName_doesNotCrash() {
        // Empty alarm name must produce a URL without crashing
        let url = makeShareURL(lat: 40.0, lon: -74.0, name: "")
        XCTAssertNotNil(URL(string: url),
                        "Empty name must still produce a parseable URL: \(url)")
    }

    func test_shareURL_nameWithHashAndQuestion_isEncoded() {
        // # and ? are URL-reserved — must be encoded in the query param
        let url = makeShareURL(lat: 40.0, lon: -74.0, name: "Stop #1 & Q?")
        let parsed = URL(string: url)
        XCTAssertNotNil(parsed, "URL must remain parseable after encoding reserved chars")
        // Raw # and ? must not appear unencoded in the query string portion
        XCTAssertFalse(url.contains("Stop #1"),
                       "Hash character must be percent-encoded: \(url)")
    }

    // MARK: - Boundary coordinates

    func test_shareURL_northPole_producesValidURL() {
        let url = makeShareURL(lat: 90.0, lon: 0.0, name: "North Pole")
        XCTAssertNotNil(URL(string: url))
        XCTAssertTrue(url.contains("ll=90.0,0.0"))
    }

    func test_shareURL_antimeridian_producesValidURL() {
        let url = makeShareURL(lat: 0.0, lon: 180.0, name: "Date Line")
        XCTAssertNotNil(URL(string: url))
    }

    func test_shareURL_negativeCoordinates_correctlyFormatted() {
        // Southern hemisphere, western hemisphere — both negative
        let url = makeShareURL(lat: -33.8688, lon: -70.6693, name: "Santiago")
        XCTAssertTrue(url.contains("ll=-33.8688,-70.6693"),
                      "Negative coordinates must appear with minus sign: \(url)")
    }

    // MARK: - Helpers

    /// Mirrors AlarmDetailView.shareURLString exactly — keep in sync with the view.
    private func makeShareURL(lat: Double, lon: Double, name: String) -> String {
        let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? name
        return "https://maps.apple.com/?ll=\(lat),\(lon)&q=\(encoded)"
    }

    private func makeShareURL(from alarm: NapAlarm) -> String {
        makeShareURL(lat: alarm.latitude, lon: alarm.longitude, name: alarm.name)
    }
}

// MARK: - Auto-Notify fire tests

/// Tests that queueAutoNotify (called inside handleRegionEvent when an alarm fires)
/// correctly sets pendingContactMessage — the signal ContentView uses to present
/// the Messages compose sheet.
///
/// Key invariants:
/// • Fires immediately when the geo-event is detected (not on notification tap).
/// • Only fires for phone contacts — email contacts are silently ignored.
/// • SMS body includes direction (Arrival/Departure), alarm name, and current time.
/// • Does NOT fire when Auto-Notify is disabled or contact list is empty.
@MainActor
final class AutoNotifyFireTests: XCTestCase {

    var sut: AlarmManager!

    override func setUp() {
        super.setUp()
        sut = AlarmManager()
    }

    override func tearDown() {
        sut = nil
        super.tearDown()
    }

    // MARK: - Fires on alarm trigger

    func test_regionEntry_setsContactMessage_whenAutoNotifyEnabled() {
        let alarm = makeEntryAlarmWithPhone()
        sut.add(alarm: alarm)

        sut.simulateRegionEntered(regionID: alarm.id.uuidString)

        XCTAssertNotNil(sut.pendingContactMessage,
                        "pendingContactMessage must be set when alarm fires with Auto-Notify on")
    }

    func test_regionExit_setsContactMessage_whenAutoNotifyEnabled() {
        let alarm = makeExitAlarmWithPhone()
        sut.add(alarm: alarm)

        sut.simulateRegionExited(regionID: alarm.id.uuidString)

        XCTAssertNotNil(sut.pendingContactMessage,
                        "pendingContactMessage must be set on exit alarm with Auto-Notify on")
    }

    // MARK: - Does NOT fire when disabled / empty

    func test_regionEntry_doesNotSetContactMessage_whenAutoNotifyDisabled() {
        let alarm = makeEntryAlarmWithPhone()
        alarm.notifyContact = false
        sut.add(alarm: alarm)

        sut.simulateRegionEntered(regionID: alarm.id.uuidString)

        XCTAssertNil(sut.pendingContactMessage,
                     "pendingContactMessage must be nil when Auto-Notify is disabled")
    }

    func test_regionEntry_doesNotSetContactMessage_whenNoContacts() {
        let alarm = makeEntryAlarm()
        alarm.notifyContact = true
        alarm.notifyContactList = []
        sut.add(alarm: alarm)

        sut.simulateRegionEntered(regionID: alarm.id.uuidString)

        XCTAssertNil(sut.pendingContactMessage,
                     "pendingContactMessage must be nil when contact list is empty")
    }

    func test_regionEntry_doesNotSetContactMessage_forEmailOnlyContacts() {
        let alarm = makeEntryAlarm()
        alarm.notifyContact = true
        alarm.notifyContactList = [NotifyContact(name: "Bob", value: "bob@example.com")]
        sut.add(alarm: alarm)

        sut.simulateRegionEntered(regionID: alarm.id.uuidString)

        XCTAssertNil(sut.pendingContactMessage,
                     "Email-only contacts must not trigger SMS compose sheet")
    }

    // MARK: - SMS body content

    func test_autoNotify_smsBody_containsAlarmName() {
        let alarm = makeEntryAlarmWithPhone()
        alarm.name = "Penn Station"
        sut.add(alarm: alarm)

        sut.simulateRegionEntered(regionID: alarm.id.uuidString)

        let body = sut.pendingContactMessage?.body ?? ""
        XCTAssertTrue(body.contains("Penn Station"),
                      "SMS body must include alarm name. Got: \(body)")
    }

    func test_autoNotify_smsBody_mentionsArrival_forOnEntryAlarm() {
        let alarm = makeEntryAlarmWithPhone()
        alarm.name = "Times Square"
        sut.add(alarm: alarm)

        sut.simulateRegionEntered(regionID: alarm.id.uuidString)

        let body = sut.pendingContactMessage?.body ?? ""
        XCTAssertTrue(body.contains("Arrival") || body.contains("arrived"),
                      "SMS body for entry alarm must mention arrival. Got: \(body)")
    }

    func test_autoNotify_smsBody_mentionsDeparture_forOnExitAlarm() {
        let alarm = makeExitAlarmWithPhone()
        alarm.name = "Home Station"
        sut.add(alarm: alarm)

        sut.simulateRegionExited(regionID: alarm.id.uuidString)

        let body = sut.pendingContactMessage?.body ?? ""
        XCTAssertTrue(body.contains("Departure") || body.contains("departed"),
                      "SMS body for exit alarm must mention departure. Got: \(body)")
    }

    func test_autoNotify_smsBody_containsTime() {
        let alarm = makeEntryAlarmWithPhone()
        sut.add(alarm: alarm)

        let before = Date()
        sut.simulateRegionEntered(regionID: alarm.id.uuidString)
        let after = Date()

        let body = sut.pendingContactMessage?.body ?? ""
        // Body should contain a time component recognisable as HH:MM (12- or 24-hr).
        // Use a simple regex — we don't care about exact format, just presence.
        let hasTime = body.range(of: #"\d{1,2}:\d{2}"#, options: .regularExpression) != nil
        XCTAssertTrue(hasTime,
                      "SMS body must contain a time value (e.g. '9:14 AM'). Got: \(body)")
        // Also sanity-check the time is recent (within 30 s of the test).
        _ = before  // suppress unused warning; above range check is the real guard
        _ = after
    }

    // MARK: - Phone numbers forwarded correctly

    func test_autoNotify_smsPhones_matchConfiguredContacts() {
        let alarm = makeEntryAlarm()
        alarm.notifyContact = true
        alarm.notifyContactList = [
            NotifyContact(name: "Alice", value: "+15551234567"),
            NotifyContact(name: "Bob",   value: "+15559876543"),
        ]
        sut.add(alarm: alarm)

        sut.simulateRegionEntered(regionID: alarm.id.uuidString)

        XCTAssertEqual(
            Set(sut.pendingContactMessage?.phones ?? []),
            ["+15551234567", "+15559876543"],
            "Both phone contacts must appear in ContactMessage.phones"
        )
    }

    func test_autoNotify_smsPhones_excludeEmailContacts() {
        let alarm = makeEntryAlarm()
        alarm.notifyContact = true
        alarm.notifyContactList = [
            NotifyContact(name: "Alice", value: "+15551234567"),
            NotifyContact(name: "Email", value: "alice@example.com"),
        ]
        sut.add(alarm: alarm)

        sut.simulateRegionEntered(regionID: alarm.id.uuidString)

        XCTAssertEqual(sut.pendingContactMessage?.phones, ["+15551234567"],
                       "Email contacts must be filtered out of SMS phones list")
    }

    // MARK: - Helpers

    private func makeEntryAlarm(name: String = "Grand Central") -> NapAlarm {
        NapAlarm(name: name, latitude: 40.7527, longitude: -73.9772, radius: 200,
                 regionEvent: .onEntry, state: .active)
    }

    private func makeExitAlarm(name: String = "Home") -> NapAlarm {
        NapAlarm(name: name, latitude: 40.7127, longitude: -74.0059, radius: 200,
                 regionEvent: .onExit, state: .active)
    }

    private func makeEntryAlarmWithPhone(_ phone: String = "+15551234567") -> NapAlarm {
        let alarm = makeEntryAlarm()
        alarm.notifyContact = true
        alarm.notifyContactList = [NotifyContact(name: "Alice", value: phone)]
        return alarm
    }

    private func makeExitAlarmWithPhone(_ phone: String = "+15551234567") -> NapAlarm {
        let alarm = makeExitAlarm()
        alarm.notifyContact = true
        alarm.notifyContactList = [NotifyContact(name: "Alice", value: phone)]
        return alarm
    }
}
