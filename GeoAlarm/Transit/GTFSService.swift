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
            DebugLogger.shared.log("GTFS cache hit for '\(feed.name)' — loading from \(dir.lastPathComponent)", category: "GTFS")
            await parse(from: dir)
        } else {
            await downloadAndParse(feed: feed)
        }
    }

    /// Force a fresh download even if data is already cached.
    func refresh(feed: GTFSFeedModel) async {
        errorMessage = nil
        DebugLogger.shared.log("GTFS force-refresh requested for '\(feed.name)'", category: "GTFS")
        await downloadAndParse(feed: feed)
    }

    /// Cancel any in-flight download.
    func cancel() {
        DebugLogger.shared.log("GTFS download cancelled by user", category: "GTFS")
        downloadTask?.cancel()
        downloadTask = nil
        isLoading = false
        downloadProgress = 0
    }

    // MARK: - Download

    private func downloadAndParse(feed: GTFSFeedModel) async {
        guard let url = URL(string: feed.feedURL) else {
            errorMessage = "\(feed.name): Invalid feed URL."
            DebugLogger.shared.log("GTFS download FAILED: '\(feed.name)' — malformed URL: \(feed.feedURL)", category: "GTFS")
            return
        }

        DebugLogger.shared.log("GTFS download START: '\(feed.name)' url=\(feed.feedURL)", category: "GTFS")
        isLoading = true
        downloadProgress = 0
        defer { isLoading = false }

        do {
            let zipURL = try await download(from: url)

            // Log the size of the downloaded ZIP
            let zipBytes = (try? FileManager.default.attributesOfItem(atPath: zipURL.path)[.size] as? Int64) ?? 0
            DebugLogger.shared.log("GTFS download COMPLETE: '\(feed.name)' size=\(ByteCountFormatter.string(fromByteCount: zipBytes, countStyle: .file))", category: "GTFS")

            let extractDir = try extract(zipURL: zipURL, feedID: feed.id.uuidString)

            feed.cachedDirectoryName = extractDir.lastPathComponent
            feed.lastDownloaded = Date()

            await parse(from: extractDir)

            try? FileManager.default.removeItem(at: zipURL)
        } catch is CancellationError {
            // User cancelled — already logged in cancel()
        } catch {
            errorMessage = "\(feed.name): \(error.localizedDescription)"
            DebugLogger.shared.log("GTFS download/parse FAILED: '\(feed.name)' error='\(error.localizedDescription)' url=\(feed.feedURL)", category: "GTFS")
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
                if let http = response as? HTTPURLResponse,
                   !(200...299).contains(http.statusCode) {
                    continuation.resume(throwing: GTFSError.httpError(http.statusCode))
                    return
                }
                guard let location else {
                    continuation.resume(throwing: GTFSError.downloadFailed)
                    return
                }
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

            let observation = task.progress.observe(\.fractionCompleted) { [weak self] progress, _ in
                Task { @MainActor [weak self] in
                    self?.downloadProgress = progress.fractionCompleted * 0.9
                }
            }

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

        if FileManager.default.fileExists(atPath: cachesDir.path) {
            try FileManager.default.removeItem(at: cachesDir)
        }
        try FileManager.default.createDirectory(at: cachesDir, withIntermediateDirectories: true)

        let archive: Archive
        do {
            archive = try Archive(url: zipURL, accessMode: .read)
        } catch {
            throw GTFSError.downloadFailed
        }

        let neededFiles: Set<String> = ["routes.txt", "stops.txt", "trips.txt",
                                        "stop_times.txt", "calendar.txt"]

        print("[GTFS] Archive entries:")
        for entry in archive {
            let rawPath = entry.path
            print("[GTFS]   \(entry.type == .directory ? "DIR " : "FILE") \(rawPath)")

            if rawPath.hasPrefix("__MACOSX") { continue }
            if entry.type == .directory { continue }

            let filename = (rawPath as NSString).lastPathComponent.lowercased()

            if filename.hasPrefix(".") { continue }
            guard neededFiles.contains(filename) else { continue }

            let destURL = cachesDir.appendingPathComponent(filename)
            if FileManager.default.fileExists(atPath: destURL.path) {
                try? FileManager.default.removeItem(at: destURL)
            }
            _ = try archive.extract(entry, to: destURL)
            print("[GTFS]   → extracted \(filename)")
        }

        let extracted = (try? FileManager.default.contentsOfDirectory(atPath: cachesDir.path)) ?? []
        print("[GTFS] Cache dir contains: \(extracted)")
        return cachesDir
    }

    // MARK: - Parsing

    private func parse(from dir: URL) async {
        downloadProgress = 0.9
        DebugLogger.shared.log("GTFS parse START from directory: \(dir.lastPathComponent)", category: "GTFS")
        let parseStart = Date()

        // Run parsing off the main actor using nonisolated async wrappers to avoid
        // capturing @MainActor-isolated context in Task.detached closures.
        let parsedRoutes = await GTFSParser.parseRoutesAsync(in: dir)
        let parsedStops  = await GTFSParser.parseStopsAsync(in: dir)

        let elapsed = String(format: "%.2f", Date().timeIntervalSince(parseStart))
        DebugLogger.shared.log("GTFS parse COMPLETE: routes=\(parsedRoutes.count) stops=\(parsedStops.count) elapsed=\(elapsed)s", category: "GTFS")

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

    // MARK: - Async wrappers (nonisolated — safe to call from @MainActor without Task.detached)

    nonisolated static func parseRoutesAsync(in dir: URL) async -> [GTFSRoute] {
        parseRoutes(in: dir)
    }

    nonisolated static func parseStopsAsync(in dir: URL) async -> [GTFSStop] {
        parseStops(in: dir)
    }

    // MARK: Routes

    nonisolated static func parseRoutes(in dir: URL) -> [GTFSRoute] {
        guard let fileURL = locate("routes.txt", in: dir) else { return [] }
        guard let text = (try? String(contentsOf: fileURL, encoding: .utf8))
                       ?? (try? String(contentsOf: fileURL, encoding: .isoLatin1)) else { return [] }

        var result: [GTFSRoute] = []
        var idx: [String: Int] = [:]
        var isHeader = true

        text.enumerateLines { line, _ in
            guard !line.isEmpty else { return }
            let row = parseSingleRow(line)
            guard !row.isEmpty else { return }

            if isHeader {
                idx = columnIndex(row)
                isHeader = false
                return
            }

            guard row.count > 1 else { return }

            let routeID   = field(row, idx, "route_id")
            let shortName = field(row, idx, "route_short_name")
            let longName  = field(row, idx, "route_long_name")
            let typeStr   = field(row, idx, "route_type")
            let colorHex  = field(row, idx, "route_color")

            result.append(GTFSRoute(
                id:        routeID,
                shortName: shortName,
                longName:  longName,
                type:      GTFSRouteType(rawInt: Int(typeStr) ?? 99),
                colorHex:  colorHex.isEmpty ? nil : colorHex
            ))
        }
        return result
    }

    // MARK: Stops

    nonisolated static func parseStops(in dir: URL) -> [GTFSStop] {
        guard let fileURL = locate("stops.txt", in: dir) else { return [] }
        guard let text = (try? String(contentsOf: fileURL, encoding: .utf8))
                       ?? (try? String(contentsOf: fileURL, encoding: .isoLatin1)) else { return [] }

        var result: [GTFSStop] = []
        var idx: [String: Int] = [:]
        var isHeader = true

        text.enumerateLines { line, _ in
            guard !line.isEmpty else { return }

            let row = parseSingleRow(line)
            guard !row.isEmpty else { return }

            if isHeader {
                idx = columnIndex(row)
                isHeader = false
                return
            }

            guard row.count > 1 else { return }

            let stopID   = field(row, idx, "stop_id")
            let stopName = field(row, idx, "stop_name")
            let latStr   = field(row, idx, "stop_lat")
            let lonStr   = field(row, idx, "stop_lon")

            guard
                let lat = Double(latStr.trimmingCharacters(in: .whitespaces)),
                let lon = Double(lonStr.trimmingCharacters(in: .whitespaces)),
                lat.isFinite, lon.isFinite,
                (lat != 0 || lon != 0),
                lat >= -90,  lat <= 90,
                lon >= -180, lon <= 180
            else { return }

            result.append(GTFSStop(
                id:        stopID,
                name:      stopName,
                latitude:  lat,
                longitude: lon
            ))
        }
        return result
    }

    // MARK: - Single-row CSV parser

    nonisolated private static func parseSingleRow(_ line: String) -> [String] {
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var i = line.startIndex

        while i < line.endIndex {
            let c = line[i]
            if inQuotes {
                if c == "\"" {
                    let next = line.index(after: i)
                    if next < line.endIndex && line[next] == "\"" {
                        field.append("\"")
                        i = line.index(after: next)
                        continue
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(c)
                }
            } else {
                switch c {
                case "\"": inQuotes = true
                case ",":  row.append(field); field = ""
                case "\r": break
                default:   field.append(c)
                }
            }
            i = line.index(after: i)
        }
        row.append(field)
        return row
    }

    // MARK: - Helpers

    nonisolated private static func locate(_ filename: String, in dir: URL) -> URL? {
        let direct = dir.appendingPathComponent(filename)
        if FileManager.default.fileExists(atPath: direct.path) { return direct }

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

    nonisolated private static func columnIndex(_ header: [String]) -> [String: Int] {
        var dict: [String: Int] = [:]
        dict.reserveCapacity(header.count)
        for (i, col) in header.enumerated() {
            let key = col
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\u{FEFF}"))
            guard !key.isEmpty else { continue }
            dict[key] = i
        }
        return dict
    }

    nonisolated private static func field(_ row: [String], _ idx: [String: Int], _ key: String) -> String {
        guard let i = idx[key], i < row.count else { return "" }
        return row[i].trimmingCharacters(in: .whitespaces)
    }

    // MARK: - RFC 4180 CSV parser (kept for reference)

    nonisolated static func parseCSV(_ text: String) -> [[String]] {
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

        row.append(field)
        if row.contains(where: { !$0.isEmpty }) {
            rows.append(row)
        }

        return rows
    }
}
