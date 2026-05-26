// GTFSParserTests.swift
// Tier 2 — Full download + parse tests for a representative subset of feeds.
//
// These tests download real GTFS ZIP files and run the complete pipeline
// (download → extract → parse).  They are slower than the URL reachability
// tests (~30–120 s each depending on file size) and are therefore excluded
// from the default "Test" action by default.
//
// How to run selectively:
//   xcodebuild test -project GeoAlarm.xcodeproj \
//     -scheme GeoAlarm -destination 'platform=iOS Simulator,name=iPhone 16' \
//     -only-testing:GeoAlarmTests/GTFSParserTests
//
// Skip condition:
//   Set the environment variable SKIP_PARSER_TESTS=1 to skip in CI environments
//   that want URL checks only (saves bandwidth / build time).

import XCTest
@testable import GeoAlarm

// GTFSService is @MainActor so the test class must be too.
@MainActor
final class GTFSParserTests: XCTestCase {

    // Feeds chosen for these tests are relatively small (<40 MB) and have
    // well-maintained static schedules.  Avoid very large feeds (TfNSW ~280 MB,
    // PTV Melbourne ~200 MB) in automated CI — they would inflate build minutes.
    private struct ParseTestCase {
        let name: String            // must match CuratedFeeds.all entry
        let minRoutes: Int          // minimum acceptable route count
        let minStops:  Int          // minimum acceptable stop count
    }

    private let testCases: [ParseTestCase] = [
        // MARTA — Atlanta rapid transit; ~20 MB, straightforward GTFS.
        ParseTestCase(name: "MARTA",              minRoutes: 5,  minStops: 50),
        // BART — Bay Area rapid transit; compact feed with a handful of stations.
        ParseTestCase(name: "BART",               minRoutes: 5,  minStops: 40),
        // DB Fernverkehr — German intercity rail; small feed, non-ASCII station names.
        ParseTestCase(name: "DB Fernverkehr (Germany)", minRoutes: 10, minStops: 100),
        // TriMet — Portland light rail + bus; mid-size feed.
        ParseTestCase(name: "TriMet",             minRoutes: 20, minStops: 500),
    ]

    // Generous per-test timeout: the full download + parse must complete within
    // this window.  Set higher than XCTest's default (600 s) for large feeds.
    override var timeoutForAsyncExpectations: TimeInterval { 180 }

    // MARK: - Tests

    /// Parse every test-case feed and collect failures in bulk so one broken
    /// feed doesn't hide the others.
    func testSelectedFeedsParseSuccessfully() async throws {
        try XCTSkipIf(
            ProcessInfo.processInfo.environment["SKIP_PARSER_TESTS"] == "1",
            "SKIP_PARSER_TESTS=1 — skipping full-parse tests"
        )
        try XCTSkipIf(
            ProcessInfo.processInfo.environment["SKIP_NETWORK_TESTS"] == "1",
            "SKIP_NETWORK_TESTS=1 — skipping network tests"
        )

        var failures: [String] = []

        for tc in testCases {
            do {
                let (routes, stops) = try await downloadAndParse(named: tc.name)
                if routes.count < tc.minRoutes {
                    failures.append(
                        "\(tc.name): expected ≥ \(tc.minRoutes) routes, got \(routes.count)"
                    )
                }
                if stops.count < tc.minStops {
                    failures.append(
                        "\(tc.name): expected ≥ \(tc.minStops) stops, got \(stops.count)"
                    )
                }
                // Verify every stop has valid lat/lon — parser guard should
                // reject bad values, but assert defensively here too.
                let badStops = stops.filter { s in
                    s.latitude  < -90  || s.latitude  > 90  ||
                    s.longitude < -180 || s.longitude > 180
                }
                if !badStops.isEmpty {
                    failures.append(
                        "\(tc.name): \(badStops.count) stop(s) with out-of-range coordinates"
                    )
                }
            } catch {
                failures.append("\(tc.name): \(error.localizedDescription)")
            }
        }

        XCTAssertTrue(
            failures.isEmpty,
            "GTFS parse failures:\n" + failures.joined(separator: "\n")
        )
    }

    // MARK: - Individual granular tests
    // One test per feed for quick isolation in Xcode's test navigator.

    func testMARTAParsesSuccessfully() async throws {
        try await assertParses("MARTA", minRoutes: 5, minStops: 50)
    }

    func testBARTParsesSuccessfully() async throws {
        try await assertParses("BART", minRoutes: 5, minStops: 40)
    }

    func testDBFernverkehrParsesSuccessfully() async throws {
        try await assertParses("DB Fernverkehr (Germany)", minRoutes: 10, minStops: 100)
    }

    func testTriMetParsesSuccessfully() async throws {
        try await assertParses("TriMet", minRoutes: 20, minStops: 500)
    }

    // MARK: - Helpers

    private func assertParses(_ name: String, minRoutes: Int, minStops: Int) async throws {
        try XCTSkipIf(
            ProcessInfo.processInfo.environment["SKIP_PARSER_TESTS"] == "1",
            "SKIP_PARSER_TESTS=1 — skipping full-parse tests"
        )
        try XCTSkipIf(
            ProcessInfo.processInfo.environment["SKIP_NETWORK_TESTS"] == "1",
            "SKIP_NETWORK_TESTS=1 — skipping network tests"
        )

        let (routes, stops) = try await downloadAndParse(named: name)

        XCTAssertGreaterThanOrEqual(
            routes.count, minRoutes,
            "\(name): expected ≥ \(minRoutes) routes, got \(routes.count)"
        )
        XCTAssertGreaterThanOrEqual(
            stops.count, minStops,
            "\(name): expected ≥ \(minStops) stops, got \(stops.count)"
        )

        let badStops = stops.filter { s in
            s.latitude  < -90  || s.latitude  > 90  ||
            s.longitude < -180 || s.longitude > 180
        }
        XCTAssertEqual(
            badStops.count, 0,
            "\(name): \(badStops.count) stop(s) with out-of-range coordinates"
        )
    }

    /// Download the named feed via GTFSService and return the parsed (routes, stops).
    private func downloadAndParse(named feedName: String) async throws -> ([GTFSRoute], [GTFSStop]) {
        guard let curated = CuratedFeeds.all.first(where: { $0.name == feedName }) else {
            throw TestError.feedNotFound(feedName)
        }

        let feedModel = GTFSFeedModel(
            name: curated.name,
            feedURL: curated.feedURL,
            regionLabel: curated.region
        )

        let service = GTFSService()
        await service.load(feed: feedModel)

        if let errMsg = service.errorMessage {
            throw TestError.serviceError(errMsg)
        }

        return (service.routes, service.stops)
    }

    enum TestError: LocalizedError {
        case feedNotFound(String)
        case serviceError(String)

        var errorDescription: String? {
            switch self {
            case .feedNotFound(let name):
                return "Feed '\(name)' not found in CuratedFeeds.all"
            case .serviceError(let msg):
                return msg
            }
        }
    }
}
