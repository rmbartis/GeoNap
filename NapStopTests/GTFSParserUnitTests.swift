// GTFSParserUnitTests.swift
// Pure offline unit tests for GTFSParser CSV parsing logic and CuratedFeeds integrity.
// No network access required — writes minimal CSV content to a temp directory.
//
// Covered:
//   • stops.txt  — (0,0) rejection, out-of-range lat/lon, non-numeric coords,
//                  valid stop accepted, quoted fields with commas
//   • routes.txt — unknown route_type → .unknown, missing file → []
//   • RFC 4180   — embedded double-quote escape ("") inside quoted field
//   • UTF-8 BOM  — header with BOM must still parse correctly
//   • CuratedFeeds — no duplicate names, all fields non-empty, all URLs start with http

import XCTest
@testable import GeoNap

// MARK: - GTFSParser offline unit tests ───────────────────────────────────────

final class GTFSParserUnitTests: XCTestCase {

    // Temp directory recreated for each test.
    private var tmpDir: URL!

    override func setUp() {
        super.setUp()
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("GTFSParserUnitTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tmpDir)
        super.tearDown()
    }

    // MARK: Stops — valid data

    func test_parseStops_returnsStop_forValidRow() throws {
        write("stops.txt", csv: """
        stop_id,stop_name,stop_lat,stop_lon
        S1,Penn Station,40.7506,-73.9971
        """)
        let stops = GTFSParser.parseStops(in: tmpDir)
        XCTAssertEqual(stops.count, 1)
        let stop = try XCTUnwrap(stops.first)
        XCTAssertEqual(stop.id,   "S1")
        XCTAssertEqual(stop.name, "Penn Station")
        XCTAssertEqual(stop.latitude,   40.7506, accuracy: 0.0001)
        XCTAssertEqual(stop.longitude, -73.9971, accuracy: 0.0001)
    }

    func test_parseStops_returnsMultipleStops() {
        write("stops.txt", csv: """
        stop_id,stop_name,stop_lat,stop_lon
        S1,Grand Central,40.7527,-73.9772
        S2,Times Square,40.7580,-73.9855
        S3,Union Square,40.7359,-73.9906
        """)
        let stops = GTFSParser.parseStops(in: tmpDir)
        XCTAssertEqual(stops.count, 3)
    }

    // MARK: Stops — coordinate rejection

    func test_parseStops_rejects_zeroZeroCoordinate() {
        // (0,0) is the GTFS sentinel for "no location" and must be filtered out
        write("stops.txt", csv: """
        stop_id,stop_name,stop_lat,stop_lon
        S1,Ghost Stop,0.0,0.0
        """)
        let stops = GTFSParser.parseStops(in: tmpDir)
        XCTAssertTrue(stops.isEmpty,
                      "(0,0) coordinates must be rejected — they indicate a missing location")
    }

    func test_parseStops_rejects_latAbove90() {
        write("stops.txt", csv: """
        stop_id,stop_name,stop_lat,stop_lon
        S1,Bad Stop,91.0,10.0
        """)
        XCTAssertTrue(GTFSParser.parseStops(in: tmpDir).isEmpty,
                      "Latitude > 90 must be rejected")
    }

    func test_parseStops_rejects_latBelow90() {
        write("stops.txt", csv: """
        stop_id,stop_name,stop_lat,stop_lon
        S1,Bad Stop,-91.0,10.0
        """)
        XCTAssertTrue(GTFSParser.parseStops(in: tmpDir).isEmpty,
                      "Latitude < -90 must be rejected")
    }

    func test_parseStops_rejects_lonAbove180() {
        write("stops.txt", csv: """
        stop_id,stop_name,stop_lat,stop_lon
        S1,Bad Stop,50.0,181.0
        """)
        XCTAssertTrue(GTFSParser.parseStops(in: tmpDir).isEmpty,
                      "Longitude > 180 must be rejected")
    }

    func test_parseStops_rejects_lonBelow180() {
        write("stops.txt", csv: """
        stop_id,stop_name,stop_lat,stop_lon
        S1,Bad Stop,50.0,-181.0
        """)
        XCTAssertTrue(GTFSParser.parseStops(in: tmpDir).isEmpty,
                      "Longitude < -180 must be rejected")
    }

    func test_parseStops_rejects_nonNumericLatitude() {
        write("stops.txt", csv: """
        stop_id,stop_name,stop_lat,stop_lon
        S1,Bad Stop,not_a_number,-73.9971
        """)
        XCTAssertTrue(GTFSParser.parseStops(in: tmpDir).isEmpty,
                      "Non-numeric latitude must be rejected gracefully")
    }

    func test_parseStops_rejects_nonNumericLongitude() {
        write("stops.txt", csv: """
        stop_id,stop_name,stop_lat,stop_lon
        S1,Bad Stop,40.7506,not_a_number
        """)
        XCTAssertTrue(GTFSParser.parseStops(in: tmpDir).isEmpty)
    }

    func test_parseStops_skips_badRows_butKeepsGoodOnes() {
        // Mix of one valid stop and one (0,0) sentinel
        write("stops.txt", csv: """
        stop_id,stop_name,stop_lat,stop_lon
        S1,Good Stop,40.7506,-73.9971
        S2,Ghost Stop,0.0,0.0
        """)
        let stops = GTFSParser.parseStops(in: tmpDir)
        XCTAssertEqual(stops.count, 1)
        XCTAssertEqual(stops.first?.id, "S1")
    }

    func test_parseStops_boundaryCases_acceptsEdgeCoordinates() {
        // Extreme but valid: North Pole and antimeridian
        write("stops.txt", csv: """
        stop_id,stop_name,stop_lat,stop_lon
        S1,North Pole,90.0,0.0
        S2,South Pole,-90.0,0.0
        S3,Antimeridian East,0.0,180.0
        S4,Antimeridian West,0.0,-180.0
        """)
        // (0,0) is blocked, but the others with only one coordinate zero are fine
        let stops = GTFSParser.parseStops(in: tmpDir)
        // S1 lat=90 lon=0: lon is 0 but lat is not 0 → not the (0,0) case → accepted
        // S2 lat=-90 lon=0: same → accepted
        // S3 lat=0 lon=180: lat=0 but lon≠0 → accepted
        // S4 lat=0 lon=-180: accepted
        XCTAssertEqual(stops.count, 4,
                       "Valid extreme coordinates (poles, antimeridian) must be accepted")
    }

    // MARK: Stops — CSV quoting

    func test_parseStops_quotedFieldWithComma() {
        // Stop name contains a comma inside quotes — must be treated as one field
        write("stops.txt", csv: """
        stop_id,stop_name,stop_lat,stop_lon
        S1,"Grand Central, 42nd St",40.7527,-73.9772
        """)
        let stops = GTFSParser.parseStops(in: tmpDir)
        XCTAssertEqual(stops.count, 1)
        XCTAssertEqual(stops.first?.name, "Grand Central, 42nd St",
                       "Comma inside quoted field must not split the field")
    }

    func test_parseStops_rfc4180_doubleQuoteEscape() {
        // RFC 4180: an embedded " is represented as ""
        write("stops.txt", csv: """
        stop_id,stop_name,stop_lat,stop_lon
        S1,"O""Hare Airport",41.9742,-87.9073
        """)
        let stops = GTFSParser.parseStops(in: tmpDir)
        XCTAssertEqual(stops.count, 1)
        XCTAssertEqual(stops.first?.name, "O\"Hare Airport",
                       "RFC 4180 double-quote escape (\"\") must be decoded as a single \"")
    }

    // MARK: Stops — empty / header-only

    func test_parseStops_emptyFile_returnsEmpty() {
        write("stops.txt", csv: "")
        XCTAssertTrue(GTFSParser.parseStops(in: tmpDir).isEmpty)
    }

    func test_parseStops_headerOnly_returnsEmpty() {
        write("stops.txt", csv: "stop_id,stop_name,stop_lat,stop_lon")
        XCTAssertTrue(GTFSParser.parseStops(in: tmpDir).isEmpty,
                      "Header-only file with no data rows must return []")
    }

    // MARK: Stops — UTF-8 BOM

    func test_parseStops_utf8BOM_parsedCorrectly() {
        // Some GTFS feeds prefix their CSV with a UTF-8 BOM (EF BB BF).
        // The parser must strip it from the first column header.
        let bom = "\u{FEFF}"
        write("stops.txt", csv: "\(bom)stop_id,stop_name,stop_lat,stop_lon\nS1,Central Park,40.7829,-73.9654")
        let stops = GTFSParser.parseStops(in: tmpDir)
        XCTAssertEqual(stops.count, 1,
                       "UTF-8 BOM must not prevent the stop_id column from being found")
    }

    // MARK: Stops — missing file

    func test_parseStops_missingFile_returnsEmpty() {
        // tmpDir has no stops.txt
        XCTAssertTrue(GTFSParser.parseStops(in: tmpDir).isEmpty,
                      "Missing stops.txt must return [] without crashing")
    }

    // MARK: Routes — valid data

    func test_parseRoutes_returnsRoute_forValidRow() {
        write("routes.txt", csv: """
        route_id,route_short_name,route_long_name,route_type,route_color
        R1,7,Flushing Local,1,EE352E
        """)
        let routes = GTFSParser.parseRoutes(in: tmpDir)
        XCTAssertEqual(routes.count, 1)
        XCTAssertEqual(routes.first?.id,        "R1")
        XCTAssertEqual(routes.first?.shortName, "7")
        XCTAssertEqual(routes.first?.longName,  "Flushing Local")
        XCTAssertEqual(routes.first?.type,      .subway)
        XCTAssertEqual(routes.first?.colorHex,  "EE352E")
    }

    // MARK: Routes — route_type mapping

    func test_parseRoutes_routeType_rail() {
        write("routes.txt", csv: "route_id,route_short_name,route_long_name,route_type\nR1,NJ,Rail,2")
        XCTAssertEqual(GTFSParser.parseRoutes(in: tmpDir).first?.type, .rail)
    }

    func test_parseRoutes_routeType_bus() {
        write("routes.txt", csv: "route_id,route_short_name,route_long_name,route_type\nR1,M,Bus,3")
        XCTAssertEqual(GTFSParser.parseRoutes(in: tmpDir).first?.type, .bus)
    }

    func test_parseRoutes_unknownRouteType_mapsToUnknown() {
        write("routes.txt", csv: "route_id,route_short_name,route_long_name,route_type\nR1,X,Mystery,42")
        XCTAssertEqual(GTFSParser.parseRoutes(in: tmpDir).first?.type, .unknown,
                       "Unrecognised route_type must map to .unknown, not crash")
    }

    func test_parseRoutes_missingFile_returnsEmpty() {
        XCTAssertTrue(GTFSParser.parseRoutes(in: tmpDir).isEmpty)
    }

    func test_parseRoutes_emptyFile_returnsEmpty() {
        write("routes.txt", csv: "")
        XCTAssertTrue(GTFSParser.parseRoutes(in: tmpDir).isEmpty)
    }

    func test_parseRoutes_headerOnly_returnsEmpty() {
        write("routes.txt", csv: "route_id,route_short_name,route_long_name,route_type")
        XCTAssertTrue(GTFSParser.parseRoutes(in: tmpDir).isEmpty)
    }

    // MARK: Routes — optional color

    func test_parseRoutes_emptyColorHex_yieldsNil() {
        write("routes.txt", csv: "route_id,route_short_name,route_long_name,route_type,route_color\nR1,A,Alpha,3,")
        let route = GTFSParser.parseRoutes(in: tmpDir).first
        XCTAssertNil(route?.colorHex,
                     "Empty route_color must yield nil colorHex, not an empty string")
    }

    // MARK: - Helpers

    private func write(_ filename: String, csv: String) {
        let url = tmpDir.appendingPathComponent(filename)
        try? csv.write(to: url, atomically: true, encoding: .utf8)
    }
}

// MARK: - CuratedFeeds integrity tests ────────────────────────────────────────

/// Verifies the built-in feed list is internally consistent.
/// These run without network access and catch editorial mistakes
/// (duplicate names, empty fields, typos in URL scheme).
final class CuratedFeedsIntegrityTests: XCTestCase {

