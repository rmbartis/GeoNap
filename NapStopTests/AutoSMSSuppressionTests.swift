// Copyright © 2026 Robert Bartis. All rights reserved.

// AutoSMSSuppressionTests.swift
// Coverage for AlarmManager.queueAutoNotify's automation-suppression toggle —
// flagged as untested in the 2026-06-29 CI review
// (docs/ci-and-help-review-2026-06-29.md, recommendation #2).
//
// When the user has set up the hands-free Shortcuts automation (Settings →
// Auto-SMS → "I've set up the Shortcuts automation"), the in-app Messages
// compose sheet must be suppressed — otherwise the same message would be
// both auto-sent by Shortcuts AND shown to the user as a compose sheet. In
// both states, the message body must still be written to UserDefaults for
// NotifyContactsIntent (the Shortcuts action) to pick up.
//
// queueAutoNotify() reads/writes UserDefaults.standard directly (not an
// injectable suite), so these tests touch the real `standard` defaults for
// four specific keys and carefully reset them in setUp/tearDown to avoid
// bleeding state into other test files (confirmed no other test file reads
// or writes these four keys).
//
// pendingPhones added (Bob, 2026-07-09) alongside pendingBody/pendingBodyTimestamp
// — it's the recipient list NotifyContactsIntent now returns as a named
// "Recipients" output, sourced from the alarm's own Auto-Notify contacts so the
// Shortcuts automation never needs a manually configured, static contact list.
// This key was previously untested — queueAutoNotify wrote it but nothing here
// asserted on it, so a regression there would have shipped silently.

import XCTest
@testable import GeoNap

@MainActor
final class AutoSMSSuppressionTests: XCTestCase {

    var sut: AlarmManager!

    override func setUp() {
        super.setUp()
        resetDefaults()
        sut = AlarmManager()
    }

    override func tearDown() {
        resetDefaults()
        sut = nil
        super.tearDown()
    }

    private func resetDefaults() {
        UserDefaults.standard.removeObject(forKey: AppStorageKey.autoSMSAutomationEnabled)
        UserDefaults.standard.removeObject(forKey: AutoNotifyDefaultsKey.pendingBody)
        UserDefaults.standard.removeObject(forKey: AutoNotifyDefaultsKey.pendingPhones)
        UserDefaults.standard.removeObject(forKey: AutoNotifyDefaultsKey.pendingBodyTimestamp)
    }

    private func makeAlarmWithPhone(_ phone: String = "+15551234567") -> NapAlarm {
        let alarm = NapAlarm(name: "Penn Station", latitude: 40.7506, longitude: -73.9971,
                              regionEvent: .onEntry)
        alarm.notifyContact = true
        alarm.notifyContactList = [NotifyContact(name: "Alice", value: phone)]
        return alarm
    }

    // MARK: - Automation OFF (default) — in-app compose sheet queued

    func test_automationDisabled_queuesComposeSheet() {
        UserDefaults.standard.set(false, forKey: AppStorageKey.autoSMSAutomationEnabled)
        let alarm = makeAlarmWithPhone()
        sut.add(alarm: alarm)

        sut.simulateRegionEntered(regionID: alarm.id.uuidString)

        XCTAssertNotNil(sut.pendingContactMessage,
            "With the automation switch off, the in-app compose sheet must be queued")
        XCTAssertEqual(sut.pendingContactMessage?.phones, ["+15551234567"])
    }

    func test_automationDisabled_alsoWritesPendingBody() {
        // pendingBody/timestamp are written unconditionally, regardless of the
        // toggle — NotifyContactsIntent's own freshness guard is what governs
        // whether a Shortcuts run outside the automation actually sends.
        UserDefaults.standard.set(false, forKey: AppStorageKey.autoSMSAutomationEnabled)
        let alarm = makeAlarmWithPhone()
        sut.add(alarm: alarm)

        sut.simulateRegionEntered(regionID: alarm.id.uuidString)

        XCTAssertNotNil(UserDefaults.standard.string(forKey: AutoNotifyDefaultsKey.pendingBody),
            "pendingBody must be written even when automation is off")
    }

    // MARK: - Automation ON — in-app compose sheet suppressed

    func test_automationEnabled_suppressesComposeSheet() {
        UserDefaults.standard.set(true, forKey: AppStorageKey.autoSMSAutomationEnabled)
        let alarm = makeAlarmWithPhone()
        sut.add(alarm: alarm)

        sut.simulateRegionEntered(regionID: alarm.id.uuidString)

        XCTAssertNil(sut.pendingContactMessage,
            "With the automation switch on, the in-app compose sheet must be suppressed — Shortcuts sends the SMS instead")
    }

    func test_automationEnabled_stillWritesPendingBodyForShortcuts() {
        UserDefaults.standard.set(true, forKey: AppStorageKey.autoSMSAutomationEnabled)
        let alarm = makeAlarmWithPhone()
        sut.add(alarm: alarm)

        sut.simulateRegionEntered(regionID: alarm.id.uuidString)

        let body = UserDefaults.standard.string(forKey: AutoNotifyDefaultsKey.pendingBody)
        XCTAssertNotNil(body,
            "Even when the sheet is suppressed, the body must still be written for NotifyContactsIntent to read")
        XCTAssertTrue(body?.contains("Penn Station") ?? false)
    }

