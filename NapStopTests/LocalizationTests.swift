// LocalizationTests.swift
// CI tests that verify every Localizable.strings file:
//   1. Contains the two help keys that were recently updated.
//   2. Uses proper native Unicode — not ASCII romanizations from a failed
//      translation pass (e.g. "Ohne Bestatigung" instead of "Ohne Bestätigung").
//   3. Uses correct .strings escape sequences (\\n, not bare newlines inside values).

import XCTest

final class LocalizationTests: XCTestCase {

    // MARK: - Language table

    /// Maps each supported language code to tokens that MUST appear in the
    /// updated help keys — written in the language's own script.
    private let expectedTokens: [String: (autoNotify: String, siri: String)] = [
        "en":      ("without approval",              "Notify my contacts"),
        "de":      ("Bestätigung",                   "Kurzbefehle"),
        "es":      ("aprobación",                    "Automatización"),
        "fr":      ("approbation",                   "Raccourcis"),
        "it":      ("approvazione",                  "Automazione"),
        "pt":      ("aprovação",                     "Automação"),
        "ru":      ("Отправка без",                  "автоматизации"),
        "ar":      ("إرسال بدون",                    "الاختصارات"),
        "hi":      ("अनुमोदन",                       "ऑटोमेशन"),
        "ja":      ("承認なし",                        "ショートカット"),
        "th":      ("ไม่ต้องอนุมัติ",                 "อัตโนมัติ"),
        "vi":      ("phê duyệt",                     "Tự động hóa"),
        "zh-Hans": ("无需批准",                        "自动短信"),
    ]

    /// Romanized placeholder strings that indicate a failed/incomplete
    /// translation — none of these should appear in any file.
    private let forbiddenTokens: [String] = [
        "Ohne Bestatigung",       // de — missing umlaut
        "Enviar sin aprobacion",  // es — missing accent
        "Enviar sem aprovacao",   // pt — missing cedilla/accent
        "Otpravka bez",           // ru — romanized
        "Irsal bdon",             // ar — romanized
        "Bina anumodan",          // hi — romanized
        "Shonin nashi",           // ja — romanized
        "Song doi mai",           // th — romanized
        "Wu xu pi",               // zh — romanized
        "Tong guo GeoNap",        // zh — romanized
        "Tang kha kha",           // th — romanized
    ]

    // MARK: - Helpers

