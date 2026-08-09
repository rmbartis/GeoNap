// Copyright © 2026 Robert Bartis. All rights reserved.

// GTFSReinstallCacheFallbackTests.swift
// Regression coverage for the 2026-08-09 bug: GTFSFeedModel lives in the
// CloudKit-backed SwiftData store (see ModelContainerFactory.swift), so a
// delete/reinstall can bring a feed's cache METADATA back (isCached: true,
// a recent lastDownloaded) via iCloud sync even though the extracted
// routes.txt/stops.txt files it points to lived in the local-only Caches
// directory, which the reinstall wiped. Before the fix, GTFSService.load(
// feed:) trusted the metadata alone, called parse(from:) on a directory
// that no longer existed, and silently ended up with zero routes/stops and
// no error — surfaced to Bob as "No Routes Found" for Amtrak after a
// reinstall, with no indication anything had gone wrong.
//
// This test does NOT touch the network. It proves the fix by using an
// invalid feedURL ("") — GTFSService.downloadAndParse's very first step is
// `URL(string: feed.feedURL)`, which fails synchronously and sets
// errorMessage before any network call is attempted. So:
//   - Before the fix: cache metadata alone was enough to reach
//     `parse(from: dir)` on a missing directory → errorMessage stays nil,
//     routes/stops silently empty. This test's errorMessage assertion
//     would have FAILED.
//   - After the fix: the missing on-disk directory forces the download
//     branch, which immediately fails on the invalid URL and sets
//     errorMessage → this test's assertion passes.
// That distinguishes "correctly fell back to download" from "incorrectly
// treated stale metadata as a cache hit" without any network dependency,
// matching the project's preference for fast, deterministic unit tests
// (see GTFSCacheTests.swift's header comment).

import XCTest
@testable import GeoNap

// GTFSService is @MainActor.
@MainActor
final class GTFSReinstallCacheFallbackTests: XCTestCase {

    func test_freshCacheMetadata_missingOnDiskDirectory_fallsBackToDownload_insteadOfSilentEmptyResult() async {
        let feed = GTFSFeedModel(
            name: "Amtrak (Test)",
            feedURL: "",   // deliberately invalid — see header comment
            regionLabel: "USA · National"
        )
        // Simulate a CloudKit-synced record: metadata claims a fresh,
        // already-extracted cache under a directory name that was never
        // actually created on this device (a fresh UUID guarantees that).
        feed.cachedDirectoryName = UUID().uuidString
        feed.lastDownloaded = Date()   // "just downloaded" — well within any retention window

        XCTAssertTrue(feed.isCached, "Precondition: metadata alone should read as cached.")
        if let dir = feed.cachedDirectoryURL {
            XCTAssertFalse(
                FileManager.default.fileExists(atPath: dir.path),
                "Precondition: the directory the metadata points to must not actually exist on disk."
            )
        }

        let service = GTFSService()
        await service.load(feed: feed)

        XCTAssertNotNil(
            service.errorMessage,
            "With the on-disk directory missing, load(feed:) must fall back to downloadAndParse (which fails fast on the invalid test URL) rather than silently returning an empty result from a cache hit that was never actually on disk."
        )
        XCTAssertTrue(service.routes.isEmpty)
        XCTAssertTrue(service.stops.isEmpty)
    }

    func test_freshCacheMetadata_directoryPresent_usesCacheWithoutError() async throws {
        // Contrast case: when the directory genuinely exists (even if empty
        // of GTFS files, which just parses to zero routes/stops the normal
        // way), load(feed:) must still take the cache path rather than
        // re-downloading — this test guards against over-correcting the fix
        // into always re-downloading regardless of on-disk state.
        let feed = GTFSFeedModel(
            name: "Amtrak (Test)",
            feedURL: "",   // must never be reached — download would fail on this
            regionLabel: "USA · National"
        )
        let dirName = UUID().uuidString
        feed.cachedDirectoryName = dirName
        feed.lastDownloaded = Date()

        guard let dir = feed.cachedDirectoryURL else {
            XCTFail("cachedDirectoryURL should resolve once cachedDirectoryName is set.")
            return
        }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let service = GTFSService()
        await service.load(feed: feed)

        XCTAssertNil(
            service.errorMessage,
            "A genuinely present cache directory must be used as-is, not trigger a (failing) re-download."
        )
    }
}
