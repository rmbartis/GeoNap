// CoordinateParser.swift
// Parses, validates, and formats geographic coordinates in three formats:
//   DD  — Decimal Degrees:         40.712800  /  -74.006000
//   DMS — Degrees Minutes Seconds: 40°42′46″N / 74°00′21″W
//   DDM — Degrees Decimal Minutes: 40°42.767′N / 74°00.360′W
//
// All parsers accept flexible separators (°, ′, ″, ', ", spaces, dashes).
// Hemisphere letters (N/S/E/W) are accepted at either end of the string.

import Foundation
import CoreLocation

// MARK: - Error type

enum CoordinateParseError: LocalizedError {
    case empty
    case invalidFormat(String)
    case latitudeOutOfRange(Double)
    case longitudeOutOfRange(Double)
    case wrongHemisphere(String)
    case minutesOutOfRange
    case secondsOutOfRange

    var errorDescription: String? {
        switch self {
        case .empty:
            return "Please enter both latitude and longitude."
        case .invalidFormat(let hint):
            return "Invalid format — \(hint)"
        case .latitudeOutOfRange(let v):
            return String(format: "Latitude %.6f is out of range (−90 to +90).", v)
        case .longitudeOutOfRange(let v):
            return String(format: "Longitude %.6f is out of range (−180 to +180).", v)
        case .wrongHemisphere(let h):
            return "'\(h)' is not a valid hemisphere letter for this field. Use N/S for latitude, E/W for longitude."
        case .minutesOutOfRange:
            return "Minutes must be between 0 and 59."
        case .secondsOutOfRange:
            return "Seconds must be between 0 and 59.999."
        }
    }
}

// MARK: - Parser

enum CoordinateParser {

    // MARK: Public API

