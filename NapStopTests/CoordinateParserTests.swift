// Copyright © 2026 Robert Bartis. All rights reserved.

// CoordinateParserTests.swift
// CoordinateParser.swift (DD / DMS / DDM parsing + formatting, hemisphere
// handling, range validation) is pure Foundation/CoreLocation logic with no
// framework dependencies — a textbook fit for the project's "pure logic
// only" CI testability convention — but had zero test coverage before this
// file. Found during the 2026-07-05 CI coverage audit (Bob).

import XCTest
import CoreLocation
@testable import GeoNap

final class CoordinateParserTests: XCTestCase {

    // MARK: - DD (Decimal Degrees)

    func test_parseDD_plainValues() throws {
        let coord = try CoordinateParser.parse(latString: "40.7128", lonString: "-74.0060", format: .dd)
        XCTAssertEqual(coord.latitude,  40.7128, accuracy: 0.00001)
        XCTAssertEqual(coord.longitude, -74.0060, accuracy: 0.00001)
    }

    func test_parseDD_hemisphereSuffix() throws {
        let coord = try CoordinateParser.parse(latString: "40.7128N", lonString: "74.0060W", format: .dd)
        XCTAssertEqual(coord.latitude,  40.7128, accuracy: 0.00001)
        XCTAssertEqual(coord.longitude, -74.0060, accuracy: 0.00001)
    }

    func test_parseDD_hemispherePrefix() throws {
        let coord = try CoordinateParser.parse(latString: "N40.7128", lonString: "W74.0060", format: .dd)
        XCTAssertEqual(coord.latitude,  40.7128, accuracy: 0.00001)
        XCTAssertEqual(coord.longitude, -74.0060, accuracy: 0.00001)
    }

    func test_parseDD_southernAndEasternHemispheres_areNegativeOrPositive() throws {
        let coord = try CoordinateParser.parse(latString: "33.8688S", lonString: "151.2093E", format: .dd)
        XCTAssertEqual(coord.latitude,  -33.8688, accuracy: 0.00001)
        XCTAssertEqual(coord.longitude,  151.2093, accuracy: 0.00001)
    }

    func test_parseDD_degreeSymbol_isStripped() throws {
        let coord = try CoordinateParser.parse(latString: "40.7128°", lonString: "-74.0060°", format: .dd)
        XCTAssertEqual(coord.latitude,  40.7128, accuracy: 0.00001)
        XCTAssertEqual(coord.longitude, -74.0060, accuracy: 0.00001)
    }

    func test_parseDD_emptyString_throwsEmpty() {
        XCTAssertThrowsError(try CoordinateParser.parse(latString: "", lonString: "-74.0060", format: .dd)) { error in
            guard case CoordinateParseError.empty = error else {
                return XCTFail("Expected .empty, got \(error)")
            }
        }
    }

    func test_parseDD_nonNumeric_throwsInvalidFormat() {
        // "xyz" deliberately avoids starting/ending with a hemisphere letter
        // (N/S/E/W) so this exercises the "just not a number" path, not the
        // hemisphere-prefix path (which "not-a-number" would — its leading
        // "n" is parsed as a hemisphere prefix first, still landing on
        // .invalidFormat, but for a different reason than intended here).
        XCTAssertThrowsError(try CoordinateParser.parse(latString: "xyz", lonString: "-74.0060", format: .dd)) { error in
            guard case CoordinateParseError.invalidFormat = error else {
                return XCTFail("Expected .invalidFormat, got \(error)")
            }
        }
    }

    func test_parseDD_latitudeOutOfRange_throws() {
        XCTAssertThrowsError(try CoordinateParser.parse(latString: "91", lonString: "0", format: .dd)) { error in
            guard case CoordinateParseError.latitudeOutOfRange = error else {
                return XCTFail("Expected .latitudeOutOfRange, got \(error)")
            }
        }
    }

    func test_parseDD_longitudeOutOfRange_throws() {
        XCTAssertThrowsError(try CoordinateParser.parse(latString: "0", lonString: "181", format: .dd)) { error in
            guard case CoordinateParseError.longitudeOutOfRange = error else {
                return XCTFail("Expected .longitudeOutOfRange, got \(error)")
            }
        }
    }

