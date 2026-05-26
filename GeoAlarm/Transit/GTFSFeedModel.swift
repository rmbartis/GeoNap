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
}
