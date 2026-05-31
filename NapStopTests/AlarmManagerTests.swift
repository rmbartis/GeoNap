// AlarmManagerTests.swift
// Unit tests for AlarmManager CRUD, persistence, and state transitions.
// Uses a mock UserDefaults suite so tests don't pollute real app storage.

import XCTest
@testable import GeoNap

@MainActor
final class AlarmManagerTests: XCTestCase {

    var sut: AlarmManager!

    override func setUp() {
        super.setUp()
        // Wipe the test suite before each run
        UserDefaults(suiteName: "test")?.removePersistentDomain(forName: "test")
        sut = AlarmManager()
    }

    override func tearDown() {
        UserDefaults(suiteName: "test")?.removePersistentDomain(forName: "test")
        sut = nil
        super.tearDown()
    }

    // MARK: - Add

    func test_add_appendsAlarm() {
        let alarm = NapAlarm.preview
        sut.add(alarm: alarm)
        XCTAssertEqual(sut.alarms.count, 1)
        XCTAssertEqual(sut.alarms.first?.id, alarm.id)
    }

    func test_add_multiple() {
        NapAlarm.samples.forEach { sut.add(alarm: $0) }
        XCTAssertEqual(sut.alarms.count, NapAlarm.samples.count)
    }

    // MARK: - Update

    func test_update_modifiesExistingAlarm() {
        let alarm = NapAlarm.preview
        sut.add(alarm: alarm)

        var modified = alarm
        modified = NapAlarm(
            id: alarm.id,
            name: "Updated Name",
            latitude: alarm.latitude,
            longitude: alarm.longitude,
            radius: 500
        )
        sut.update(alarm: modified)

        XCTAssertEqual(sut.alarms.first?.name,   "Updated Name")
        XCTAssertEqual(sut.alarms.first?.radius, 500)
        XCTAssertEqual(sut.alarms.count, 1)
    }

    func test_update_unknownID_doesNothing() {
        sut.add(alarm: NapAlarm.preview)
        let stranger = NapAlarm(name: "Stranger", latitude: 0, longitude: 0)
        sut.update(alarm: stranger)
        XCTAssertEqual(sut.alarms.count, 1)
    }

    // MARK: - Delete

    func test_delete_removesAlarm() {
        let alarm = NapAlarm.preview
        sut.add(alarm: alarm)
        sut.delete(alarm: alarm)
        XCTAssertTrue(sut.alarms.isEmpty)
    }

    func test_deleteAtOffsets() {
        NapAlarm.samples.forEach { sut.add(alarm: $0) }
        sut.delete(at: IndexSet([0]))
        XCTAssertEqual(sut.alarms.count, NapAlarm.samples.count - 1)
    }

    // MARK: - Toggle active

    func test_toggleActive_disablesActiveAlarm() {
        let alarm = NapAlarm.preview   // starts as .active
        sut.add(alarm: alarm)
        sut.toggleActive(alarm)
        XCTAssertEqual(sut.alarms.first?.state, .inactive)
    }

    func test_toggleActive_enablesInactiveAlarm() {
        var alarm = NapAlarm.preview
        alarm = NapAlarm(
            id: alarm.id,
            name: alarm.name,
            latitude: alarm.latitude,
            longitude: alarm.longitude,
            state: .inactive
        )
        sut.add(alarm: alarm)
        sut.toggleActive(alarm)
        XCTAssertEqual(sut.alarms.first?.state, .active)
    }

    // MARK: - State: triggered via region event

    func test_handleRegionEntry_triggersMatchingAlarm() {
        let alarm = NapAlarm.preview   // .onEntry
        sut.add(alarm: alarm)

        // Simulate the region event callback
        sut.simulateRegionEntered(regionID: alarm.id.uuidString)

        XCTAssertEqual(sut.alarms.first?.state, .triggered)
        XCTAssertNotNil(sut.alarms.first?.lastTriggeredAt)
    }

    func test_handleRegionEntry_doesNotTrigger_inactiveAlarm() {
        var alarm = NapAlarm.preview
        alarm = NapAlarm(
            id: alarm.id, name: alarm.name,
            latitude: alarm.latitude, longitude: alarm.longitude,
            state: .inactive
        )
        sut.add(alarm: alarm)
        sut.simulateRegionEntered(regionID: alarm.id.uuidString)
        XCTAssertEqual(sut.alarms.first?.state, .inactive)
    }

    func test_handleRegionExit_doesNotTrigger_onEntryAlarm() {
        let alarm = NapAlarm.preview   // .onEntry
        sut.add(alarm: alarm)
        sut.simulateRegionExited(regionID: alarm.id.uuidString)
        XCTAssertEqual(sut.alarms.first?.state, .active)  // unchanged
    }
}

