// Copyright © 2026 Robert Bartis. All rights reserved.

// DebugLoggerTests.swift
// Unit tests for DebugLogTrimmer.trim(_:maxBytes:targetBytes:noticePrefix:)
// — the size-cap fix added 2026-09-28 after deciding to leave Calendar
// Scanning's diagnostic logging (getPendingTaskRequests) on indefinitely,
// which meant the previously-unbounded, append-only GeoNapDebug.log needed
// an actual ceiling.
//
// Tested as a pure function against small in-memory Data fixtures rather
// than by writing real multi-MB files to disk and exercising the actual
// DebugLogger singleton — mirrors the "pure logic only" testing convention
// used throughout this project (CalendarScanRefreshScheduling,
// CalendarScanCandidateMerger, CalendarScanLocationExtractor, etc.).

import XCTest
@testable import GeoNap

final class DebugLogTrimmerTests: XCTestCase {

    private func lineData(_ lines: [String]) -> Data {
        Data(lines.map { "\($0)\n" }.joined().utf8)
    }

    func test_underCap_returnsNil() {
        let data = lineData(["a", "b", "c"])
        let result = DebugLogTrimmer.trim(data, maxBytes: 1000, targetBytes: 500, noticePrefix: "NOTICE\n")
        XCTAssertNil(result, "A file under the cap should not be touched")
    }

    func test_exactlyAtCap_returnsNil() {
        // Guard is `data.count > maxBytes`, not `>=` — a file exactly at the
        // cap doesn't need trimming yet.
        let data = Data(repeating: 0x41, count: 100) // 100 bytes of "A"
        let result = DebugLogTrimmer.trim(data, maxBytes: 100, targetBytes: 50, noticePrefix: "NOTICE\n")
        XCTAssertNil(result)
    }

    func test_overCap_trimsToApproximatelyTargetBytesPlusNotice() {
        // 100 lines of exactly 10 bytes each ("line-001\n" style, padded) = 1000 bytes total.
        let lines = (1...100).map { String(format: "line-%03d", $0) } // 8 chars + \n = 9 bytes each
        let data = lineData(lines)
        XCTAssertEqual(data.count, 900)

        let result = DebugLogTrimmer.trim(data, maxBytes: 500, targetBytes: 300, noticePrefix: "NOTICE\n")
        XCTAssertNotNil(result)
        guard let result else { return }

        // Kept content should be meaningfully smaller than the original.
        XCTAssertLessThan(result.count, data.count)
        // And should start with the notice.
        XCTAssertTrue(result.starts(with: Data("NOTICE\n".utf8)))
    }

    func test_overCap_keepsTheMostRecentLinesNotTheOldest() {
        let lines = (1...50).map { "entry-\($0)" }
        let data = lineData(lines)

        let result = DebugLogTrimmer.trim(data, maxBytes: 200, targetBytes: 100, noticePrefix: "TRIMMED\n")
        guard let result, let resultString = String(data: result, encoding: .utf8) else {
            return XCTFail("Expected trimmed, UTF-8-decodable result")
        }

        // The earliest entries must be gone...
        XCTAssertFalse(resultString.contains("entry-1\n"), "Oldest entries should have been dropped")
        XCTAssertFalse(resultString.contains("entry-2\n"))
        // ...but the most recent entry must survive.
        XCTAssertTrue(resultString.contains("entry-50"), "Newest entry must be preserved")
    }

    func test_overCap_neverLeavesATruncatedPartialLineAtTheStart() {
        // Deliberately choose a targetBytes that would land mid-line without
        // the newline-snap — every kept line must be complete.
        let lines = ["aaaaaaaaaa", "bbbbbbbbbb", "cccccccccc", "dddddddddd", "eeeeeeeeee"] // 11 bytes each incl. \n = 55 bytes
        let data = lineData(lines)

        let result = DebugLogTrimmer.trim(data, maxBytes: 20, targetBytes: 15, noticePrefix: "")
        guard let result, let resultString = String(data: result, encoding: .utf8) else {
            return XCTFail("Expected trimmed, UTF-8-decodable result")
        }

        // Every line remaining should be one of the original, complete lines
        // — never a fragment like "aaaa" or "bbbbbbbbbb" cut off partway.
        let keptLines = resultString.split(separator: "\n").map(String.init)
        for line in keptLines {
            XCTAssertTrue(lines.contains(line), "Kept line '\(line)' should be a complete original line, not a fragment")
        }
    }

    func test_degenerateTargetGreaterThanOrEqualToDataSize_dropsToNoticeOnly() {
        let data = lineData(["only-line"])
        let result = DebugLogTrimmer.trim(data, maxBytes: 1, targetBytes: 999, noticePrefix: "NOTICE\n")
        XCTAssertEqual(result, Data("NOTICE\n".utf8))
    }

    func test_degenerateZeroTarget_dropsToNoticeOnly() {
        let data = lineData(["only-line"])
        let result = DebugLogTrimmer.trim(data, maxBytes: 1, targetBytes: 0, noticePrefix: "NOTICE\n")
        XCTAssertEqual(result, Data("NOTICE\n".utf8))
    }

    func test_realisticCap_2MBTo1MB_trimsRoughlyInHalf() {
        // Mirrors DebugLogger's actual configured cap (2 MB / 1 MB) with a
        // realistically-sized synthetic log (repeated ~90-byte entries, in
        // line with a typical "[timestamp] [category] message" line).
        let sampleLine = "[2026-09-28T12:00:00Z] [CalendarScan] Background calendar scan: found=11 pending=11 new=0"
        let lineCount = 25_000 // ~90 bytes * 25,000 ≈ 2.25 MB
        let data = lineData(Array(repeating: sampleLine, count: lineCount))
        XCTAssertGreaterThan(data.count, 2 * 1024 * 1024)

        let maxBytes = 2 * 1024 * 1024
        let targetBytes = 1 * 1024 * 1024
        let result = DebugLogTrimmer.trim(data, maxBytes: maxBytes, targetBytes: targetBytes, noticePrefix: "NOTICE\n")

        XCTAssertNotNil(result)
        guard let result else { return }
        XCTAssertLessThan(result.count, data.count, "Trimmed file must be smaller than the original")
        XCTAssertLessThan(result.count, maxBytes, "Trimmed file must end up back under the cap")
        // Allow slack for the newline-snap plus the notice prefix.
        XCTAssertLessThan(result.count, targetBytes + sampleLine.utf8.count + 100)
    }
}
