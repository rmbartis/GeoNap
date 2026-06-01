// NotifyContactTests.swift
// Tests for NotifyContact JSON encoding/decoding, isEmail edge cases,
// and the array-level toJSON/fromJSON helpers.
// These code paths are used by Auto-Notify persistence — bugs here mean
// contacts disappear silently when an alarm is saved or reloaded.

import XCTest
@testable import GeoNap

@MainActor
final class NotifyContactTests: XCTestCase {

    // MARK: - isEmail

    func test_isEmail_true_forSimpleAddress() {
        XCTAssertTrue(NotifyContact(name: "A", value: "alice@example.com").isEmail)
    }

    func test_isEmail_true_forPlusAddressedEmail() {
        XCTAssertTrue(NotifyContact(name: "A", value: "alice+filter@example.com").isEmail)
    }

    func test_isEmail_true_forSubdomainEmail() {
        XCTAssertTrue(NotifyContact(name: "A", value: "bob@mail.example.co.uk").isEmail)
    }

    func test_isEmail_false_forPlainPhone() {
        XCTAssertFalse(NotifyContact(name: "B", value: "+15551234567").isEmail)
    }

    func test_isEmail_false_forLocalPhone() {
        XCTAssertFalse(NotifyContact(name: "B", value: "5551234567").isEmail)
    }

    func test_isEmail_false_forEmptyValue() {
        XCTAssertFalse(NotifyContact(name: "B", value: "").isEmail)
    }

    // MARK: - init trims whitespace

    func test_init_trimsLeadingTrailingWhitespace() {
        let c = NotifyContact(name: "A", value: "  +15551234567  ")
        XCTAssertEqual(c.value, "+15551234567",
                       "init must strip whitespace from value")
    }

    // MARK: - Equatable

    func test_equatable_sameIDSameFields_isEqual() {
        let id = UUID()
        let c1 = NotifyContact(id: id, name: "Alice", value: "+15551234567")
        let c2 = NotifyContact(id: id, name: "Alice", value: "+15551234567")
        XCTAssertEqual(c1, c2)
    }

    func test_equatable_differentID_isNotEqual() {
        let c1 = NotifyContact(name: "Alice", value: "+15551234567")
        let c2 = NotifyContact(name: "Alice", value: "+15551234567")
        // Default init generates a new UUID each time
        XCTAssertNotEqual(c1, c2)
    }

    // MARK: - Array toJSON / fromJSON round-trips

    func test_toJSON_fromJSON_singleContact() {
        let original = [NotifyContact(name: "Alice", value: "+15551234567")]
        let json     = original.toJSON()
        let decoded  = [NotifyContact].fromJSON(json)

        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded.first?.name,  "Alice")
        XCTAssertEqual(decoded.first?.value, "+15551234567")
    }

    func test_toJSON_fromJSON_multipleContacts() {
        let original = [
            NotifyContact(name: "Alice", value: "+15551234567"),
            NotifyContact(name: "Bob",   value: "bob@example.com"),
        ]
        let decoded = [NotifyContact].fromJSON(original.toJSON())

        XCTAssertEqual(decoded.count, 2)
        XCTAssertEqual(Set(decoded.map(\.name)), ["Alice", "Bob"])
    }

    func test_toJSON_fromJSON_emptyList() {
        let json    = [NotifyContact]().toJSON()
        let decoded = [NotifyContact].fromJSON(json)
        XCTAssertTrue(decoded.isEmpty)
    }

    func test_fromJSON_emptyString_returnsEmptyArray() {
        XCTAssertTrue([NotifyContact].fromJSON("").isEmpty)
    }

    func test_fromJSON_corruptJSON_returnsEmptyArray() {
        XCTAssertTrue([NotifyContact].fromJSON("not valid json {{").isEmpty,
                      "Corrupt JSON must return [] rather than crash")
    }

    func test_fromJSON_nullJSON_returnsEmptyArray() {
        XCTAssertTrue([NotifyContact].fromJSON("null").isEmpty)
    }

    func test_fromJSON_wrongTypeJSON_returnsEmptyArray() {
        // A JSON object instead of an array
        XCTAssertTrue([NotifyContact].fromJSON("{\"name\":\"X\"}").isEmpty)
    }

    // MARK: - ID survives round-trip

    func test_id_survivesJSONRoundTrip() {
        let id      = UUID()
        let contact = NotifyContact(id: id, name: "Carol", value: "+15550009999")
        let decoded = [NotifyContact].fromJSON([contact].toJSON())
        XCTAssertEqual(decoded.first?.id, id,
                       "UUID must survive JSON encode → decode without mutation")
    }

    // MARK: - NapAlarm.notifyContactList accessor

    func test_napAlarm_notifyContactList_roundTrip() {
        let alarm = NapAlarm(name: "T", latitude: 40.0, longitude: -74.0)
        let contacts = [
            NotifyContact(name: "Alice", value: "+15551234567"),
            NotifyContact(name: "Bob",   value: "+15559876543"),
        ]
        alarm.notifyContactList = contacts

        let retrieved = alarm.notifyContactList
        XCTAssertEqual(retrieved.count, 2)
        XCTAssertEqual(Set(retrieved.map(\.name)), ["Alice", "Bob"])
    }

    func test_napAlarm_notifyContactList_emptyByDefault() {
        let alarm = NapAlarm(name: "T", latitude: 40.0, longitude: -74.0)
        XCTAssertTrue(alarm.notifyContactList.isEmpty)
    }

    func test_napAlarm_notifyContactList_persistsViaJSON() {
        let alarm   = NapAlarm(name: "T", latitude: 40.0, longitude: -74.0)
        let contact = NotifyContact(id: UUID(), name: "Dave", value: "+15550001111")
        alarm.notifyContactList = [contact]

        // Simulate storage round-trip by re-reading from JSON
        let json     = alarm.notifyContactsJSON
        let decoded  = [NotifyContact].fromJSON(json)
        XCTAssertEqual(decoded.first?.id,    contact.id)
        XCTAssertEqual(decoded.first?.name,  "Dave")
        XCTAssertEqual(decoded.first?.value, "+15550001111")
    }
}
