// GTFSCacheTests.swift
// Pure-logic coverage for GTFSService.shouldUseCache(...) and
// effectiveRetentionDays(...) — the decision of whether a previously
// downloaded GTFS feed's on-disk cache should be reused instead of
// re-downloading.
//
// Caching is NOT opt-in: it always happens, silently, with a fixed 7-day
// retention window by default. Settings → "Customize Cache Duration" does
// not turn caching on/off — it only unlocks overriding that fixed window
// with a custom value (1–30 days, or the Infinite sentinel that never
// auto-expires). See AppSettings.swift's registerGTFSCacheDefaults() and
// SettingsView.swift's gtfsCacheSection
// (Bob, 2026-07-07 — corrected from the original 2026-07-06 "opt-in" spec
// after Bob reported the cache appearing not to work with the toggle off,
// which turned out to be by design under the old, mistaken reading).
//
// No disk, UserDefaults, or network access is exercised here — both
// functions take every input as a parameter (including an injectable `now`
// for shouldUseCache), matching the project's convention for testable
// decision functions (see ETAEstimatorTests, AddAlarmViewGPSLockTests,
// NapAlarmDeadReckoningTests).

import XCTest
@testable import GeoNap

final class GTFSCacheTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_800_000_000) // fixed reference instant

    // MARK: - Not yet cached

    func test_notCached_neverUsesCache() {
        let result = GTFSService.shouldUseCache(
            isCached: false,
            lastDownloaded: nil,
            retentionDays: 7,
            now: now
        )
        XCTAssertFalse(result)
    }

    func test_cachedButNoDownloadDate_neverUsesCache() {
        // Defensive: isCached is normally derived from lastDownloaded being
        // non-nil, but shouldUseCache should not assume that invariant holds.
        let result = GTFSService.shouldUseCache(
            isCached: true,
            lastDownloaded: nil,
            retentionDays: 7,
            now: now
        )
        XCTAssertFalse(result)
    }

    // MARK: - Fresh vs. expired (fixed default 7-day window)

    func test_fresh_usesCache() {
        let oneDayAgo = now.addingTimeInterval(-1 * 86_400)
        let result = GTFSService.shouldUseCache(
            isCached: true,
            lastDownloaded: oneDayAgo,
            retentionDays: 7,
            now: now
        )
        XCTAssertTrue(result, "A feed downloaded 1 day ago is within the default 7-day window")
    }

    func test_exactlyAtRetentionBoundary_isExpired() {
        // Exactly retentionDays old is no longer "fresh" — boundary is exclusive.
        let exactlyAtBoundary = now.addingTimeInterval(-7 * 86_400)
        let result = GTFSService.shouldUseCache(
            isCached: true,
            lastDownloaded: exactlyAtBoundary,
            retentionDays: 7,
            now: now
        )
        XCTAssertFalse(result)
    }

    func test_justUnderRetentionBoundary_isFresh() {
        let justUnder = now.addingTimeInterval(-7 * 86_400 + 60)
        let result = GTFSService.shouldUseCache(
            isCached: true,
            lastDownloaded: justUnder,
            retentionDays: 7,
            now: now
        )
        XCTAssertTrue(result)
    }

    func test_expired_doesNotUseCache() {
        let tenDaysAgo = now.addingTimeInterval(-10 * 86_400)
        let result = GTFSService.shouldUseCache(
            isCached: true,
            lastDownloaded: tenDaysAgo,
            retentionDays: 7,
            now: now
        )
        XCTAssertFalse(result)
    }

    // MARK: - Custom retention (1-30 days)

    func test_customRetention_freshWithinCustomWindow_usesCache() {
        let twentyDaysAgo = now.addingTimeInterval(-20 * 86_400)
        let result = GTFSService.shouldUseCache(
            isCached: true,
            lastDownloaded: twentyDaysAgo,
            retentionDays: 30,
            now: now
        )
        XCTAssertTrue(result)
    }

    func test_customRetention_expiredOutsideCustomWindow_doesNotUseCache() {
        let fortyDaysAgo = now.addingTimeInterval(-40 * 86_400)
        let result = GTFSService.shouldUseCache(
            isCached: true,
            lastDownloaded: fortyDaysAgo,
            retentionDays: 30,
            now: now
        )
        XCTAssertFalse(result)
    }

    // MARK: - Infinite retention sentinel

    func test_infiniteRetention_alwaysUsesCache_evenWhenVeryOld() {
        let tenYearsAgo = now.addingTimeInterval(-10 * 365 * 86_400)
        let result = GTFSService.shouldUseCache(
            isCached: true,
            lastDownloaded: tenYearsAgo,
            retentionDays: AppStorageKey.gtfsCacheInfiniteRetention,
            now: now
        )
        XCTAssertTrue(result, "Infinite retention means the cache never expires automatically")
    }

    func test_infiniteRetention_stillRequiresIsCached() {
        let result = GTFSService.shouldUseCache(
            isCached: false,
            lastDownloaded: nil,
            retentionDays: AppStorageKey.gtfsCacheInfiniteRetention,
            now: now
        )
        XCTAssertFalse(result)
    }

    // MARK: - Retention days edge cases

    func test_zeroRetentionDays_neverUsesCache() {
        let result = GTFSService.shouldUseCache(
            isCached: true,
            lastDownloaded: now, // downloaded this instant
            retentionDays: 0,
            now: now
        )
        XCTAssertFalse(result, "A 0-day retention window means never reuse the cache")
    }

    func test_negativeRetentionDays_neverUsesCache() {
        // Defensive: a corrupt/never-registered UserDefaults value shouldn't
        // be able to produce a negative window that somehow always matches.
        let result = GTFSService.shouldUseCache(
            isCached: true,
            lastDownloaded: now,
            retentionDays: -1,
            now: now
        )
        XCTAssertFalse(result)
    }

    // MARK: - effectiveRetentionDays(customRetentionEnabled:storedRetentionDays:)

    func test_customRetentionDisabled_alwaysResolvesToFixedDefault() {
        // Even if a stale custom value (e.g. 30, or the Infinite sentinel)
        // is still sitting in UserDefaults from a previous session, turning
        // "Customize Cache Duration" off must ignore it and use the fixed
        // 7-day default (Bob, 2026-07-07).
        XCTAssertEqual(
            GTFSService.effectiveRetentionDays(customRetentionEnabled: false, storedRetentionDays: 30),
            AppStorageKey.gtfsCacheDefaultRetentionDays
        )
        XCTAssertEqual(
            GTFSService.effectiveRetentionDays(customRetentionEnabled: false, storedRetentionDays: AppStorageKey.gtfsCacheInfiniteRetention),
            AppStorageKey.gtfsCacheDefaultRetentionDays
        )
    }

    func test_customRetentionEnabled_usesStoredValue() {
        XCTAssertEqual(
            GTFSService.effectiveRetentionDays(customRetentionEnabled: true, storedRetentionDays: 15),
            15
        )
        XCTAssertEqual(
            GTFSService.effectiveRetentionDays(customRetentionEnabled: true, storedRetentionDays: AppStorageKey.gtfsCacheInfiniteRetention),
            AppStorageKey.gtfsCacheInfiniteRetention
        )
    }

    func test_customRetentionEnabled_normalizesStrayOutOfRangeStoredValue() {
        // Regression: a build carried forward a UserDefaults value of 42
        // from an earlier version of this feature whose stepper allowed
        // 1...90 — the redesigned 1-30/Infinite stepper must not silently
        // honor that as a legitimate 42-day window (Bob, 2026-07-08).
        XCTAssertEqual(
            GTFSService.effectiveRetentionDays(customRetentionEnabled: true, storedRetentionDays: 42),
            AppStorageKey.gtfsCacheDefaultRetentionDays
        )
    }

    // MARK: - normalizedRetentionDays(_:)

    func test_normalizedRetentionDays_passesThroughValidRange() {
        for day in [1, 7, 15, 30] {
            XCTAssertEqual(GTFSService.normalizedRetentionDays(day), day)
        }
    }

    func test_normalizedRetentionDays_infiniteSentinelPassesThrough() {
        XCTAssertEqual(
            GTFSService.normalizedRetentionDays(AppStorageKey.gtfsCacheInfiniteRetention),
            AppStorageKey.gtfsCacheInfiniteRetention
        )
        // Anything at or above the sentinel collapses to the canonical sentinel.
        XCTAssertEqual(
            GTFSService.normalizedRetentionDays(AppStorageKey.gtfsCacheInfiniteRetention + 500),
            AppStorageKey.gtfsCacheInfiniteRetention
        )
    }

    func test_normalizedRetentionDays_outOfRangeFallsBackToDefault() {
        // 31-9998 is a gap no current UI can produce, but old builds (1...90
        // stepper) or corrupt data could still leave a value there.
        for stray in [0, -1, 31, 42, 90, AppStorageKey.gtfsCacheInfiniteRetention - 1] {
            XCTAssertEqual(
                GTFSService.normalizedRetentionDays(stray),
                AppStorageKey.gtfsCacheDefaultRetentionDays,
                "raw value \(stray) should normalize to the 7-day default"
            )
        }
    }
}
