// Copyright © 2026 Robert Bartis. All rights reserved.

// WatchAlarmPayloadCodableTests.swift
// Added 2026-08-09 as part of a full test-coverage pass. Tests the iOS
// app-target copy of WatchAlarmPayload — the file's own header documents
// that there are two other DELIBERATE duplicate copies (Watch target,
// Widget/complication target) that must be changed in lockstep, since the
// struct crosses a real process boundary via WCSession/Codable and the
// three copies aren't compiler-linked in any way. This test target can only
// compile against the iOS copy, so it can't catch the three copies drifting
// apart directly — but it does pin down this copy's exact wire format
// (property names, JSON key names) so a silent rename here shows up as a
// failing test rather than a mysterious "Watch app stopped showing alarms"
// bug report after the three copies quietly go out of sync.

import XCTest
@testable import GeoNap

final class WatchAlarmPayloadCodableTests: XCTestCase {

    // MARK: - Round trip

    func test_encodeDecode_roundTripsAllFields() throws {
        let original = WatchAlarmPayload(
            id: UUID().uuidString,
            name: "Penn Station",
            regionEvent: "onEntry",
            radius: 150.0,
            state: "active",
            triggerCount: 3
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(WatchAlarmPayload.self, from: data)

        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.name, original.name)
        XCTAssertEqual(decoded.regionEvent, original.regionEvent)
        XCTAssertEqual(decoded.radius, original.radius)
        XCTAssertEqual(decoded.state, original.state)
        XCTAssertEqual(decoded.triggerCount, original.triggerCount)
    }

    // MARK: - Fixed wire-format shape

    /// Decodes a hand-written JSON literal using the exact key names the
    /// Watch and Widget copies of this struct also expect. If a future edit
    /// renames a property on the iOS copy without updating this test (and
    /// the other two copies), this fails loudly here instead of silently at
    /// runtime on a real Watch.
    func test_decode_fixedWireFormat_matchesExpectedKeys() throws {
        let json = """
        {
            "id": "11111111-2222-3333-4444-555555555555",
            "name": "Penn Station",
            "regionEvent": "onEntry",
            "radius": 150.5,
            "state": "active",
            "triggerCount": 2
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(WatchAlarmPayload.self, from: json)

        XCTAssertEqual(decoded.id, "11111111-2222-3333-4444-555555555555")
        XCTAssertEqual(decoded.name, "Penn Station")
        XCTAssertEqual(decoded.regionEvent, "onEntry")
        XCTAssertEqual(decoded.radius, 150.5)
        XCTAssertEqual(decoded.state, "active")
        XCTAssertEqual(decoded.triggerCount, 2)
    }

    // MARK: - Identifiable

    func test_id_matchesUnderlyingUUIDString() {
        let uuidString = UUID().uuidString
        let payload = WatchAlarmPayload(
            id: uuidString, name: "Test", regionEvent: "onExit",
            radius: 50, state: "inactive", triggerCount: 0
        )
        XCTAssertEqual(payload.id, uuidString, "Identifiable's `id` must be the same string passed in — the Watch/Widget list views key off this directly.")
    }
}