    private let feeds = CuratedFeeds.all

    func test_allFeeds_haveNonEmptyName() {
        let blank = feeds.filter { $0.name.trimmingCharacters(in: .whitespaces).isEmpty }
        XCTAssertTrue(blank.isEmpty,
                      "Every CuratedFeed must have a non-empty name. Blanks: \(blank.map(\.name))")
    }

    func test_allFeeds_haveNonEmptyRegion() {
        let blank = feeds.filter { $0.region.trimmingCharacters(in: .whitespaces).isEmpty }
        XCTAssertTrue(blank.isEmpty,
                      "Every CuratedFeed must have a non-empty region. Blanks: \(blank.map(\.name))")
    }

    func test_allFeeds_haveNonEmptyRouteTypes() {
        let blank = feeds.filter { $0.routeTypes.trimmingCharacters(in: .whitespaces).isEmpty }
        XCTAssertTrue(blank.isEmpty,
                      "Every CuratedFeed must have routeTypes text: \(blank.map(\.name))")
    }

    func test_allFeeds_haveHTTPUrl() {
        let bad = feeds.filter { !$0.feedURL.lowercased().hasPrefix("http") }
        XCTAssertTrue(bad.isEmpty,
                      "Every feed URL must start with http(s): \(bad.map { "\($0.name): \($0.feedURL)" })")
    }

    func test_allFeeds_haveValidURLSyntax() {
        let invalid = feeds.filter { URL(string: $0.feedURL) == nil }
        XCTAssertTrue(invalid.isEmpty,
                      "Every feed URL must be parseable: \(invalid.map(\.feedURL))")
    }

    func test_allFeeds_haveUniqueNames() {
        let names = feeds.map(\.name)
        let unique = Set(names)
        XCTAssertEqual(names.count, unique.count,
                       "Feed names must be unique. Duplicates found if counts differ.")
    }

    func test_allFeeds_haveUniqueURLs() {
        let urls = feeds.map(\.feedURL)
        let unique = Set(urls)
        XCTAssertEqual(urls.count, unique.count,
                       "Feed URLs must be unique. Duplicate URLs found if counts differ.")
    }

    func test_feedCount_isExpected() {
        // Update this number when feeds are added or removed intentionally.
        // It acts as a tripwire against accidental deletions.
        XCTAssertEqual(feeds.count, 29,
                       "Expected 29 curated feeds. Update this test if the list changes intentionally.")
    }
}
