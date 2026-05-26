// GTFSService.swift
// Downloads a GTFS ZIP feed, extracts routes.txt and stops.txt,
// parses them into GTFSRoute / GTFSStop arrays, and caches the result.
//
// DEPENDENCY: ZipFoundation must be added as a Swift Package.
//   URL: https://github.com/weichsel/ZIPFoundation.git  (Up Next Major Version)

import Foundation
import Combine
import CoreLocation
import ZIPFoundation

@MainActor
final class GTFSService: ObservableObject {

    // MARK: - Published state

    @Published var routes: [GTFSRoute] = []
    @Published var stops:  [GTFSStop]  = []
    @Published var downloadProgress: Double = 0   // 0.0 – 1.0
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil

    // MARK: - Private

    private var downloadTask: URLSessionTask? = nil

    // MARK: - Public API

    /// Load from cache if available, otherwise download and parse.
    func load(feed: GTFSFeedModel) async {
        errorMessage = nil

        if feed.isCached, let dir = feed.cachedDirectoryURL {
            await parse(from: dir)
        } else {
            await downloadAndParse(feed: feed)
        }
    }

    /// Force a fresh download even if data is already cached.
    func refresh(feed: GTFSFeedModel) async {
        errorMessage = nil
        await downloadAndParse(feed: feed)
    }

    /// Cancel any in-flight download.
    func cancel() {
        downloadTask?.cancel()
        downloadTask = nil
        isLoading = false
        downloadProgress = 0
    }

    // MARK: - Download

    private func downloadAndParse(feed: GTFSFeedModel) async {
        guard let url = URL(string: feed.feedURL) else {
            errorMessage = "Invalid feed URL."
            return
        }

        isLoading = true
        downloadProgress = 0
        defer { isLoading = false }

        do {
            let zipURL = try await download(from: url)
            let extractDir = try extract(zipURL: zipURL, feedID: feed.id.uuidString)

            // Persist the cache directory name back to the model
            feed.cachedDirectoryName = extractDir.lastPathComponent
            feed.lastDownloaded = Date()
            // Caller's ModelContext will save on next cycle.

            await parse(from: extractDir)

            // Clean up the temporary ZIP file
            try? FileManager.default.removeItem(at: zipURL)
        } catch is CancellationError {
            // User cancelled — leave progress where it is
        } catch {
            errorMessage = "Download failed: \(error.localizedDescription)"
        }
    }

    // Returns a temporary file URL for the downloaded ZIP.
    private func download(from url: URL) async throws -> URL {
        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".zip")

