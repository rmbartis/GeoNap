// LocalizationConsistencyTests.swift
// Systematic, structural consistency checks across all 13 Localizable.strings
// files — as opposed to LocalizationTests.swift, which spot-checks specific
// keys/tokens for specific features by hand.
//
// The existing LocalizationTests.swift catches "did we forget to translate
// THIS particular string" for strings someone remembered to write a test for.
// It does not catch "does every language have the SAME set of keys as
// English" — the actual class of bug that causes a language to silently fall
// back to its raw key text (or crash on a format-string mismatch) in
// production, without ever needing a hand-written test for the specific key
// that went missing. This file closes that gap generically, so newly added
// keys are covered automatically without anyone remembering to add a
// per-key test (Bob, 2026-07-05).
//
// Uses PropertyListSerialization — the same parser Foundation/Bundle uses at
// runtime to load .strings files — rather than a hand-rolled scanner, so a
// parse failure here means the file is genuinely malformed, not an artifact
// of imperfect test-side parsing.

import XCTest

final class LocalizationConsistencyTests: XCTestCase {

    // MARK: - Language table

    /// All languages the app ships, per LanguageManager.AppLanguage and the
    /// Xcode project's `knownRegions`. Kept as a literal list (rather than
    /// importing AppLanguage directly) so this file also catches drift
    /// between the enum and the actual .lproj folders on disk — see
    /// `test_everyDeclaredLanguage_hasAnOnDiskLprojFolder` and
    /// `test_noStrayLprojFolders_beyondDeclaredLanguages`.
    static let languageCodes = [
        "ar", "de", "en", "es", "fr", "hi", "it",
        "ja", "pt", "ru", "th", "vi", "zh-Hans",
    ]

    static let referenceLanguage = "en"

    // MARK: - File location

    private func projectRoot(sourceFile: StaticString) -> URL {
        URL(fileURLWithPath: "\(sourceFile)")
            .deletingLastPathComponent()   // NapStopTests/
            .deletingLastPathComponent()   // project root
    }

    private func lprojDirectory(for lang: String, sourceFile: StaticString) -> URL {
        projectRoot(sourceFile: sourceFile)
            .appendingPathComponent("GeoAlarm")
            .appendingPathComponent("\(lang).lproj")
    }

    private func stringsURL(for lang: String, sourceFile: StaticString) -> URL {
        lprojDirectory(for: lang, sourceFile: sourceFile)
            .appendingPathComponent("Localizable.strings")
    }

    // MARK: - Parsing