// MARK: - Testability extension
// Exposes internal region-event handling so tests don't need a real CLLocationManager.
extension AlarmManager {
    func simulateRegionEntered(regionID: String) {
        handleRegionEvent(regionID: regionID, event: .onEntry)
    }
    func simulateRegionExited(regionID: String) {
        handleRegionEvent(regionID: regionID, event: .onExit)
    }
}

// MARK: - Auto-Notify tests

/// Tests for buildNotifyUserInfo and recoverAutoNotify.
///
/// Device testing revealed two bugs:
/// 1. SMS compose sheet never appeared after notification tap — pendingContactMessage
///    was lost when the app relaunched. Fix: embed phone data in content.userInfo.
/// 2. Email was sent to wrong address via SMTP. Fix: SMTP removed; email contacts
///    are embedded in userInfo and presented via MFMailComposeViewController.
@MainActor
final class AutoNotifyTests: XCTestCase {

    var sut: AlarmManager!

    override func setUp() {
        super.setUp()
        sut = AlarmManager()
    }

    override func tearDown() {
        sut = nil
        super.tearDown()
    }

    // MARK: NotifyContact.isEmail

    func test_isEmail_true_forEmailAddress() {
        XCTAssertTrue(NotifyContact(name: "A", value: "a@example.com").isEmail)
    }

    func test_isEmail_false_forPhoneNumber() {
        XCTAssertFalse(NotifyContact(name: "B", value: "+15551234567").isEmail)
    }

    // MARK: buildNotifyUserInfo — alarmID always present

    func test_buildNotifyUserInfo_alwaysContainsAlarmID() {
        let alarm = makeAlarm()
        let info = sut.buildNotifyUserInfo(for: alarm)
        XCTAssertEqual(info["alarmID"] as? String, alarm.id.uuidString)
    }

    // MARK: buildNotifyUserInfo — disabled / empty

    func test_buildNotifyUserInfo_noContactData_whenNotifyContactFalse() {
        var alarm = makeAlarm()
        alarm.notifyContact = false
        alarm.notifyContactList = [NotifyContact(name: "A", value: "+15550001111")]
        let info = sut.buildNotifyUserInfo(for: alarm)
        XCTAssertNil(info["notifyPhones"])
        XCTAssertNil(info["notifyEmails"])
        XCTAssertNil(info["notifyBody"])
    }

    func test_buildNotifyUserInfo_noContactData_whenListEmpty() {
        var alarm = makeAlarm()
        alarm.notifyContact = true
        alarm.notifyContactList = []
        let info = sut.buildNotifyUserInfo(for: alarm)
        XCTAssertNil(info["notifyPhones"])
        XCTAssertNil(info["notifyEmails"])
    }

    // MARK: buildNotifyUserInfo — phone contacts

    func test_buildNotifyUserInfo_embedsPhones() {
        let alarm = makeAlarmWithPhone("+15551234567")
        let info = sut.buildNotifyUserInfo(for: alarm)
        XCTAssertEqual(info["notifyPhones"] as? [String], ["+15551234567"])
        XCTAssertNotNil(info["notifyBody"])
        XCTAssertNil(info["notifySubject"], "Subject is email-only")
    }

    func test_buildNotifyUserInfo_body_containsAlarmName() {
        var alarm = makeAlarmWithPhone()
        alarm.name = "Penn Station"
        let body = sut.buildNotifyUserInfo(for: alarm)["notifyBody"] as? String ?? ""
        XCTAssertTrue(body.contains("Penn Station"))
    }

    func test_buildNotifyUserInfo_body_mentionsArrival_forOnEntry() {
        var alarm = makeAlarmWithPhone()
        alarm.regionEvent = .onEntry
        let body = sut.buildNotifyUserInfo(for: alarm)["notifyBody"] as? String ?? ""
        XCTAssertTrue(body.contains("Arrival") || body.contains("arrived"))
    }

    func test_buildNotifyUserInfo_body_mentionsDeparture_forOnExit() {
        var alarm = makeAlarmWithPhone()
        alarm.regionEvent = .onExit
        let body = sut.buildNotifyUserInfo(for: alarm)["notifyBody"] as? String ?? ""
        XCTAssertTrue(body.contains("Departure") || body.contains("departed"))
    }

    // MARK: buildNotifyUserInfo — email contacts

    func test_buildNotifyUserInfo_embedsEmails() {
        let alarm = makeAlarmWithEmail("alice@example.com")
        let info = sut.buildNotifyUserInfo(for: alarm)
        XCTAssertEqual(info["notifyEmails"] as? [String], ["alice@example.com"])
        XCTAssertNotNil(info["notifySubject"])
        XCTAssertNil(info["notifyPhones"], "Phones key absent for email-only contact")
    }

