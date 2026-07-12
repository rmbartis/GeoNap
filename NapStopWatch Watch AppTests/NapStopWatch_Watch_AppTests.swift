// Copyright © 2026 Robert Bartis. All rights reserved.

// NapStopWatch_Watch_AppTests.swift
// Unit tests for the watchOS app target. Previously this target only had
// Xcode's generated placeholder test (an empty `example()`), so the "watch
// unit tests" CI job (see .github/workflows/gtfs-tests.yml) had nothing
// real to run. Added 2026-07-11 alongside CI coverage for Apple Watch
// support.
//
// Covers WatchAlarmPayload's Codable round-trip — the wire format sent from
// the iOS app (WatchConnectivityManager.updateWatch(with:)) over WCSession
// applicationContext and decoded here by WatchAlarmStore. This struct is
// DELIBERATELY duplicated across three targets (iOS, this Watch app, and
// the widget/complication extension — see this file's sibling
// WatchAlarmPayload.swift for why); a field mismatch or Codable regression
// in any copy would silently break the Watch sync path with no compiler
// error, since nothing here shares a module with the iOS side. This test
// only guards THIS target's copy, but gives the sync payload real,
// automated coverage for the first time.

import Testing
import Foundation
@testable import NapStopWatch_Watch_App

struct WatchAlarmPayloadTests {

    @Test func encodeDecode_roundTrip_preservesAllFields() throws {
        let original = WatchAlarmPayload(
            id: "ABC-123", name: "Penn Station", regionEvent: "onEntry",
            radius: 200, state: "active", triggerCount: 3
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(WatchAlarmPayload.self, from: data)

        #expect(decoded.id == original.id)
        #expect(decoded.name == original.name)
        #expect(decoded.regionEvent == original.regionEvent)
        #expect(decoded.radius == original.radius)
        #expect(decoded.state == original.state)
        #expect(decoded.triggerCount == original.triggerCount)
    }

    @Test func decode_arrayOfPayloads_matchesApplicationContextShape() throws {
        // Mirrors exactly what WatchConnectivityManager.updateWatch(with:)
        // encodes into applicationContext[alarmsKey] on the iOS side —
        // an array, sorted triggered-first, that WatchAlarmStore decodes
        // in session(_:didReceiveApplicationContext:).
        let payloads = [
            WatchAlarmPayload(id: "1", name: "A", regionEvent: "onEntry", radius: 200, state: "triggered", triggerCount: 1),
            WatchAlarmPayload(id: "2", name: "B", regionEvent: "onExit", radius: 500, state: "active", triggerCount: 0),
        ]
        let data = try JSONEncoder().encode(payloads)
        let decoded = try JSONDecoder().decode([WatchAlarmPayload].self, from: data)

        #expect(decoded.count == 2)
        #expect(decoded.first?.id == "1")
        #expect(decoded.first?.state == "triggered")
        #expect(decoded.last?.id == "2")
    }

    @Test func decode_missingField_throws() {
        // If the iOS-side struct ever gains/loses a field without this copy
        // being updated to match, decoding should fail loudly in CI rather
        // than silently dropping alarms on-device.
        let incomplete = Data(#"{"id":"1","name":"A"}"#.utf8)
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(WatchAlarmPayload.self, from: incomplete)
        }
    }
}