        return try await withCheckedThrowingContinuation { continuation in
            let session = URLSession(
                configuration: .default,
                delegate: nil,
                delegateQueue: nil
            )
            var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
            request.timeoutInterval = 120

            let task = session.downloadTask(with: request) { location, response, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                // Reject non-2xx HTTP responses (e.g. redirect to HTML login page)
                if let http = response as? HTTPURLResponse,
                   !(200...299).contains(http.statusCode) {
                    continuation.resume(throwing: GTFSError.httpError(http.statusCode))
                    return
                }
                guard let location else {
                    continuation.resume(throwing: GTFSError.downloadFailed)
                    return
                }
                // Verify the file starts with a ZIP magic header (PK: 0x50 0x4B).
                // Some agency URLs redirect to an HTML page with a 200 status,
                // so we double-check the raw bytes.
                if let fh = FileHandle(forReadingAtPath: location.path) {
                    let magic = fh.readData(ofLength: 4)
                    fh.closeFile()
                    if magic.count < 4 || magic[0] != 0x50 || magic[1] != 0x4B {
                        continuation.resume(throwing: GTFSError.notAZipFile)
                        return
                    }
                }
                do {
                    if FileManager.default.fileExists(atPath: tmpURL.path) {
                        try FileManager.default.removeItem(at: tmpURL)
                    }
                    try FileManager.default.moveItem(at: location, to: tmpURL)
                    continuation.resume(returning: tmpURL)
                } catch {
                    continuation.resume(throwing: error)
                }
            }

            // Progress observation via KVO
            let observation = task.progress.observe(\.fractionCompleted) { [weak self] progress, _ in
                Task { @MainActor [weak self] in
                    self?.downloadProgress = progress.fractionCompleted * 0.9  // reserve last 10% for parsing
                }
            }

            // Retain the observation for the task's lifetime
            objc_setAssociatedObject(task, &GTFSService.observationKey, observation, .OBJC_ASSOCIATION_RETAIN)

            self.downloadTask = task
            task.resume()
        }
    }

    private static var observationKey: UInt8 = 0

    // MARK: - Extraction

    private func extract(zipURL: URL, feedID: String) throws -> URL {
        let cachesDir = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("gtfs", isDirectory: true)
            .appendingPathComponent(feedID, isDirectory: true)

        // Remove old extraction if present
        if FileManager.default.fileExists(atPath: cachesDir.path) {
            try FileManager.default.removeItem(at: cachesDir)
        }
        try FileManager.default.createDirectory(at: cachesDir, withIntermediateDirectories: true)

        // Extract only the GTFS text files we need.
        // Using entry-by-entry extraction avoids ZIPFoundation's invalidEntryPath
        // error (error 13) that fires on feeds with __MACOSX metadata, absolute
        // paths, or other non-standard ZIP structures.
        guard let archive = Archive(url: zipURL, accessMode: .read) else {
            throw GTFSError.downloadFailed
        }

        let neededFiles: Set<String> = ["routes.txt", "stops.txt", "trips.txt",
                                        "stop_times.txt", "calendar.txt"]

        for entry in archive {
            let rawPath = entry.path

            // Skip macOS metadata and hidden files
            if rawPath.hasPrefix("__MACOSX") || rawPath.hasPrefix(".") { continue }
            if entry.type == .directory { continue }

            // Normalise to lowercase — some agencies use "Routes.txt" or "STOPS.TXT"
            // and our neededFiles set is all-lowercase.
            let filename = (rawPath as NSString).lastPathComponent.lowercased()
            guard neededFiles.contains(filename) else { continue }

            // Always write with the lowercase canonical name so locate() finds it.
            let destURL = cachesDir.appendingPathComponent(filename)
            if FileManager.default.fileExists(atPath: destURL.path) {
                try? FileManager.default.removeItem(at: destURL)
            }
            _ = try archive.extract(entry, to: destURL)
        }

        return cachesDir
    }

    // MARK: - Parsing

    private func parse(from dir: URL) async {
        downloadProgress = 0.9

        let parsedRoutes = await Task.detached(priority: .userInitiated) {
            GTFSParser.parseRoutes(in: dir)
        }.value

        let parsedStops = await Task.detached(priority: .userInitiated) {
            GTFSParser.parseStops(in: dir)
        }.value

        routes = parsedRoutes
        stops  = parsedStops
        downloadProgress = 1.0
    }
}

// MARK: - Errors

enum GTFSError: LocalizedError {
    case downloadFailed
    case httpError(Int)
    case notAZipFile
    case missingFile(String)

    var errorDescription: String? {
        switch self {
        case .downloadFailed:
            return "The feed file could not be downloaded."
        case .httpError(let code):
            return "The agency server returned HTTP \(code). The feed URL may have changed — try a custom URL."
        case .notAZipFile:
            return "The URL did not return a GTFS ZIP file. The feed URL may have changed — try a custom URL."
        case .missingFile(let f):
            return "Required GTFS file not found in archive: \(f)"
        }
    }
}

// MARK: - CSV Parser

/// Pure-value CSV parser that handles quoted fields and CRLF/LF line endings.
enum GTFSParser {

    // MARK: Routes

    static func parseRoutes(in dir: URL) -> [GTFSRoute] {
        // Some feeds nest files inside a subdirectory — walk to find routes.txt
        guard let fileURL = locate("routes.txt", in: dir) else { return [] }
        guard let text = (try? String(contentsOf: fileURL, encoding: .utf8))
                       ?? (try? String(contentsOf: fileURL, encoding: .isoLatin1)) else { return [] }

        let rows  = parseCSV(text)
        guard let header = rows.first else { return [] }

        let idx = columnIndex(header)
        var result: [GTFSRoute] = []
        result.reserveCapacity(rows.count)

        for row in rows.dropFirst() {
            guard row.count > 1 else { continue }

            let routeID   = field(row, idx, "route_id")
            let shortName = field(row, idx, "route_short_name")
            let longName  = field(row, idx, "route_long_name")
            let typeStr   = field(row, idx, "route_type")
            let colorHex  = field(row, idx, "route_color")

            let routeType = GTFSRouteType(rawInt: Int(typeStr) ?? 99)

            result.append(GTFSRoute(
                id:        routeID,
                shortName: shortName,
                longName:  longName,
                type:      routeType,
                colorHex:  colorHex.isEmpty ? nil : colorHex
            ))
        }
        return result
    }