    func test_parseDD_latitudeBoundary_90IsValid() throws {
        let coord = try CoordinateParser.parse(latString: "90", lonString: "0", format: .dd)
        XCTAssertEqual(coord.latitude, 90, accuracy: 0.00001)
    }

    func test_parseDD_longitudeBoundary_180IsValid() throws {
        let coord = try CoordinateParser.parse(latString: "0", lonString: "180", format: .dd)
        XCTAssertEqual(coord.longitude, 180, accuracy: 0.00001)
    }

    func test_parseDD_wrongHemisphereForLatitude_throws() {
        // "E"/"W" are longitude hemisphere letters — invalid on a latitude field.
        XCTAssertThrowsError(try CoordinateParser.parse(latString: "40.7128E", lonString: "-74.0060", format: .dd)) { error in
            guard case CoordinateParseError.wrongHemisphere = error else {
                return XCTFail("Expected .wrongHemisphere, got \(error)")
            }
        }
    }

    func test_parseDD_wrongHemisphereForLongitude_throws() {
        // "N"/"S" are latitude hemisphere letters — invalid on a longitude field.
        XCTAssertThrowsError(try CoordinateParser.parse(latString: "40.7128", lonString: "74.0060N", format: .dd)) { error in
            guard case CoordinateParseError.wrongHemisphere = error else {
                return XCTFail("Expected .wrongHemisphere, got \(error)")
            }
        }
    }

    // MARK: - DMS (Degrees Minutes Seconds)

    func test_parseDMS_plainValues() throws {
        let coord = try CoordinateParser.parse(latString: "40°42′46″N", lonString: "74°00′21″W", format: .dms)
        XCTAssertEqual(coord.latitude,  40.712778, accuracy: 0.0001)
        XCTAssertEqual(coord.longitude, -74.005833, accuracy: 0.0001)
    }

    func test_parseDMS_spaceSeparated_alsoWorks() throws {
        let coord = try CoordinateParser.parse(latString: "40 42 46 N", lonString: "74 00 21 W", format: .dms)
        XCTAssertEqual(coord.latitude,  40.712778, accuracy: 0.0001)
        XCTAssertEqual(coord.longitude, -74.005833, accuracy: 0.0001)
    }

    func test_parseDMS_minutesOutOfRange_throws() {
        XCTAssertThrowsError(try CoordinateParser.parse(latString: "40°60′00″N", lonString: "74°00′00″W", format: .dms)) { error in
            guard case CoordinateParseError.minutesOutOfRange = error else {
                return XCTFail("Expected .minutesOutOfRange, got \(error)")
            }
        }
    }

    func test_parseDMS_secondsOutOfRange_throws() {
        XCTAssertThrowsError(try CoordinateParser.parse(latString: "40°42′60″N", lonString: "74°00′00″W", format: .dms)) { error in
            guard case CoordinateParseError.secondsOutOfRange = error else {
                return XCTFail("Expected .secondsOutOfRange, got \(error)")
            }
        }
    }

    func test_parseDMS_missingTokens_throwsInvalidFormat() {
        // Only one token supplied where at least degrees+minutes are required.
        XCTAssertThrowsError(try CoordinateParser.parse(latString: "40", lonString: "74°00′00″W", format: .dms)) { error in
            guard case CoordinateParseError.invalidFormat = error else {
                return XCTFail("Expected .invalidFormat, got \(error)")
            }
        }
    }

    // MARK: - DDM (Degrees Decimal Minutes)

    func test_parseDDM_plainValues() throws {
        let coord = try CoordinateParser.parse(latString: "40°42.767′N", lonString: "74°00.360′W", format: .ddm)
        XCTAssertEqual(coord.latitude,  40.712783, accuracy: 0.0001)
        XCTAssertEqual(coord.longitude, -74.006000, accuracy: 0.0001)
    }

    func test_parseDDM_minutesOutOfRange_throws() {
        XCTAssertThrowsError(try CoordinateParser.parse(latString: "40°60.00′N", lonString: "74°00.00′W", format: .ddm)) { error in
            guard case CoordinateParseError.minutesOutOfRange = error else {
                return XCTFail("Expected .minutesOutOfRange, got \(error)")
            }
        }
    }

