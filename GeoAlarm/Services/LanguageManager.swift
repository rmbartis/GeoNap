// LanguageManager.swift
// In-app language switching for iOS 26 / SwiftUI 6.
//
// Neither the object_setClass bundle-swizzle nor the AppleLanguages UserDefault
// trick works on iOS 26: NSBundle caches the language selection at first use and
// ignores runtime changes.  The only reliable solution is to pass the selected
// .lproj bundle EXPLICITLY to every Text() via the SwiftUI environment key
// \.languageBundle, then force a view-tree rebuild via .id(currentLanguage).
//
// Usage in views:
//   @Environment(\.languageBundle) private var bundle
//   Text("Settings", bundle: bundle)
//
// Or use the LText helper view which does this automatically:
//   LText("Settings")
//
// All 13 language bundles are compiled into the app — no downloads needed.
// Supported: English · Español · Français · Deutsch · Italiano · 日本語 · 中文
//            Tiếng Việt · ภาษาไทย · हिन्दी · العربية · Português · Русский

import Foundation
import Combine
import SwiftUI

// MARK: - AppLanguage

enum AppLanguage: String, CaseIterable, Identifiable {
    case english    = "en"
    case spanish    = "es"
    case french     = "fr"
    case german     = "de"
    case italian    = "it"
    case japanese   = "ja"
    case chinese    = "zh-Hans"
    case vietnamese = "vi"
    case thai       = "th"
    case hindi      = "hi"
    case arabic     = "ar"
    case portuguese = "pt"
    case russian    = "ru"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .english:    return "English"
        case .spanish:    return "Español"
        case .french:     return "Français"
        case .german:     return "Deutsch"
        case .italian:    return "Italiano"
        case .japanese:   return "日本語"
        case .chinese:    return "中文（简体）"
        case .vietnamese: return "Tiếng Việt"
        case .thai:       return "ภาษาไทย"
        case .hindi:      return "हिन्दी"
        case .arabic:     return "العربية"
        case .portuguese: return "Português"
        case .russian:    return "Русский"
        }
    }

    var flag: String {
        switch self {
        case .english:    return "🇺🇸"
        case .spanish:    return "🇪🇸"
        case .french:     return "🇫🇷"
        case .german:     return "🇩🇪"
        case .italian:    return "🇮🇹"
        case .japanese:   return "🇯🇵"
        case .chinese:    return "🇨🇳"
        case .vietnamese: return "🇻🇳"
        case .thai:       return "🇹🇭"
        case .hindi:      return "🇮🇳"
        case .arabic:     return "🇸🇦"
        case .portuguese: return "🇧🇷"
        case .russian:    return "🇷🇺"
        }
    }

    init?(code: String?) {
        guard let code, let lang = AppLanguage(rawValue: code) else { return nil }
        self = lang
    }

    /// The .lproj Bundle for this language, or nil if not found in the app bundle.
    var bundle: Bundle {
        let root = Bundle.main.bundlePath as NSString
        let candidates = [rawValue, String(rawValue.prefix(2))]
        for code in candidates {
            let path = root.appendingPathComponent("\(code).lproj")
            if let b = Bundle(path: path) { return b }
        }
        return Bundle.main          // fallback: English keys act as their own values
    }
}

// MARK: - Environment key

private struct LanguageBundleKey: EnvironmentKey {
    static let defaultValue: Bundle = AppLanguage.english.bundle
}

extension EnvironmentValues {
    /// The bundle to pass to Text("key", bundle: bundle) for the current
    /// in-app language.  Injected at the root view in GeoAlarmApp.
    var languageBundle: Bundle {
        get { self[LanguageBundleKey.self] }
        set { self[LanguageBundleKey.self] = newValue }
    }
}

// MARK: - LText helper

/// Drop-in replacement for Text("key") that automatically uses the
/// in-app language bundle injected via \.languageBundle.
/// Use this wherever a localised string is needed:
///   LText("Save Alarm")
struct LText: View {
    let key: LocalizedStringKey
    @Environment(\.languageBundle) private var bundle

    init(_ key: LocalizedStringKey) { self.key = key }

    var body: some View {
        Text(key, bundle: bundle)
    }
}

// MARK: - LanguageManager

@MainActor
final class LanguageManager: ObservableObject {

    static let shared = LanguageManager()

    @Published private(set) var currentLanguage: AppLanguage

    private init() {
        let saved   = UserDefaults.standard.string(forKey: AppStorageKey.appLanguage)
        let sysCode = Locale.current.language.languageCode?.identifier ?? "en"
        currentLanguage = AppLanguage(code: saved)
            ?? AppLanguage(code: sysCode)
            ?? .english
    }

    func setLanguage(_ language: AppLanguage) {
        guard language != currentLanguage else { return }
        currentLanguage = language
        UserDefaults.standard.set(language.rawValue, forKey: AppStorageKey.appLanguage)
        DebugLogger.shared.log("Language → \(language.rawValue)", category: "Language")
    }

    /// The Bundle to inject into the SwiftUI environment.
    var currentBundle: Bundle { currentLanguage.bundle }
}