    // MARK: Stops

    static func parseStops(in dir: URL) -> [GTFSStop] {
        guard let fileURL = locate("stops.txt", in: dir) else { return [] }
        guard let text = (try? String(contentsOf: fileURL, encoding: .utf8))
                       ?? (try? String(contentsOf: fileURL, encoding: .isoLatin1)) else { return [] }

        let rows  = parseCSV(text)
        guard let header = rows.first else { return [] }

        let idx = columnIndex(header)
        var result: [GTFSStop] = []
        result.reserveCapacity(rows.count)

        for row in rows.dropFirst() {
            guard row.count > 1 else { continue }

            let stopID   = field(row, idx, "stop_id")
            let stopName = field(row, idx, "stop_name")
            let latStr   = field(row, idx, "stop_lat")
            let lonStr   = field(row, idx, "stop_lon")

            guard
                let lat = Double(latStr),
                let lon = Double(lonStr),
                lat != 0 || lon != 0
            else { continue }

            result.append(GTFSStop(
                id:        stopID,
                name:      stopName,
                latitude:  lat,
                longitude: lon
            ))
        }
        return result
    }

    // MARK: - Helpers

    /// Locate a filename inside a directory tree (handles one-level-deep nesting).
    private static func locate(_ filename: String, in dir: URL) -> URL? {
        let direct = dir.appendingPathComponent(filename)
        if FileManager.default.fileExists(atPath: direct.path) { return direct }

        // Check one level of subdirectory
        if let contents = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles
        ) {
            for item in contents {
                let isDir = (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                if isDir {
                    let nested = item.appendingPathComponent(filename)
                    if FileManager.default.fileExists(atPath: nested.path) { return nested }
                }
            }
        }
        return nil
    }

    private static func columnIndex(_ header: [String]) -> [String: Int] {
        // Build manually: skip empty keys, last-wins for duplicates.
        // Dictionary(uniqueKeysWithValues:) crashes if any key appears twice or is "".
        var dict: [String: Int] = [:]
        dict.reserveCapacity(header.count)
        for (i, col) in header.enumerated() {
            // Strip BOM (\u{FEFF}) that some agencies prepend to the first column
            let key = col
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\u{FEFF}"))
            guard !key.isEmpty else { continue }
            dict[key] = i
        }
        return dict
    }

    private static func field(_ row: [String], _ idx: [String: Int], _ key: String) -> String {
        guard let i = idx[key], i < row.count else { return "" }
        return row[i].trimmingCharacters(in: .whitespaces)
    }

    // MARK: - RFC 4180 CSV parser

    static func parseCSV(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row:  [String]   = []
        var field = ""
        var inQuotes = false

        var i = text.startIndex
        while i < text.endIndex {
            let c = text[i]

            if inQuotes {
                if c == "\"" {
                    let next = text.index(after: i)
                    if next < text.endIndex && text[next] == "\"" {
                        // Escaped quote
                        field.append("\"")
                        i = text.index(after: next)
                        continue
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(c)
                }
            } else {
                switch c {
                case "\"":
                    inQuotes = true
                case ",":
                    row.append(field)
                    field = ""
                case "\r":
                    row.append(field)
                    field = ""
                    rows.append(row)
                    row = []
                    // Skip following \n
                    let next = text.index(after: i)
                    if next < text.endIndex && text[next] == "\n" {
                        i = next
                    }
                case "\n":
                    row.append(field)
                    field = ""
                    rows.append(row)
                    row = []
                default:
                    field.append(c)
                }
            }
            i = text.index(after: i)
        }

        // Flush last field / row
        row.append(field)
        if row.contains(where: { !$0.isEmpty }) {
            rows.append(row)
        }

        return rows
    }
}