    // MARK: - Cross-format consistency
    // The same real-world point expressed in all three formats must parse to
    // (approximately) the same coordinate.

    func test_allThreeFormats_parseTheSameRealWorldPoint_consistently() throws {
        let dd  = try CoordinateParser.parse(latString: "40.7128",     lonString: "-74.0060",     format: .dd)
        let dms = try CoordinateParser.parse(latString: "40°42′46″N",  lonString: "74°00′21″W",    format: .dms)
        let ddm = try CoordinateParser.parse(latString: "40°42.767′N", lonString: "74°00.360′W",   format: .ddm)

        XCTAssertEqual(dd.latitude,  dms.latitude,  accuracy: 0.0005)
        XCTAssertEqual(dd.latitude,  ddm.latitude,  accuracy: 0.0005)
        XCTAssertEqual(dd.longitude, dms.longitude, accuracy: 0.0005)
        XCTAssertEqual(dd.longitude, ddm.longitude, accuracy: 0.0005)
    }

    // MARK: - Formatting

    func test_formatDD_sixDecimalPlaces() {
        XCTAssertEqual(CoordinateParser.format(latitude: 40.7128, format: .dd), "40.712800")
        XCTAssertEqual(CoordinateParser.format(longitude: -74.0060, format: .dd), "-74.006000")
    }

    func test_formatDMS_includesHemisphereLetter() {
        let lat = CoordinateParser.format(latitude: 40.712778, format: .dms)
        let lon = CoordinateParser.format(longitude: -74.005833, format: .dms)
        XCTAssertEqual(lat, "40°42′46.00″N")
        XCTAssertEqual(lon, "74°00′21.00″W")
    }

    func test_formatDDM_includesHemisphereLetter() {
        // Use the exact fraction (40 + 42.767/60) rather than a rounded
        // literal — formatting is precise to 5 decimal places on minutes, so
        // an imprecise literal input produces a mismatched last digit.
        let lat = CoordinateParser.format(latitude: 40 + 42.767 / 60, format: .ddm)
        let lon = CoordinateParser.format(longitude: -(74 + 0.360 / 60), format: .ddm)
        XCTAssertEqual(lat, "40°42.76700′N")
        XCTAssertEqual(lon, "74°00.36000′W")
    }

    func test_format_negativeLatitude_usesSouthHemisphere() {
        XCTAssertTrue(CoordinateParser.format(latitude: -33.8688, format: .dms).hasSuffix("S"))
    }

    func test_format_positiveLongitude_usesEastHemisphere() {
        XCTAssertTrue(CoordinateParser.format(longitude: 151.2093, format: .dms).hasSuffix("E"))
    }

    // MARK: - Round trip (format → parse → same coordinate)

    func test_roundTrip_dd() throws {
        let original = CLLocationCoordinate2D(latitude: 51.5074, longitude: -0.1278)
        let latStr = CoordinateParser.format(latitude: original.latitude, format: .dd)
        let lonStr = CoordinateParser.format(longitude: original.longitude, format: .dd)
        let reparsed = try CoordinateParser.parse(latString: latStr, lonString: lonStr, format: .dd)
        XCTAssertEqual(reparsed.latitude,  original.latitude,  accuracy: 0.00001)
        XCTAssertEqual(reparsed.longitude, original.longitude, accuracy: 0.00001)
    }

    func test_roundTrip_dms() throws {
        let original = CLLocationCoordinate2D(latitude: 51.5074, longitude: -0.1278)
        let latStr = CoordinateParser.format(latitude: original.latitude, format: .dms)
        let lonStr = CoordinateParser.format(longitude: original.longitude, format: .dms)
        let reparsed = try CoordinateParser.parse(latString: latStr, lonString: lonStr, format: .dms)
        // DMS rounds seconds to 2 decimal places, so allow a slightly looser tolerance.
        XCTAssertEqual(reparsed.latitude,  original.latitude,  accuracy: 0.0001)
        XCTAssertEqual(reparsed.longitude, original.longitude, accuracy: 0.0001)
    }
}