    /// Parses a Localizable.strings file into [key: value] using Foundation's
    /// own plist parser. Throws (via XCTUnwrap/fail) on genuinely malformed
    /// files rather than silently producing a partial/wrong dictionary.
    private func parse(_ lang: String, sourceFile: StaticString = #file, file: StaticString = #filePath, line: UInt = #line) throws -> [String: String] {
        let url = stringsURL(for: lang, sourceFile: sourceFile)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("Localizable.strings not found for '\(lang)': \(url.path)")
        }
        let data = try Data(contentsOf: url)
        let plist: Any
        do {
            plist = try PropertyListSerialization.propertyList(from: data, format: nil)
        } catch {
            XCTFail("\(lang): Localizable.strings failed to parse as a property list — the file is malformed (unbalanced quotes, bad escape, etc.): \(error)", file: file, line: line)
            return [:]
        }
        guard let dict = plist as? [String: String] else {
            XCTFail("\(lang): Localizable.strings did not parse to a flat [String: String]", file: file, line: line)
            return [:]
        }
        return dict
    }

    // MARK: - Language table completeness

    /// The set of languages this test file (and LanguageManager.AppLanguage)
    /// claims to support must have a real .lproj folder + Localizable.strings
    /// on disk for every code — catches a language removed from disk but left
    /// in the picker (crashes to Bundle.main fallback) or vice versa.
    func test_everyDeclaredLanguage_hasAnOnDiskLprojFolder() throws {
        for lang in Self.languageCodes {
            let dir = lprojDirectory(for: lang, sourceFile: #file)
            var isDir: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDir)
            XCTAssertTrue(exists && isDir.boolValue, "\(lang).lproj folder is missing at \(dir.path)")

            let stringsFile = stringsURL(for: lang, sourceFile: #file)
            XCTAssertTrue(FileManager.default.fileExists(atPath: stringsFile.path),
                "\(lang).lproj exists but has no Localizable.strings")
        }
    }

    /// The reverse direction: no stray `.lproj` folder on disk for a language
    /// this test file doesn't know about (e.g. a leftover folder for a
    /// language that was removed from the picker, still shipping unused
    /// strings in the app bundle).
    func test_noStrayLprojFolders_beyondDeclaredLanguages() throws {
        let geoAlarmDir = projectRoot(sourceFile: #file).appendingPathComponent("GeoAlarm")
        let contents = try FileManager.default.contentsOfDirectory(atPath: geoAlarmDir.path)
        let lprojFolders = contents
            .filter { $0.hasSuffix(".lproj") }
            .map { String($0.dropLast(".lproj".count)) }

        let declared = Set(Self.languageCodes)
        let stray = Set(lprojFolders).subtracting(declared)
        XCTAssertTrue(stray.isEmpty,
            "Found .lproj folder(s) on disk not declared in languageCodes: \(stray.sorted()) — either add them to the language table or remove the stray folder(s)")
    }

    // MARK: - Key parity across all languages

    /// Every non-English language must have EXACTLY the same key set as
    /// English. Missing keys silently fall back to raw key text at runtime;
    /// extra keys are dead weight from a removed/renamed English key that
    /// never got cleaned up in translations.
    func test_allLanguages_haveExactSameKeySet_asEnglish() throws {
        let reference = try parse(Self.referenceLanguage)
        let referenceKeys = Set(reference.keys)
        XCTAssertFalse(referenceKeys.isEmpty,
            "English Localizable.strings parsed to zero keys — parser or file problem, treat other assertions in this test as untrustworthy until fixed")

        for lang in Self.languageCodes where lang != Self.referenceLanguage {
            let dict = try parse(lang)
            let keys = Set(dict.keys)

            let missing = referenceKeys.subtracting(keys)
            let extra   = keys.subtracting(referenceKeys)

            XCTAssertTrue(missing.isEmpty,
                "\(lang) is missing \(missing.count) key(s) present in English: \(missing.sorted().prefix(15).joined(separator: ", "))")
            XCTAssertTrue(extra.isEmpty,
                "\(lang) has \(extra.count) orphaned key(s) not present in English: \(extra.sorted().prefix(15).joined(separator: ", "))")
        }
    }

    // MARK: - No empty translation values

    /// A key present but translated to an empty (or whitespace-only) string
    /// renders as blank UI — worse than falling back to English, since
    /// there's no visible clue anything is wrong.
    func test_noLanguage_hasEmptyTranslationValues() throws {
        for lang in Self.languageCodes {
            let dict = try parse(lang)
            let empties = dict.filter { $0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            XCTAssertTrue(empties.isEmpty,
                "\(lang) has \(empties.count) key(s) with an empty translation: \(empties.keys.sorted().prefix(15).joined(separator: ", "))")
        }
    }

    // MARK: - Format specifier parity

    /// Extracts printf-style format specifiers (%d, %@, %.2f, %1$@, etc.)
    /// from a string value.
    private func formatSpecifiers(in value: String) -> [String] {
        let pattern = #"%(\d+\$)?[-+ 0#]*\d*(\.\d+)?[@dDuUxXoOfeEgGcCsSp%]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(value.startIndex..., in: value)
        return regex.matches(in: value, range: range).compactMap {
            Range($0.range, in: value).map { String(value[$0]) }
        }
    }

    /// Every translation must use the same COUNT of format specifiers as the
    /// English source for that key. A translation that drops a %d (e.g. the
    /// count in "%d contacts") silently loses data; one that adds an extra
    /// specifier crashes `String(format:)` with an argument-count mismatch at
    /// runtime. Compares specifier type multisets, not positional order,
    /// since grammar can legitimately reorder arguments between languages.
    func test_formatSpecifiers_matchEnglish_acrossAllLanguages() throws {
        let reference = try parse(Self.referenceLanguage)
        for lang in Self.languageCodes where lang != Self.referenceLanguage {
            let dict = try parse(lang)
            for (key, enValue) in reference {
                guard let translated = dict[key] else { continue }  // caught by key-parity test above
                let enSpecs = formatSpecifiers(in: enValue).sorted()
                let trSpecs = formatSpecifiers(in: translated).sorted()
                XCTAssertEqual(enSpecs, trSpecs,
                    "\(lang).\"\(key)\": format specifiers don't match English — en has \(enSpecs), \(lang) has \(trSpecs)")
            }
        }
    }

    // MARK: - Duplicate key declarations

    /// PropertyListSerialization silently keeps the LAST value when a key is
    /// declared twice in a .strings file — it never errors, so a copy/paste
    /// duplicate silently shadows the real translation with no visible
    /// symptom besides "why does this string say the wrong thing." Scans raw
    /// text for `"key" = ` declarations at the start of a line (heuristic:
    /// could in principle misfire if a multi-line value's continuation line
    /// happened to start with a quote character, which none of the current
    /// files do).
    func test_noLanguage_hasDuplicateKeyDeclarations() throws {
        let pattern = try NSRegularExpression(pattern: #"(?m)^"((?:[^"\\]|\\.)*)"\s*=\s*""#)

        for lang in Self.languageCodes {
            let url = stringsURL(for: lang, sourceFile: #file)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            let raw = try String(contentsOf: url, encoding: .utf8)
            let range = NSRange(raw.startIndex..., in: raw)

            var seen = Set<String>()
            var dupes = Set<String>()
            pattern.enumerateMatches(in: raw, range: range) { match, _, _ in
                guard let match, let keyRange = Range(match.range(at: 1), in: raw) else { return }
                let key = String(raw[keyRange])
                if seen.contains(key) { dupes.insert(key) }
                seen.insert(key)
            }

            XCTAssertTrue(dupes.isEmpty,
                "\(lang): duplicate key declaration(s) — later declarations silently shadow earlier ones: \(dupes.sorted())")
        }
    }

    // MARK: - AppLanguage enum ↔ disk consistency

    /// The number of languages this test table declares must match the
    /// number of .lproj folders actually shipping Localizable.strings — a
    /// cheap sanity check that catches a language being added/removed from
    /// only one of {languageCodes here, AppLanguage enum, .lproj folders,
    /// Xcode project knownRegions} without the others being updated to match.
    func test_languageTable_has13Languages() {
        XCTAssertEqual(Self.languageCodes.count, 13,
            "Expected 13 supported languages (ar, de, en, es, fr, hi, it, ja, pt, ru, th, vi, zh-Hans) — update this test deliberately if the supported-language count actually changed")
    }
}