    /// Locates Localizable.strings for a given language code by navigating
    /// relative to this source file. Works without any bundle configuration:
    ///   NapStopTests/LocalizationTests.swift
    ///   → ../GeoAlarm/{lang}.lproj/Localizable.strings
    private func stringsURL(for languageCode: String,
                            sourceFile: StaticString = #file) throws -> URL {
        let thisFile = URL(fileURLWithPath: "\(sourceFile)")
        let projectRoot = thisFile
            .deletingLastPathComponent()   // NapStopTests/
            .deletingLastPathComponent()   // GeoAlarm/ (project root)
        let url = projectRoot
            .appendingPathComponent("GeoAlarm")
            .appendingPathComponent("\(languageCode).lproj")
            .appendingPathComponent("Localizable.strings")

        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("Localizable.strings not found for '\(languageCode)': \(url.path)")
        }
        return url
    }

    /// Extracts the raw string value for a given key from .strings content.
    /// Returns nil if the key is absent.
    /// Extracts the raw value for a .strings key using a simple linear scan —
    /// no regex, no backtracking risk on long strings.
    /// Handles both single-line and multi-line values, and \" escapes inside values.
    private func value(for key: String, in content: String) -> String? {
        // Look for:  "key" = "
        let keyDecl = "\"\(key)\" = \""
        guard let declRange = content.range(of: keyDecl) else { return nil }

        // Walk forward from the opening quote of the value, respecting \" escapes,
        // until we find the unescaped closing " followed by optional whitespace and ;
        var idx = declRange.upperBound
        var result = ""
        while idx < content.endIndex {
            let ch = content[idx]
            if ch == "\\" {
                // Escape sequence — consume backslash + next char
                let next = content.index(after: idx)
                if next < content.endIndex {
                    result.append(ch)
                    result.append(content[next])
                    idx = content.index(after: next)
                } else {
                    break
                }
            } else if ch == "\"" {
                // Closing quote — confirm followed by optional whitespace then ;
                var peek = content.index(after: idx)
                while peek < content.endIndex && content[peek].isWhitespace { peek = content.index(after: peek) }
                if peek < content.endIndex && content[peek] == ";" {
                    return result
                } else {
                    // Embedded quote that isn't the value terminator (shouldn't happen
                    // in well-formed .strings, but skip it gracefully)
                    result.append(ch)
                    idx = content.index(after: idx)
                }
            } else {
                result.append(ch)
                idx = content.index(after: idx)
            }
        }
        return nil
    }

    // MARK: - Tests

    /// Every language's help.body.autoNotify value must contain a native-script
    /// token and must not contain any romanized placeholder.
    func test_autoNotify_allLanguages_haveNativeScriptAndNoRomanization() throws {
        for (lang, tokens) in expectedTokens.sorted(by: { $0.key < $1.key }) {
            let url  = try stringsURL(for: lang, sourceFile: #file)
            let raw  = try String(contentsOf: url, encoding: .utf8)
            let val  = try XCTUnwrap(
                value(for: "help.body.autoNotify", in: raw),
                "\(lang): help.body.autoNotify key missing"
            )

            XCTAssertTrue(
                val.contains(tokens.autoNotify),
                "\(lang) help.body.autoNotify missing native token '\(tokens.autoNotify)'"
            )
            for bad in forbiddenTokens {
                XCTAssertFalse(
                    val.contains(bad),
                    "\(lang) help.body.autoNotify contains romanized placeholder '\(bad)'"
                )
            }
        }
    }

    /// Every language's help.body.siri value must contain a native-script
    /// token and must not contain any romanized placeholder.
    func test_siri_allLanguages_haveNativeScriptAndNoRomanization() throws {
        for (lang, tokens) in expectedTokens.sorted(by: { $0.key < $1.key }) {
            let url  = try stringsURL(for: lang, sourceFile: #file)
            let raw  = try String(contentsOf: url, encoding: .utf8)
            let val  = try XCTUnwrap(
                value(for: "help.body.siri", in: raw),
                "\(lang): help.body.siri key missing"
            )

            XCTAssertTrue(
                val.contains(tokens.siri),
                "\(lang) help.body.siri missing native token '\(tokens.siri)'"
            )
            for bad in forbiddenTokens {
                XCTAssertFalse(
                    val.contains(bad),
                    "\(lang) help.body.siri contains romanized placeholder '\(bad)'"
                )
            }
        }
    }

    /// The help strings added by our Auto-SMS feature must use \\n escape
    /// sequences (not bare newlines) so the additions are correctly encoded.
    /// Apple's .strings format allows bare newlines in original values, but
    /// our programmatic additions via Python always encode newlines as \\n.
    func test_autoSMSAdditions_useEscapedNewlines() throws {
        // Sentinel text unique to our additions in every language —
        // preceded by \\n in the file if encoding is correct.
        let sentinels: [String: String] = [
            "en": "\\nSend without approval",
            "de": "\\nOhne Best",
            "es": "\\nEnviar sin aprobaci",
            "fr": "\\nEnvoyer sans approbation",
            "it": "\\nInviare senza approvazione",
            "pt": "\\nEnviar sem aprova",
            "ru": "\\nОтправка без",
            "ar": "\\nإرسال بدون",
            "hi": "\\nबिना अनुमोदन",
            "ja": "\\n承認なしで送信",
            "th": "\\nส่งโดยไม่ต้องอนุมัติ",
            "vi": "\\nGửi mà không",
            "zh-Hans": "\\n无需批准",
        ]
        for (lang, sentinel) in sentinels.sorted(by: { $0.key < $1.key }) {
            let url = try stringsURL(for: lang, sourceFile: #file)
            let raw = try String(contentsOf: url, encoding: .utf8)
            XCTAssertTrue(
                raw.contains(sentinel),
                "\(lang): Auto-SMS addition missing or not using \\\\n escape — expected '\(sentinel)'"
            )
        }
    }

    /// Both updated keys must be present in every language file.
    /// Uses a plain string search for the key declaration rather than a
    /// regex, so it works regardless of value length or newline style.
    func test_allLanguages_haveRequiredHelpKeys() throws {
        let requiredKeys = ["help.body.autoNotify", "help.body.siri"]
        for lang in expectedTokens.keys.sorted() {
            let url = try stringsURL(for: lang, sourceFile: #file)
            let raw = try String(contentsOf: url, encoding: .utf8)
            for key in requiredKeys {
                XCTAssertTrue(
                    raw.contains("\"\(key)\""),
                    "\(lang): required key '\(key)' is missing from Localizable.strings"
                )
            }
        }
    }

    // MARK: - Auto-SMS section keys (SettingsView)

    /// Every language file must contain all 13 keys used by the Auto-SMS section.
    func test_allLanguages_haveAutoSMSSectionKeys() throws {
        let autoSMSKeys = [
            "Auto-SMS (No Approval Needed)",
            "settings.autoSMS.description",
            "settings.autoSMS.setupTitle",
            "settings.autoSMS.step1",
            "settings.autoSMS.step2",
            "settings.autoSMS.step3a",
            "settings.autoSMS.step3b",
            "settings.autoSMS.step4a",
            "settings.autoSMS.step4b",
            "settings.autoSMS.step4c",
            "settings.autoSMS.step5",
            "Open Shortcuts App",
            "settings.autoSMS.footer",
        ]
        for lang in expectedTokens.keys.sorted() {
            let url = try stringsURL(for: lang, sourceFile: #file)
            let raw = try String(contentsOf: url, encoding: .utf8)
            for key in autoSMSKeys {
                XCTAssertTrue(
                    raw.contains("\"\(key)\""),
                    "\(lang): Auto-SMS key '\(key)' missing from Localizable.strings"
                )
            }
        }
    }

    /// Auto-SMS description values must contain native-script content, not romanized
    /// placeholders. Spot-checks the key with the longest translatable phrase.
    func test_autoSMS_description_allLanguages_haveNativeScript() throws {
        let nativeTokens: [String: String] = [
            "en":      "no compose sheet",
            "de":      "Verfassen",
            "es":      "hoja de redacción",
            "fr":      "fenêtre de rédaction",
            "it":      "foglio di composizione",
            "pt":      "folha de composição",
            "ru":      "окна",
            "ar":      "نافذة",
            "hi":      "कम्पोज़ शीट",
            "ja":      "作成",
            "th":      "หน้าเขียนข้อความ",
            "vi":      "trang soạn",
            "zh-Hans": "无需",
        ]
        for (lang, token) in nativeTokens.sorted(by: { $0.key < $1.key }) {
            let url = try stringsURL(for: lang, sourceFile: #file)
            let raw = try String(contentsOf: url, encoding: .utf8)
            let val = try XCTUnwrap(
                value(for: "settings.autoSMS.description", in: raw),
                "\(lang): settings.autoSMS.description key missing"
            )
            XCTAssertTrue(
                val.contains(token),
                "\(lang) settings.autoSMS.description missing native token '\(token)'. Got: \(val)"
            )
        }
    }

    // MARK: - AlarmFiringView keys

    /// Both UI strings used by AlarmFiringView must be present in every language file.
    func test_allLanguages_haveAlarmFiringViewKeys() throws {
        let keys = ["Snooze 10 min", "Slide to dismiss"]
        for lang in expectedTokens.keys.sorted() {
            let url = try stringsURL(for: lang, sourceFile: #file)
            let raw = try String(contentsOf: url, encoding: .utf8)
            for key in keys {
                XCTAssertTrue(
                    raw.contains("\"\(key)\""),
                    "\(lang): AlarmFiringView key '\(key)' missing from Localizable.strings"
                )
            }
        }
    }

    /// "Slide to dismiss" translations must use native script — not an English
    /// literal left as a fallback.
    func test_slideToDismiss_nonEnglishLanguages_areNotEnglishLiteral() throws {
        let nonEnglish = expectedTokens.keys.filter { $0 != "en" }
        for lang in nonEnglish.sorted() {
            let url = try stringsURL(for: lang, sourceFile: #file)
            let raw = try String(contentsOf: url, encoding: .utf8)
            if let val = value(for: "Slide to dismiss", in: raw) {
                XCTAssertNotEqual(
                    val, "Slide to dismiss",
                    "\(lang) 'Slide to dismiss' is still the untranslated English literal"
                )
            }
        }
    }

    /// "Snooze 10 min" translations must use native script — not an English
    /// literal left as a fallback.
    func test_snooze10min_nonEnglishLanguages_areNotEnglishLiteral() throws {
        let nonEnglish = expectedTokens.keys.filter { $0 != "en" }
        for lang in nonEnglish.sorted() {
            let url = try stringsURL(for: lang, sourceFile: #file)
            let raw = try String(contentsOf: url, encoding: .utf8)
            if let val = value(for: "Snooze 10 min", in: raw) {
                XCTAssertNotEqual(
                    val, "Snooze 10 min",
                    "\(lang) 'Snooze 10 min' is still the untranslated English literal"
                )
            }
        }
    }
}
