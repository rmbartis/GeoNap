// Copyright © 2026 Robert Bartis. All rights reserved.

// NotificationSoundTests.swift
// Unit tests for GeoAlarm/Models/NotificationSound.swift — previously had no
// test coverage at all despite being a small, pure, easily-testable struct
// with real branching logic (the `vibrate` → silentTone AlarmKit mapping is
// the exact fix for a real "Vibrate Only rings out loud" bug; displayName's
// filename-cleanup logic has never been exercised). Added 2026-09-28.
//
// Scope: everything here is pure string/enum-style logic that needs no
// Bundle.main resources to evaluate correctly — matches this project's
// existing "pure logic only" testing convention (see
// CalendarScanCandidateStoreTests.swift's header comment). Bundle-dependent
// members (`bundledSounds`, `bundleURL` for a non-system sound,
// `installBundledSoundsIfNeeded()`) are intentionally NOT exercised here for
// the same reason live EventKit/CLGeocoder calls aren't in the calendar scan
// suite — they're thin wrappers around Bundle.main/FileManager with no
// branching logic worth testing in isolation, and would require bundling
// real WAV fixtures into the test target to exercise meaningfully.

import XCTest
import UserNotifications
@testable import GeoNap

final class NotificationSoundTests: XCTestCase {

    // MARK: - Initializers / rawValue

    func test_initByID_andInitByRawValue_produceEqualInstances() {
        let a = NotificationSound(id: "Boat Horn.wav")
        let b = NotificationSound(rawValue: "Boat Horn.wav")
        XCTAssertEqual(a, b)
    }

    func test_rawValue_matchesID() {
        let sound = NotificationSound(id: "Train Horn.wav")
        XCTAssertEqual(sound.rawValue, "Train Horn.wav")
        XCTAssertEqual(sound.rawValue, sound.id)
    }

    // MARK: - System presets

    func test_systemPresets_haveExpectedIDs() {
        XCTAssertEqual(NotificationSound.vibrate.id, "vibrate")
        XCTAssertEqual(NotificationSound.default.id, "default")
        XCTAssertEqual(NotificationSound.critical.id, "critical")
    }

    // MARK: - isSystem

    func test_isSystem_trueForAllThreeSystemPresets() {
        XCTAssertTrue(NotificationSound.vibrate.isSystem)
        XCTAssertTrue(NotificationSound.default.isSystem)
        XCTAssertTrue(NotificationSound.critical.isSystem)
    }

    func test_isSystem_falseForABundledSoundID() {
        XCTAssertFalse(NotificationSound(id: "Boat Horn.wav").isSystem)
    }

    // MARK: - alarmKitSoundName
    // Regression guard: `vibrate` used to collapse to `nil` → AlarmKit's
    // `.default` tone, which made "Vibrate Only" alarms ring out loud instead
    // of just vibrating. It must map to the reserved silent tone instead.

    func test_alarmKitSoundName_vibrate_mapsToReservedSilentTone() {
        XCTAssertEqual(NotificationSound.vibrate.alarmKitSoundName, NotificationSound.silentTone)
    }

    func test_alarmKitSoundName_defaultAndCritical_areNil_useAlarmKitDefaultTone() {
        XCTAssertNil(NotificationSound.default.alarmKitSoundName)
        XCTAssertNil(NotificationSound.critical.alarmKitSoundName)
    }

    func test_alarmKitSoundName_bundledSound_returnsItsOwnFilename() {
        XCTAssertEqual(NotificationSound(id: "Boat Horn.wav").alarmKitSoundName, "Boat Horn.wav")
    }

    // MARK: - displayName

    func test_displayName_systemPresets() {
        XCTAssertEqual(NotificationSound.vibrate.displayName, "Vibrate Only")
        XCTAssertEqual(NotificationSound.default.displayName, "Default")
        XCTAssertEqual(NotificationSound.critical.displayName, "Critical (ignores silent mode)")
    }

    func test_displayName_bundledSound_stripsExtension() {
        XCTAssertEqual(NotificationSound(id: "Boat Horn.wav").displayName, "Boat Horn")
    }

    func test_displayName_bundledSound_replacesUnderscoresWithSpaces() {
        XCTAssertEqual(NotificationSound(id: "Airport_Chime.wav").displayName, "Airport Chime")
    }

