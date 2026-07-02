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

// MARK: - Coordinate Format

enum CoordFormat: String, CaseIterable, Identifiable {
    case dd  = "dd"   // Decimal Degrees:          40.712800, -74.006000
    case dms = "dms"  // Degrees Minutes Seconds:  40°42′46″N  74°00′21″W
    case ddm = "ddm"  // Degrees Decimal Minutes:  40°42.767′N  74°00.360′W

    var id: String { rawValue }

    var label: String {
        switch self {
        case .dd:  return "DD"
        case .dms: return "DMS"
        case .ddm: return "DDM"
        }
    }

    var fullLabel: String {
        switch self {
        case .dd:  return "Decimal Degrees (DD)"
        case .dms: return "Deg Min Sec (DMS)"
        case .ddm: return "Deg Decimal Min (DDM)"
        }
    }

    var latPlaceholder: String {
        switch self {
        case .dd:  return "e.g. 40.712800"
        case .dms: return "e.g. 40°42′46″N"
        case .ddm: return "e.g. 40°42.767′N"
        }
    }

    var lonPlaceholder: String {
        switch self {
        case .dd:  return "e.g. -74.006000"
        case .dms: return "e.g. 74°00′21″W"
        case .ddm: return "e.g. 74°00.360′W"
        }
    }
}

// MARK: - Calendar Scan Mode

/// Whether calendar scanning runs automatically in the background or only
/// when the user explicitly taps "Scan Now" in Settings.
enum CalendarScanMode: String, CaseIterable, Identifiable {
    case automatic
    case manualOnly

    var id: String { rawValue }

    /// Localization key for the picker label.
    var localizationKey: String {
        switch self {
        case .automatic:  return "calendarScan.mode.automatic"
        case .manualOnly: return "calendarScan.mode.manualOnly"
        }
    }

    /// English fallback label (also the key registered in Localizable.strings).
    var englishLabel: String {
        switch self {
        case .automatic:  return "Automatic"
        case .manualOnly: return "Manual Only"
        }
    }
}

// MARK: - AppStorage Keys

enum AppStorageKey {
    static let distanceUnit   = "distanceUnit"
    static let timeFormat     = "timeFormat"
    static let coordFormat    = "coordFormat"
    /// Whether the user has opted into debug logging.
    /// Defaults to false — logging is completely silent until the user enables it.
    static let debugLogging   = DebugLogger.UserDefaultsKey.debugLoggingEnabled
    /// BCP-47 language code chosen by the user (e.g. "en", "es", "zh-Hans").
    /// Defaults to the system language if supported, otherwise English.
    static let appLanguage    = "appLanguage"
    /// JSON-encoded [NotifyContact] default list for the Auto-Notify feature.
    /// Pre-filled into per-alarm contact lists when Auto-Notify is first enabled.
    static let defaultNotifyContacts = "defaultNotifyContacts"
    /// User has set up the Shortcuts "When GeoNap Is Opened" automation that sends
    /// Auto-Notify SMS hands-free. When true, the app suppresses its own pre-filled
    /// Messages compose sheet so the two paths don't both fire (the automation
    /// sends silently the next time the app is opened after an alarm).
    static let autoSMSAutomationEnabled = "autoSMSAutomationEnabled"
    /// Default trigger input mode for the alarm-creation screen: "distance" (radius)
    /// or "time" (minutes before arrival). Stored as TriggerMode.rawValue.
    static let defaultTriggerMode = "defaultTriggerMode"

    // MARK: Calendar Scanning
    // All calendar-scan keys default to "off"/empty — scanning is strictly
    // opt-in. calendarScanEnabled MUST default to false.

    /// Master switch for the Calendar Scanning feature. Defaults to false —
    /// the user must explicitly turn this on.
    static let calendarScanEnabled = "calendarScanEnabled"
    /// CalendarScanMode.rawValue — "automatic" or "manualOnly".
    static let calendarScanModeRaw = "calendarScanModeRaw"
    /// Whether a local notification is sent when a background scan finds new
    /// trip candidates. Independent of calendarScanModeRaw.
    static let calendarScanNotifyOnResults = "calendarScanNotifyOnResults"
    /// How many days ahead the scan looks for events. Defaults to 14.
    static let calendarScanLookaheadDays = "calendarScanLookaheadDays"
    /// JSON-encoded Set<String> of EKCalendar.calendarIdentifier values the
    /// user has opted in to scanning.
    static let calendarScanEnabledCalendarIDs = "calendarScanEnabledCalendarIDs"
    /// Whether the first-run "select calendars" sheet has been completed.
    static let calendarScanHasCompletedFirstRun = "calendarScanHasCompletedFirstRun"
}