    func test_automationEnabled_pendingBodyTimestamp_isRecent() {
        UserDefaults.standard.set(true, forKey: AppStorageKey.autoSMSAutomationEnabled)
        let alarm = makeAlarmWithPhone()
        let before = Date().timeIntervalSince1970

        sut.add(alarm: alarm)
        sut.simulateRegionEntered(regionID: alarm.id.uuidString)

        let after = Date().timeIntervalSince1970
        let ts = UserDefaults.standard.double(forKey: AutoNotifyDefaultsKey.pendingBodyTimestamp)
        XCTAssertGreaterThanOrEqual(ts, before)
        XCTAssertLessThanOrEqual(ts, after)
    }

    // MARK: - pendingPhones (Recipients output for NotifyContactsIntent)

    func test_automationEnabled_writesPendingPhones_matchingConfiguredContacts() {
        UserDefaults.standard.set(true, forKey: AppStorageKey.autoSMSAutomationEnabled)
        let alarm = NapAlarm(name: "Penn Station", latitude: 40.7506, longitude: -73.9971,
                              regionEvent: .onEntry)
        alarm.notifyContact = true
        alarm.notifyContactList = [
            NotifyContact(name: "Alice", value: "+15551234567"),
            NotifyContact(name: "Bob",   value: "+15559876543"),
        ]
        sut.add(alarm: alarm)

        sut.simulateRegionEntered(regionID: alarm.id.uuidString)

        let phones = UserDefaults.standard.stringArray(forKey: AutoNotifyDefaultsKey.pendingPhones) ?? []
        XCTAssertEqual(Set(phones), ["+15551234567", "+15559876543"],
            "pendingPhones must contain every phone contact for the fired alarm, for NotifyContactsIntent's Recipients output")
    }

    func test_automationDisabled_alsoWritesPendingPhones() {
        // Same as pendingBody: written unconditionally regardless of the
        // toggle, so a Shortcuts run outside the automation still has correct
        // data available (NotifyContactsIntent's freshness guard governs
        // whether it actually sends, not this write).
        UserDefaults.standard.set(false, forKey: AppStorageKey.autoSMSAutomationEnabled)
        let alarm = makeAlarmWithPhone()
        sut.add(alarm: alarm)

        sut.simulateRegionEntered(regionID: alarm.id.uuidString)

        let phones = UserDefaults.standard.stringArray(forKey: AutoNotifyDefaultsKey.pendingPhones) ?? []
        XCTAssertEqual(phones, ["+15551234567"],
            "pendingPhones must be written even when automation is off")
    }

    func test_pendingPhones_excludesEmailContacts() {
        UserDefaults.standard.set(true, forKey: AppStorageKey.autoSMSAutomationEnabled)
        let alarm = NapAlarm(name: "Penn Station", latitude: 40.7506, longitude: -73.9971,
                              regionEvent: .onEntry)
        alarm.notifyContact = true
        alarm.notifyContactList = [
            NotifyContact(name: "Alice", value: "+15551234567"),
            NotifyContact(name: "Email", value: "alice@example.com"),
        ]
        sut.add(alarm: alarm)

        sut.simulateRegionEntered(regionID: alarm.id.uuidString)

        let phones = UserDefaults.standard.stringArray(forKey: AutoNotifyDefaultsKey.pendingPhones) ?? []
        XCTAssertEqual(phones, ["+15551234567"],
            "Email-only contacts must not appear in the Shortcuts Recipients output — Send Message needs a phone number")
    }

    // MARK: - No contacts — neither path engages

    func test_noPhoneContacts_neitherQueuesSheetNorWritesBody() {
        UserDefaults.standard.set(false, forKey: AppStorageKey.autoSMSAutomationEnabled)
        let alarm = NapAlarm(name: "No Contacts", latitude: 40.7506, longitude: -73.9971,
                              regionEvent: .onEntry)   // notifyContact defaults to false
        sut.add(alarm: alarm)

        sut.simulateRegionEntered(regionID: alarm.id.uuidString)

        XCTAssertNil(sut.pendingContactMessage,
            "No contacts configured — the compose sheet must never be queued")
        XCTAssertNil(UserDefaults.standard.string(forKey: AutoNotifyDefaultsKey.pendingBody),
            "queueAutoNotify must return before writing pendingBody when there are no phone contacts")
        XCTAssertNil(UserDefaults.standard.array(forKey: AutoNotifyDefaultsKey.pendingPhones),
            "queueAutoNotify must return before writing pendingPhones when there are no phone contacts")
    }

    func test_notifyContactFalse_withContactsListed_stillSkips() {
        // notifyContact toggle off should short-circuit even if a stale
        // contact list is still present on the model.
        UserDefaults.standard.set(false, forKey: AppStorageKey.autoSMSAutomationEnabled)
        let alarm = NapAlarm(name: "Toggle Off", latitude: 40.7506, longitude: -73.9971,
                              regionEvent: .onEntry)
        alarm.notifyContact = false
        alarm.notifyContactList = [NotifyContact(name: "Alice", value: "+15551234567")]
        sut.add(alarm: alarm)

        sut.simulateRegionEntered(regionID: alarm.id.uuidString)

        XCTAssertNil(sut.pendingContactMessage)
        XCTAssertNil(UserDefaults.standard.string(forKey: AutoNotifyDefaultsKey.pendingBody))
    }
}