    func test_displayName_bundledSound_replacesDashesWithSpaces() {
        XCTAssertEqual(NotificationSound(id: "train-horn.wav").displayName, "Train Horn")
    }

    func test_displayName_bundledSound_capitalizesEachWord() {
        XCTAssertEqual(NotificationSound(id: "boat horn.wav").displayName, "Boat Horn")
    }

    func test_displayName_bundledSound_handlesMixedUnderscoresAndDashes() {
        XCTAssertEqual(NotificationSound(id: "old_train-whistle.wav").displayName, "Old Train Whistle")
    }

    // MARK: - localizationKey

    func test_localizationKey_systemPresets() {
        XCTAssertEqual(NotificationSound.vibrate.localizationKey, "sound.vibrate")
        XCTAssertEqual(NotificationSound.default.localizationKey, "sound.default")
        XCTAssertEqual(NotificationSound.critical.localizationKey, "sound.critical")
    }

    func test_localizationKey_bundledSound_equalsItsDisplayName() {
        let sound = NotificationSound(id: "Boat Horn.wav")
        XCTAssertEqual(sound.localizationKey, sound.displayName)
        XCTAssertEqual(sound.localizationKey, "Boat Horn")
    }

    // MARK: - systemImage

    func test_systemImage_mapping() {
        XCTAssertEqual(NotificationSound.vibrate.systemImage, "waveform")
        XCTAssertEqual(NotificationSound.default.systemImage, "bell")
        XCTAssertEqual(NotificationSound.critical.systemImage, "bell.badge.waveform.fill")
        XCTAssertEqual(NotificationSound(id: "Boat Horn.wav").systemImage, "music.note")
    }

    // MARK: - bundleRelativeSoundName
    // For a system sound, `bundleURL` is always nil (guarded by `!isSystem`),
    // so `bundleRelativeSoundName` must fall back to the bare id rather than
    // crash or produce a bogus path.

    func test_bundleRelativeSoundName_systemSound_fallsBackToID() {
        XCTAssertEqual(NotificationSound.vibrate.bundleRelativeSoundName, "vibrate")
        XCTAssertEqual(NotificationSound.default.bundleRelativeSoundName, "default")
    }

    // MARK: - unSound

    func test_unSound_vibrate_isNil() {
        XCTAssertNil(NotificationSound.vibrate.unSound)
    }

    func test_unSound_default_isSystemDefault() {
        XCTAssertEqual(NotificationSound.default.unSound, .default)
    }

    func test_unSound_critical_fallsBackToSystemDefault() {
        // Critical Alerts entitlement was denied (see source comment) — must
        // fall back to .default, never crash or return a defaultCritical sound.
        XCTAssertEqual(NotificationSound.critical.unSound, .default)
    }

    func test_unSound_bundledSound_isNotNil() {
        // Wraps the filename in a UNNotificationSound regardless of whether
        // the file actually exists in the bundle at test time — construction
        // itself never fails.
        XCTAssertNotNil(NotificationSound(id: "Boat Horn.wav").unSound)
    }

    // MARK: - `all`
    // .critical is deliberately omitted from the user-facing list (Apple
    // denied the Critical Alerts entitlement) — regression guard against it
    // silently reappearing.

    func test_all_startsWithVibrateThenDefault() {
        let all = NotificationSound.all
        XCTAssertGreaterThanOrEqual(all.count, 2)
        XCTAssertEqual(all[0], .vibrate)
        XCTAssertEqual(all[1], .default)
    }

    func test_all_neverIncludesCritical() {
        XCTAssertFalse(NotificationSound.all.contains(.critical),
            "critical must stay excluded from the user-facing list — the Critical Alerts entitlement was denied, so offering it would be misleading")
    }

    // MARK: - Hashable / Codable

    func test_equality_isBasedOnID() {
        XCTAssertEqual(NotificationSound(id: "x.wav"), NotificationSound(id: "x.wav"))
        XCTAssertNotEqual(NotificationSound(id: "x.wav"), NotificationSound(id: "y.wav"))
    }

    func test_codableRoundTrip_preservesID() throws {
        let sound = NotificationSound(id: "Boat Horn.wav")
        let data = try JSONEncoder().encode(sound)
        let decoded = try JSONDecoder().decode(NotificationSound.self, from: data)
        XCTAssertEqual(decoded, sound)
    }
}
