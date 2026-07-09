// Copyright © 2026 Robert Bartis. All rights reserved.

// GTFSFeedModel.swift
// SwiftData model representing a saved GTFS agency feed.
// Stores the feed URL and tracks when data was last downloaded.

import Foundation
import SwiftData

@Model
final class GTFSFeedModel {

    var id: UUID = UUID()
    var name: String = ""           // Display name, e.g. "Amtrak"
    var feedURL: String = ""        // GTFS ZIP download URL
    var regionLabel: String = ""    // e.g. "USA · National"
    var lastDownloaded: Date? = nil

    /// Path to the directory where this feed's ZIP was extracted.
    /// Relative to the app's Caches directory.
    var cachedDirectoryName: String? = nil

    var isCached: Bool { cachedDirectoryName != nil && lastDownloaded != nil }

    init(name: String, feedURL: String, regionLabel: String = "") {
        self.name        = name
        self.feedURL     = feedURL
        self.regionLabel = regionLabel
    }

    /// Full URL to the cached extraction directory, if it exists.
    var cachedDirectoryURL: URL? {
        guard let name = cachedDirectoryName else { return nil }
        return FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("gtfs", isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
    }

    /// Finds the previously-persisted feed record for this URL, or creates
    /// and inserts a new one.
    ///
    /// Before this existed, `TransitAlarmView` constructed a fresh
    /// `GTFSFeedModel(name:feedURL:regionLabel:)` on every agency/stop
    /// selection — never inserting it into `modelContext` — so `id` (and the
    /// on-disk cache directory keyed by `id.uuidString`) was a new random
    /// UUID every single time, and `cachedDirectoryName`/`lastDownloaded`
    /// never survived past the current view's lifetime. Keying the lookup by
    /// `feedURL` (stable per agency) instead of `id` (random) is what lets a
    /// repeat visit to the same agency find its existing cache record
    /// (Bob, 2026-07-06 — GTFS caching feature).
    static func existingOrNew(
        name: String,
        feedURL: String,
        regionLabel: String = "",
        in context: ModelContext
    ) -> GTFSFeedModel {
        let descriptor = FetchDescriptor<GTFSFeedModel>(
            predicate: #Predicate { $0.feedURL == feedURL }
        )
        if let existing = try? context.fetch(descriptor).first {
            // Keep display metadata current (a curated feed's display name or
            // region label can change between app versions) without
            // disturbing its cache state.
            existing.name = name
            if !regionLabel.isEmpty {
                existing.regionLabel = regionLabel
            }
            return existing
        }
        let model = GTFSFeedModel(name: name, feedURL: feedURL, regionLabel: regionLabel)
        context.insert(model)
        return model
    }
}
