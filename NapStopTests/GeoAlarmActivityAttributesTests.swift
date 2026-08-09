// Copyright © 2026 Robert Bartis. All rights reserved.

// GeoAlarmActivityAttributesTests.swift
// Added 2026-08-09 as part of a full test-coverage pass. Tests the iOS
// app-target copy of GeoAlarmActivityAttributes (there are two other
// deliberate duplicate copies — see the file's own header — the widget
// extension's and none in the Watch target; this test target can only
// reach the app-target copy — see the file-level note below).
//
// HISTORY: this file originally documented a real bug — ContentState's
// doc comment on `distanceUnitRaw` claimed it "Defaults to imperial ... if
// somehow missing after decode," but the type relied entirely on Swift's
// compiler-synthesized Decodable, which does NOT consult a property's
// declared default for a key missing from the payload — it threw
// DecodingError.keyNotFound instead. Fixed the same day (2026-08-09) by
// giving ContentState a custom init(from:) — see
// GeoAlarm/Models/GeoAlarmActivityAttributes.swift (and the identical
// GeoAlarmLiveActivity/GeoAlarmActivityAttributes.swift copy, which MUST be
// changed identically or the app and widget extension processes will
// silently disagree on how to decode the same wire data — this test target
// cannot reach that copy at all, since it's a separate module; the fix was
// applied there by hand in lockstep and needs a build to confirm it
// actually compiles, same as this copy).
//
// The tests below were flipped from "proves the bug" to "proves the fix,"
// plus two new ones added specifically to pin the fix down precisely:
// providing an explicit distanceUnitRaw must NOT be silently overridden to
// "imperial" (a sloppy `?? "imperial"` fallback with the condition reversed
// would pass the original bug-repro test while breaking this), and a
// payload missing a genuinely REQUIRED field (lastUpdated) must still throw
// — confirms the fix didn't overcorrect into swallowing every decode error.

import XCTest
@testable import GeoNap

final class GeoAlarmActivityAttributesTests: XCTestCase {

    // MARK: - Round trip (current shape)

    func test_contentState_encodeDecode_roundTripsAllFields() throws {
        let original = GeoAlarmActivityAttributes.ContentState(
            distanceRemaining: 1250.5,
            etaSeconds: 340,
            lastUpdated: Date(timeIntervalSince1970: 1_754_000_000),
            distanceUnitRaw: "metric"
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(GeoAlarmActivityAttributes.ContentState.self, from: data)

        XCTAssertEqual(decoded, original, "A round trip through the current shape must be lossless.")
    }

    func test_contentState_encodeDecode_roundTripsNilOptionals() throws {
        // distanceRemaining/etaSeconds are both nil for a trigger-mode/GPS
        // state where neither has been computed yet — must round trip too,
        // not just the fully-populated case.
        let original = GeoAlarmActivityAttributes.ContentState(
            distanceRemaining: nil,
            etaSeconds: nil,
            lastUpdated: Date(timeIntervalSince1970: 1_754_000_000),
            distanceUnitRaw: "imperial"
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(GeoAlarmActivityAttributes.ContentState.self, from: data)

        XCTAssertEqual(decoded, original)
    }

    // MARK: - The fix: legacy payload missing distanceUnitRaw decodes and defaults

    func test_contentState_decodingLegacyJSONMissingDistanceUnitRaw_defaultsToImperial() throws {
        // Simulates a ContentState snapshot the OS persisted from before
        // distanceUnitRaw existed, replayed after an app update that added
        // the field — exactly the scenario the doc comment describes.
        let legacyJSON = """
        {
            "distanceRemaining": 800.0,
            "etaSeconds": 120.0,
            "lastUpdated": 1754000000.0
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(GeoAlarmActivityAttributes.ContentState.self, from: legacyJSON)

        XCTAssertEqual(decoded.distanceRemaining, 800.0)
        XCTAssertEqual(decoded.etaSeconds, 120.0)
        XCTAssertEqual(decoded.distanceUnitRaw, "imperial",
            "A payload missing distanceUnitRaw must decode successfully and default to \"imperial\" — this is the fix.")
    }

    // MARK: - The fix must not swallow an explicitly-provided value

    func test_contentState_decodingJSONWithExplicitDistanceUnitRaw_usesProvidedValue() throws {
        // Guards against an inverted-condition mistake in the fix (e.g.
        // `distanceUnitRaw = "imperial"` unconditionally, ignoring whatever
        // was actually decoded) — a payload that DOES specify "metric" must
        // decode as "metric", not silently get forced to the default.
        let json = """
        {
            "distanceRemaining": 800.0,
            "etaSeconds": 120.0,
            "lastUpdated": 1754000000.0,
            "distanceUnitRaw": "metric"
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(GeoAlarmActivityAttributes.ContentState.self, from: json)

        XCTAssertEqual(decoded.distanceUnitRaw, "metric",
            "An explicit distanceUnitRaw in the payload must be respected, not overridden to the default.")
    }

    // MARK: - The fix must not swallow a payload missing a genuinely required field

    func test_contentState_decodingJSONMissingRequiredLastUpdated_stillThrows() throws {
        // lastUpdated has no default and no reasonable fallback (unlike
        // distanceUnitRaw) — confirms the fix's custom init(from:) only
        // relaxed the one field it meant to, not decoding in general.
        let json = """
        {
            "distanceRemaining": 800.0,
            "etaSeconds": 120.0,
            "distanceUnitRaw": "imperial"
        }
        """.data(using: .utf8)!

        XCTAssertThrowsError(
            try JSONDecoder().decode(GeoAlarmActivityAttributes.ContentState.self, from: json)
        ) { error in
            guard case DecodingError.keyNotFound = error else {
                XCTFail("Expected DecodingError.keyNotFound for the missing lastUpdated key, got \(error)")
                return
            }
        }
    }
}