    /// Parse a latitude/longitude string pair and return a validated coordinate.
    /// Throws `CoordinateParseError` if either string is invalid or out of range.
    static func parse(
        latString: String,
        lonString: String,
        format: CoordFormat
    ) throws -> CLLocationCoordinate2D {
        let lat: Double
        let lon: Double
        switch format {
        case .dd:
            lat = try parseDD(latString, isLatitude: true)
            lon = try parseDD(lonString, isLatitude: false)
        case .dms:
            lat = try parseDMS(latString, isLatitude: true)
            lon = try parseDMS(lonString, isLatitude: false)
        case .ddm:
            lat = try parseDDM(latString, isLatitude: true)
            lon = try parseDDM(lonString, isLatitude: false)
        }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    // MARK: Format for display

    static func format(latitude: Double, format: CoordFormat) -> String {
        formatValue(latitude, isLatitude: true, format: format)
    }

    static func format(longitude: Double, format: CoordFormat) -> String {
        formatValue(longitude, isLatitude: false, format: format)
    }

    // MARK: - DD

    private static func parseDD(_ raw: String, isLatitude: Bool) throws -> Double {
        var s = raw.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { throw CoordinateParseError.empty }

        var sign = 1.0

        // Hemisphere at start or end
        let first = String(s.prefix(1)).uppercased()
        let last  = String(s.suffix(1)).uppercased()
        let latHem = Set(["N", "S"]); let lonHem = Set(["E", "W"])
        let allHem = latHem.union(lonHem)

        if allHem.contains(last) {
            if isLatitude && lonHem.contains(last) { throw CoordinateParseError.wrongHemisphere(last) }
            if !isLatitude && latHem.contains(last) { throw CoordinateParseError.wrongHemisphere(last) }
            if last == "S" || last == "W" { sign = -1.0 }
            s = String(s.dropLast()).trimmingCharacters(in: .whitespaces)
        } else if allHem.contains(first) {
            if isLatitude && lonHem.contains(first) { throw CoordinateParseError.wrongHemisphere(first) }
            if !isLatitude && latHem.contains(first) { throw CoordinateParseError.wrongHemisphere(first) }
            if first == "S" || first == "W" { sign = -1.0 }
            s = String(s.dropFirst()).trimmingCharacters(in: .whitespaces)
        }

        // Strip degree symbol
        s = s.replacingOccurrences(of: "°", with: "").trimmingCharacters(in: .whitespaces)

        guard let value = Double(s) else {
            let hint = isLatitude ? "Expected e.g. 40.712800 or 40.712800N"
                                  : "Expected e.g. -74.006000 or 74.006000W"
            throw CoordinateParseError.invalidFormat(hint)
        }

        let result = value * sign
        if isLatitude  { guard abs(result) <= 90  else { throw CoordinateParseError.latitudeOutOfRange(result)  } }
        if !isLatitude { guard abs(result) <= 180 else { throw CoordinateParseError.longitudeOutOfRange(result) } }
        return result
    }

    // MARK: - DMS

    private static func parseDMS(_ raw: String, isLatitude: Bool) throws -> Double {
        let (deg, min, sec, sign) = try tokenize(raw, isLatitude: isLatitude, decimalMinutes: false)
        guard min >= 0 && min < 60  else { throw CoordinateParseError.minutesOutOfRange }
        guard sec >= 0 && sec < 60  else { throw CoordinateParseError.secondsOutOfRange }
        let result = (deg + min / 60.0 + sec / 3600.0) * sign
        if isLatitude  { guard abs(result) <= 90  else { throw CoordinateParseError.latitudeOutOfRange(result)  } }
        if !isLatitude { guard abs(result) <= 180 else { throw CoordinateParseError.longitudeOutOfRange(result) } }
        return result
    }

    // MARK: - DDM

    private static func parseDDM(_ raw: String, isLatitude: Bool) throws -> Double {
        let (deg, min, _, sign) = try tokenize(raw, isLatitude: isLatitude, decimalMinutes: true)
        guard min >= 0 && min < 60  else { throw CoordinateParseError.minutesOutOfRange }
        let result = (deg + min / 60.0) * sign
        if isLatitude  { guard abs(result) <= 90  else { throw CoordinateParseError.latitudeOutOfRange(result)  } }
        if !isLatitude { guard abs(result) <= 180 else { throw CoordinateParseError.longitudeOutOfRange(result) } }
        return result
    }

    // MARK: - Shared tokenizer

    /// Returns (degrees, minutes, seconds, sign).
    /// When decimalMinutes is true, minutes may be fractional and seconds is always 0.
    private static func tokenize(
        _ raw: String,
        isLatitude: Bool,
        decimalMinutes: Bool
    ) throws -> (Double, Double, Double, Double) {

        var s = raw.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { throw CoordinateParseError.empty }

        var sign = 1.0
        let latHem = Set(["N", "S"]); let lonHem = Set(["E", "W"])
        let allHem = latHem.union(lonHem)

        // Hemisphere prefix or suffix
        let first = String(s.prefix(1)).uppercased()
        let last  = String(s.suffix(1)).uppercased()

        if allHem.contains(last) {
            if isLatitude  && lonHem.contains(last)  { throw CoordinateParseError.wrongHemisphere(last) }
            if !isLatitude && latHem.contains(last)  { throw CoordinateParseError.wrongHemisphere(last) }
            if last == "S" || last == "W" { sign = -1.0 }
            s = String(s.dropLast()).trimmingCharacters(in: .whitespaces)
        } else if allHem.contains(first) {
            if isLatitude  && lonHem.contains(first)  { throw CoordinateParseError.wrongHemisphere(first) }
            if !isLatitude && latHem.contains(first)  { throw CoordinateParseError.wrongHemisphere(first) }
            if first == "S" || first == "W" { sign = -1.0 }
            s = String(s.dropFirst()).trimmingCharacters(in: .whitespaces)
        } else if s.hasPrefix("-") {
            sign = -1.0
            s = String(s.dropFirst())
        }

        // Normalise separators → spaces
        for ch in ["°", "′", "″", "'", "\"", "-"] {
            s = s.replacingOccurrences(of: ch, with: " ")
        }
        let tokens = s.components(separatedBy: .whitespaces).filter { !$0.isEmpty }

        let latHint = decimalMinutes ? "e.g. 40 42.767 N"  : "e.g. 40 42 46 N"
        let lonHint = decimalMinutes ? "e.g. 74 00.360 W"  : "e.g. 74 00 21 W"
        let hint    = isLatitude ? latHint : lonHint

        guard tokens.count >= 2,
              let deg = Double(tokens[0]),
              let min = Double(tokens[1])
        else { throw CoordinateParseError.invalidFormat(hint) }

        var sec = 0.0
        if !decimalMinutes && tokens.count >= 3 {
            sec = Double(tokens[2]) ?? 0.0
        }

        return (deg, min, sec, sign)
    }

    // MARK: - Formatting

    private static func formatValue(_ degrees: Double, isLatitude: Bool, format: CoordFormat) -> String {
        let abs = Swift.abs(degrees)
        let hemi: String
        if isLatitude  { hemi = degrees >= 0 ? "N" : "S" }
        else           { hemi = degrees >= 0 ? "E" : "W" }

        switch format {
        case .dd:
            return String(format: "%.6f", degrees)

        case .dms:
            let d = Int(abs)
            let m = Int((abs - Double(d)) * 60)
            let s = (abs - Double(d) - Double(m) / 60.0) * 3600.0
            return String(format: "%d°%02d′%05.2f″%@", d, m, s, hemi)

        case .ddm:
            let d = Int(abs)
            let m = (abs - Double(d)) * 60.0
            return String(format: "%d°%08.5f′%@", d, m, hemi)
        }
    }
}
