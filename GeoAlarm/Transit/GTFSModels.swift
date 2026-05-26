// GTFSModels.swift
// Lightweight value types for parsed GTFS data.
// Only the fields GeoAlarm needs — routes and stops.

import SwiftUI
import CoreLocation

// MARK: - Route type

/// GTFS route_type values (spec section 3.3)
enum GTFSRouteType: Int {
    case tram       = 0
    case subway     = 1
    case rail       = 2
    case bus        = 3
    case ferry      = 4
    case cableTram  = 5
    case aerial     = 6
    case funicular  = 7
    case unknown    = 99

    init(rawInt: Int) {
        self = GTFSRouteType(rawValue: rawInt) ?? .unknown
    }

    var systemImage: String {
        switch self {
        case .tram:      return "tram.fill"
        case .subway:    return "tram.fill"
        case .rail:      return "train.side.front.car"
        case .bus:       return "bus.fill"
        case .ferry:     return "ferry.fill"
        case .cableTram: return "cablecar"
        case .aerial:    return "mountain.2.fill"
        case .funicular: return "mountain.2.fill"
        case .unknown:   return "location.fill"
        }
    }

    var label: String {
        switch self {
        case .tram:      return "Tram"
        case .subway:    return "Subway"
        case .rail:      return "Rail"
        case .bus:       return "Bus"
        case .ferry:     return "Ferry"
        case .cableTram: return "Cable Tram"
        case .aerial:    return "Aerial"
        case .funicular: return "Funicular"
        case .unknown:   return "Transit"
        }
    }
}

// MARK: - Route

struct GTFSRoute: Identifiable, Hashable {
    let id: String          // route_id
    let shortName: String   // route_short_name  (e.g. "7")
    let longName: String    // route_long_name   (e.g. "Flushing Local")
    let type: GTFSRouteType
    let colorHex: String?   // route_color (optional)

    /// Display name — prefers short name, falls back to long name.
    var displayName: String {
        shortName.isEmpty ? longName : shortName
    }

    /// Full label combining both names when both are present.
    var fullLabel: String {
        if shortName.isEmpty { return longName }
        if longName.isEmpty  { return shortName }
        return "\(shortName) · \(longName)"
    }

    var routeColor: Color {
        guard let hex = colorHex, !hex.isEmpty else { return .accentColor }
        return Color(hex: hex) ?? .accentColor
    }
}

// MARK: - Stop

struct GTFSStop: Identifiable, Hashable {
    let id: String          // stop_id
    let name: String        // stop_name
    let latitude: Double    // stop_lat
    let longitude: Double   // stop_lon

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    func distance(from location: CLLocation) -> CLLocationDistance {
        CLLocation(latitude: latitude, longitude: longitude).distance(from: location)
    }
}

// MARK: - Color hex helper

private extension Color {
    init?(hex: String) {
        let h = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard h.count == 6, let value = UInt64(h, radix: 16) else { return nil }
        self.init(
            red:   Double((value >> 16) & 0xFF) / 255,
            green: Double((value >>  8) & 0xFF) / 255,
            blue:  Double( value        & 0xFF) / 255
        )
    }
}