    func test_buildNotifyUserInfo_subject_containsGeoNap() {
        let info = sut.buildNotifyUserInfo(for: makeAlarmWithEmail())
        let subject = info["notifySubject"] as? String ?? ""
        XCTAssertTrue(subject.contains("GeoNap"))
    }

    // MARK: buildNotifyUserInfo — mixed contacts

    func test_buildNotifyUserInfo_embedsBoth_forMixedContacts() {
        var alarm = makeAlarm()
        alarm.notifyContact = true
        alarm.notifyContactList = [
            NotifyContact(name: "A", value: "+15550001111"),
            NotifyContact(name: "B", value: "b@example.com")
        ]
        let info = sut.buildNotifyUserInfo(for: alarm)
        XCTAssertNotNil(info["notifyPhones"])
        XCTAssertNotNil(info["notifyEmails"])
        XCTAssertNotNil(info["notifyBody"])
        XCTAssertNotNil(info["notifySubject"])
    }

    // MARK: recoverAutoNotify — phone recovery

    func test_recoverAutoNotify_setsPendingContactMessage() {
        sut.recoverAutoNotify(from: [
            "notifyPhones": ["+15551234567"],
            "notifyBody":   "Test body"
        ])
        XCTAssertNotNil(sut.pendingContactMessage)
        XCTAssertEqual(sut.pendingContactMessage?.phones, ["+15551234567"])
        XCTAssertEqual(sut.pendingContactMessage?.body,   "Test body")
    }

    func test_recoverAutoNotify_doesNotSetContactMessage_whenNoPhonesKey() {
        sut.recoverAutoNotify(from: ["alarmID": "some-uuid"])
        XCTAssertNil(sut.pendingContactMessage)
    }

    func test_recoverAutoNotify_doesNotSetContactMessage_forEmptyArray() {
        sut.recoverAutoNotify(from: ["notifyPhones": [String](), "notifyBody": "x"])
        XCTAssertNil(sut.pendingContactMessage)
    }

    // MARK: recoverAutoNotify — email recovery

    func test_recoverAutoNotify_setsPendingMailMessage() {
        sut.recoverAutoNotify(from: [
            "notifyEmails":  ["alice@example.com"],
            "notifySubject": "GeoNap Arrival",
            "notifyBody":    "I arrived."
        ])
        XCTAssertNotNil(sut.pendingMailMessage)
        XCTAssertEqual(sut.pendingMailMessage?.to,      ["alice@example.com"])
        XCTAssertEqual(sut.pendingMailMessage?.subject, "GeoNap Arrival")
        XCTAssertEqual(sut.pendingMailMessage?.body,    "I arrived.")
    }

    func test_recoverAutoNotify_usesDefaultSubject_whenMissing() {
        sut.recoverAutoNotify(from: [
            "notifyEmails": ["alice@example.com"],
            "notifyBody":   "Body"
        ])
        XCTAssertEqual(sut.pendingMailMessage?.subject, "GeoNap Alarm")
    }

    func test_recoverAutoNotify_doesNotSetMailMessage_whenNoEmailsKey() {
        sut.recoverAutoNotify(from: ["alarmID": "some-uuid"])
        XCTAssertNil(sut.pendingMailMessage)
    }

    func test_recoverAutoNotify_setsBoth_forMixedUserInfo() {
        sut.recoverAutoNotify(from: [
            "notifyPhones":  ["+15550001111"],
            "notifyEmails":  ["a@example.com"],
            "notifySubject": "GeoNap Arrival",
            "notifyBody":    "I arrived."
        ])
        XCTAssertNotNil(sut.pendingContactMessage)
        XCTAssertNotNil(sut.pendingMailMessage)
    }

    // MARK: Helpers

    private func makeAlarm(name: String = "Times Square") -> NapAlarm {
        NapAlarm(name: name, latitude: 40.7580, longitude: -73.9855, radius: 200)
    }

    private func makeAlarmWithPhone(_ phone: String = "+15551234567") -> NapAlarm {
        var alarm = makeAlarm()
        alarm.notifyContact = true
        alarm.notifyContactList = [NotifyContact(name: "Alice", value: phone)]
        return alarm
    }

    private func makeAlarmWithEmail(_ email: String = "alice@example.com") -> NapAlarm {
        var alarm = makeAlarm()
        alarm.notifyContact = true
        alarm.notifyContactList = [NotifyContact(name: "Alice", value: email)]
        return alarm
    }
}
