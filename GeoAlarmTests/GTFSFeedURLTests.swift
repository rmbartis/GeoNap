// GTFSFeedURLTests.swift
// Tier 1 — URL reachability tests for all curated GTFS feeds.
// Makes a lightweight HTTP request (HEAD, or byte-range GET as fallback) for
// each URL and asserts a 2xx response code.  No full download is performed,
// so the suite should complete in roughly 30–60 seconds.
//
// Run from the command line:
//   xcodebuild test -project GeoAlarm.xcodeproj \
//     -scheme GeoAlarm -destination 'platform=iOS Simulator,name=iPhone 16' \
//     -only-testing:GeoAlarmTests/GTFSFeedURLTests
//
// These tests require network access.  They are skipped automatically when the
// CI environment variable SKIP_NETWORK_TESTS is set to "1".

import XCTest
@testable import GeoAlarm

final class GTFSFeedURLTests: XCTestCase {

    // Generous per-request ceiling; the point is reachability, not speed.
    private let requestTimeout: TimeInterval = 30

    // Each test case corresponds to one curated feed entry.
    // The test is table-driven so new feeds added to CuratedFeeds.all are
    // automatically picked up without changing this file.

    func testAllCuratedFeedURLsAreReachable() async throws {
        // Allow callers to opt out in offline / restricted environments.
        try XCTSkipIf(
            ProcessInfo.processInfo.environment["SKIP_NETWORK_TESTS"] == "1",
            "SKIP_NETWORK_TESTS=1 — skipping network tests"
        )

        let session = URLSession(configuration: .ephemeral)
        var failures: [String] = []

        for feed in CuratedFeeds.all {
            guard let url = URL(string: feed.feedURL) else {
                failures.append("\(feed.name): malformed URL — \(feed.feedURL)")
                continue
            }

            do {
                let status = try await reachabilityStatus(for: url, session: session)
                if !(200...299).contains(status) {
                    failures.append("\(feed.name) [\(feed.region)]: HTTP \(status) — \(feed.feedURL)")
                }
            } catch {
                failures.append("\(feed.name) [\(feed.region)]: \(error.localizedDescription) — \(feed.feedURL)")
            }
        }

        XCTAssertTrue(
            failures.isEmpty,
            "One or more GTFS feed URLs are unreachable:\n" + failures.joined(separator: "\n")
        )
    }

    // MARK: - Individual feed tests
    // One test per feed gives granular pass/fail in Xcode's test navigator.

    func testAmtrak()            async throws { try await assertReachable("Amtrak") }
    func testMARA()              async throws { try await assertReachable("MARTA") }
    func testMBTA()              async throws { try await assertReachable("MBTA") }
    func testChicagoTransit()    async throws { try await assertReachable("Chicago Transit Authority") }
    func testMetra()             async throws { try await assertReachable("Metra") }
    func testDART()              async throws { try await assertReachable("DART") }
    func testDenverRTD()         async throws { try await assertReachable("Denver RTD") }
    func testHoustonMetro()      async throws { try await assertReachable("Houston Metro") }
    func testLAMetroRail()       async throws { try await assertReachable("LA Metro Rail") }
    func testMiamiDade()         async throws { try await assertReachable("Miami-Dade Transit") }
    func testMetroTransit()      async throws { try await assertReachable("Metro Transit") }
    func testNYCSubway()         async throws { try await assertReachable("NYC Subway (MTA)") }
    func testMTAMetroNorth()     async throws { try await assertReachable("MTA Metro-North") }
    func testMTALIRR()           async throws { try await assertReachable("MTA Long Island Rail Road") }
    func testValleyMetro()       async throws { try await assertReachable("Valley Metro") }
    func testTriMet()            async throws { try await assertReachable("TriMet") }
    func testUTA()               async throws { try await assertReachable("UTA (TRAX)") }
    func testBART()              async throws { try await assertReachable("BART") }
    func testSFMTA()             async throws { try await assertReachable("SFMTA / Muni") }
    func testSoundTransit()      async throws { try await assertReachable("Sound Transit") }
    func testSNCF()              async throws { try await assertReachable("SNCF TER (France)") }
    func testDBFernverkehr()     async throws { try await assertReachable("DB Fernverkehr (Germany)") }
    func testOCTranspo()         async throws { try await assertReachable("OC Transpo") }
    func testTTC()               async throws { try await assertReachable("TTC") }
    func testTransLink()         async throws { try await assertReachable("TransLink") }
    func testCalgaryTransit()    async throws { try await assertReachable("Calgary Transit") }
    func testTfNSW()             async throws { try await assertReachable("Transport for NSW") }
    func testPTVMelbourne()      async throws { try await assertReachable("PTV (Metro Trains Melbourne)") }
    func testBrisbaneTranslink() async throws { try await assertReachable("Brisbane Translink") }

    // MARK: - Helpers

    /// Assert that the named curated feed returns HTTP 2xx.
    private func assertReachable(_ feedName: String) async throws {
        try XCTSkipIf(
            ProcessInfo.processInfo.environment["SKIP_NETWORK_TESTS"] == "1",
            "SKIP_NETWORK_TESTS=1 — skipping network tests"
        )

        guard let feed = CuratedFeeds.all.first(where: { $0.name == feedName }) else {
            XCTFail("Feed '\(feedName)' not found in CuratedFeeds.all")
            return
        }
        guard let url = URL(string: feed.feedURL) else {
            XCTFail("\(feedName): malformed URL — \(feed.feedURL)")
            return
        }

        let session = URLSession(configuration: .ephemeral)
        let status = try await reachabilityStatus(for: url, session: session)
        XCTAssertTrue(
            (200...299).contains(status),
            "\(feedName): expected HTTP 2xx, got \(status) — \(feed.feedURL)"
        )
    }

    /// Returns the HTTP status code for `url` using HEAD, falling back to a
    /// single-byte range GET if the server does not support HEAD.
    private func reachabilityStatus(for url: URL, session: URLSession) async throws -> Int {
        // --- Attempt 1: HEAD ---
        var headRequest = URLRequest(url: url, timeoutInterval: requestTimeout)
        headRequest.httpMethod = "HEAD"
        // Some CDNs return 403 for HEAD but allow GET; try range-GET as fallback.
        let (_, headResponse) = try await session.data(for: headRequest)
        if let http = headResponse as? HTTPURLResponse {
            if http.statusCode != 405 && http.statusCode != 403 {
                return http.statusCode
            }
        }

        // --- Fallback: Range GET (first byte only) ---
        var rangeRequest = URLRequest(url: url, timeoutInterval: requestTimeout)
        rangeRequest.setValue("bytes=0-0", forHTTPHeaderField: "Range")
        let (_, rangeResponse) = try await session.data(for: rangeRequest)
        guard let http = rangeResponse as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        // 206 Partial Content is a success for a range request.
        return http.statusCode == 206 ? 200 : http.statusCode
    }
}
