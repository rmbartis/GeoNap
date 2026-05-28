// AppSettings.swift
// Shared enums and AppStorage key constants for user preferences.

import Foundation

// MARK: - Distance Unit

enum DistanceUnit: String, CaseIterable, Identifiable {
    case metric   = "metric"
    case imperial = "imperial"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .metric:   return "Metric (m / km)"
        case .imperial: return "Imperial (ft / mi)"
        }
    }

    /// Short unit label for small distances (radius display).
    var shortLabel: String {
        switch self {
        case .metric:   return "m"
        case .imperial: return "ft"
        }
    }

    // MARK: Conversion

    /// Convert a value stored in metres to this unit.
    func fromMeters(_ meters: Double) -> Double {
        switch self {
        case .metric:   return meters
        case .imperial: return meters * 3.28084
        }
    }

    /// Convert a value in this unit back to metres for storage.
    func toMeters(_ value: Double) -> Double {
        switch self {
        case .metric:   return value
        case .imperial: return value / 3.28084
        }
    }

    /// Slider range expressed in this unit (maps to 50 m … 2 000 m).
    var sliderRange: ClosedRange<Double> {
        switch self {
        case .metric:   return 50...2000
        case .imperial: return 164...6562   // ≈ 50 ft … 6 562 ft
        }
    }

    /// Slider step in this unit (maps to 50 m steps).
    var sliderStep: Double {
        switch self {
        case .metric:   return 50
        case .imperial: return 164
        }
    }

    /// Human-readable formatted string for a radius value in metres.
    func formatted(meters: Double) -> String {
        let converted = fromMeters(meters)
        return "\(Int(converted.rounded())) \(shortLabel)"
    }
}

// MARK: - Time Format

enum TimeFormat: String, CaseIterable, Identifiable {
    case twelveHour     = "12h"
    case twentyFourHour = "24h"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .twelveHour:     return "12-hour (AM/PM)"
        case .twentyFourHour: return "24-hour"
        }
    }

    /// Format a Date to a time string in this format.
    func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = self == .twelveHour ? "h:mm a" : "HH:mm"
        return formatter.string(from: date)
    }

    /// Locale to inject into a DatePicker so it respects the chosen clock format.
    /// DatePicker uses locale — not dateFormat — to decide 12h vs 24h display.
    /// en_GB is a reliable 24-hour locale; .current preserves the user's system locale for 12h.
    var pickerLocale: Locale {
        switch self {
        case .twelveHour:     return .current
        case .twentyFourHour: return Locale(identifier: "en_GB")
        }
    }
}

// MARK: - AppStorage Keys

enum AppStorageKey {
    static let distanceUnit   = "distanceUnit"
    static let timeFormat     = "timeFormat"
    /// Whether the user has opted into debug logging.
    /// Defaults to false — logging is completely silent until the user enables it.
    static let debugLogging   = DebugLogger.UserDefaultsKey.debugLoggingEnabled
    /// BCP-47 language code chosen by the user (e.g. "en", "es", "zh-Hans").
    /// Defaults to the system language if supported, otherwise English.
    static let appLanguage    = "appLanguage"
}
