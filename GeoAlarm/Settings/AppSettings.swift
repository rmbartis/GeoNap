// Copyright © 2026 Robert Bartis. All rights reserved.

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

    /// Slider range expressed in this unit (maps to 200 m … 5 000 m).
    /// Imperial lower bound is 655 ft (not the "round" 656 ft = 200 m × 3.28084)
    /// because it's the smallest integer ft value whose exact metre equivalent
    /// (199.644 m) still rounds up to a valid 200 m against
    /// `AlarmViewModel.isValid`/`buildAlarm()`'s `radius.rounded() >= 200`
    /// check — 654 ft (199.339 m) rounds down to 199 and would be invalid. So
    /// the slider's leftmost position is never a silently-disabled Save button
    /// (Bob, 2026-07-05; same pattern as the old 164 ft minimum this replaces).
    var sliderRange: ClosedRange<Double> {
        switch self {
        case .metric:   return 200...5000
        case .imperial: return 655...16404   // ≈ 200 ft … 16 404 ft
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

// MARK: - Calendar Scan Refresh Interval

/// User-configurable earliest-refresh interval for Automatic Calendar
/// Scanning background refreshes. Raw value is minutes, stored directly in
/// AppStorageKey.calendarScanRefreshIntervalMinutes.
///
/// This is the *earliest* the OS is allowed to run the next scan, not a
/// guarantee — BGTaskScheduler decides actual timing based on usage
/// patterns, battery, and Low Power Mode, and in practice a low-engagement
/// app may see real runs land far later than this value regardless of what's
/// picked here. The picker label pairs each option with a frequency/battery
/// hint rather than promising precision, and the Settings footer calls this
/// out explicitly (Bob, 2026-07-04).
enum CalendarScanRefreshInterval: Int, CaseIterable, Identifiable {
    case oneHour = 60
    case twoHours = 120
    case fourHours = 240
    case eightHours = 480

    var id: Int { rawValue }

    /// Matches the background task's previous hardcoded constant, so nobody's
    /// behavior changes until they explicitly open Settings and pick something else.
    static let `default`: CalendarScanRefreshInterval = .fourHours

    /// Resolves a raw stored minutes value to a valid case, falling back to
    /// `.default` for 0/missing/corrupt values (e.g. before this setting
    /// existed) rather than producing a zero or negative interval.
    static func resolve(storedMinutes: Int) -> CalendarScanRefreshInterval {
        CalendarScanRefreshInterval(rawValue: storedMinutes) ?? .default
    }

    var timeInterval: TimeInterval { TimeInterval(rawValue * 60) }

    /// Localization key for the picker label (time + frequency/battery hint).
    var localizationKey: String {
        switch self {
        case .oneHour:    return "calendarScan.refreshInterval.oneHour"
        case .twoHours:   return "calendarScan.refreshInterval.twoHours"
        case .fourHours:  return "calendarScan.refreshInterval.fourHours"
        case .eightHours: return "calendarScan.refreshInterval.eightHours"
        }
    }

    /// English fallback label (also the key registered in Localizable.strings).
    var englishLabel: String {
        switch self {
        case .oneHour:    return "1 Hour — Most Frequent"
        case .twoHours:   return "2 Hours — Frequent"
        case .fourHours:  return "4 Hours — Balanced"
        case .eightHours: return "8 Hours — Best Battery Life"
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
    /// JSON-encoded [CalendarTripCandidate] — trips found by the most recent
    /// scan (manual or background) that the user hasn't yet added or declined.
    /// Persisted so a background scan's results survive until the user next
    /// opens Settings → Calendar Scanning (Phase 3).
    static let calendarScanPendingCandidatesJSON = "calendarScanPendingCandidatesJSON"
    /// JSON-encoded [String: CalendarScanHandledRecord] keyed by candidate id —
    /// every candidate the user has already added or declined, plus the
    /// location snapshot it had at that time. On each scan, a candidate whose
    /// location snapshot no longer matches its handled record is treated as
    /// new again (Phase 3 re-offer-on-change behavior).
    static let calendarScanHandledCandidatesJSON = "calendarScanHandledCandidatesJSON"
    /// Date (encoded via UserDefaults' native Date support) of the
    /// `earliestBeginDate` most recently submitted to BGTaskScheduler for the
    /// background refresh request. Lets `scheduleNextRefresh()` tell whether a
    /// request is already pending without resetting its window every time it's
    /// called opportunistically (e.g. on every app foreground) — see
    /// CalendarScanRefreshScheduling.shouldSubmit (Bob, 2026-07-03).
    static let calendarScanNextRefreshEarliestDate = "calendarScanNextRefreshEarliestDate"
    /// CalendarScanRefreshInterval.rawValue (minutes) — the earliest-refresh
    /// interval for Automatic mode's background scans. Defaults to 240 (4h),
    /// matching the previous hardcoded constant. User-configurable via a
    /// picker in Settings → Calendar Scanning → Scan Behavior (Bob, 2026-07-04).
    static let calendarScanRefreshIntervalMinutes = "calendarScanRefreshIntervalMinutes"

    /// Registers UserDefaults defaults for the calendar-scan keys whose
    /// @AppStorage default isn't `false`/`0`/`""`. SwiftUI's @AppStorage
    /// returns its `= value` default when a key is absent, but never writes
    /// that default back to UserDefaults — so code that reads
    /// UserDefaults.standard directly (e.g. CalendarScanBackgroundTask,
    /// running outside any View) would otherwise see `false`/`0` for a
    /// never-touched key instead of the value the Settings UI actually shows.
    /// Call once at app launch, before anything reads these keys.
    static func registerCalendarScanDefaults() {
        UserDefaults.standard.register(defaults: [
            calendarScanNotifyOnResults: true,
            calendarScanLookaheadDays: 14,
            calendarScanModeRaw: CalendarScanMode.automatic.rawValue,
            calendarScanRefreshIntervalMinutes: CalendarScanRefreshInterval.default.rawValue,
        ])
    }

    // MARK: GTFS Transit Feed Cache
    // Caching itself is always on, silently, with a fixed 7-day retention —
    // no opt-in needed to get the basic behavior (Bob, 2026-07-07, correcting
    // the original 2026-07-06 spec which was misread as "off by default").
    // The Settings toggle below does NOT turn caching on/off; it only unlocks
    // a stepper for overriding that fixed 7-day window with a custom value.

    /// Fixed retention window (days) used whenever the user has not turned on
    /// custom retention. Also the value `gtfsCacheRetentionDays` registers as
    /// its UserDefaults default, so a fresh install behaves identically to
    /// "custom retention off" even before this key is ever touched.
    static let gtfsCacheDefaultRetentionDays = 7

    /// Sentinel for `gtfsCacheRetentionDays` meaning "never expire the cache
    /// automatically" — the stop past 30 days on the Settings stepper
    /// (Bob, 2026-07-07: "a final option being Infinite").
    static let gtfsCacheInfiniteRetention = 9999

    /// Whether the user has opted to override the fixed 7-day default
    /// retention with their own value via the Settings stepper. Defaults to
    /// false — caching still happens either way; this only controls whether
    /// the window is customizable (1–30 days, or "Infinite").
    static let gtfsCacheCustomRetentionEnabled = "gtfsCacheCustomRetentionEnabled"

    /// User-chosen retention window in days, used only when
    /// `gtfsCacheCustomRetentionEnabled` is true: 1–30, or
    /// `gtfsCacheInfiniteRetention` for "never expire". Ignored (fixed at
    /// `gtfsCacheDefaultRetentionDays`) when custom retention is off.
    static let gtfsCacheRetentionDays = "gtfsCacheRetentionDays"

    /// Registers the UserDefaults default for `gtfsCacheRetentionDays`
    /// (`gtfsCacheDefaultRetentionDays`, i.e. 7), so non-View code
    /// (`GTFSService`, which isn't a SwiftUI View and can't use
    /// `@AppStorage`) sees the same value the Settings stepper would show
    /// even before the user has ever touched it. Same rationale as
    /// `registerCalendarScanDefaults()` above — `@AppStorage`'s default is
    /// never written back to UserDefaults until first touched. Call once at
    /// app launch, before anything reads this key.
    static func registerGTFSCacheDefaults() {
        UserDefaults.standard.register(defaults: [
            gtfsCacheRetentionDays: gtfsCacheDefaultRetentionDays,
        ])
    }
}

// MARK: - Support Contact

/// Single source of truth for the support contact address. Every in-app use
/// (Settings → Debug Log → "Share Log with Support", and the Help screen's
/// "Support / Feedback / Suggestions" section, in all 13 languages) references
/// this constant rather than hardcoding the address — Help's Localizable.strings
/// entries hold a %@ placeholder that HelpView.swift fills in from here.
///
/// The one unavoidable exception is docs/privacy-policy.html, a static file
/// with no build step, which must be kept in sync by hand if this ever changes.
enum SupportContact {
    static let email = "geonapios@gmail.com"
}
