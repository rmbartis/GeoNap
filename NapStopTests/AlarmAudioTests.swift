// AlarmAudioTests.swift
// Bundle-resource integration tests for alarm sounds.
//
// These tests run against the HOST app bundle (via BUNDLE_LOADER), so
// Bundle.main is GeoNap.app — the real bundle with the Sounds/ folder.
// They exist specifically to catch the class of bug where .wav files are
// present on disk but not reachable at the path the playback code expects.
//
// If either test fails, the most likely cause is:
//   • .wav files were removed from the Xcode project / file-system sync group
//   • The Sounds/ folder was restructured and bundleURL no longer resolves it
//   • A new sound was added to Sounds/ but is somehow excluded from the bundle

import XCTest
@testable import GeoNap

final class AlarmAudioTests: XCTestCase {

    // MARK: - Bundle discovery

    func test_bundledSounds_isNonEmpty() {
        XCTAssertFalse(
            NotificationSound.bundledSounds.isEmpty,
            "No .wav files found in the app bundle. " +
            "Check that GeoAlarm/Sounds/ is included in the GeoNap target's " +
            "Copy Bundle Resources phase (or PBXFileSystemSynchronizedRootGroup)."
        )
    }

    // MARK: - URL resolution

    func test_bundleURL_nonNilForEachBundledSound() {
        let sounds = NotificationSound.bundledSounds
        XCTAssertFalse(sounds.isEmpty, "Precondition: bundledSounds must be non-empty")

        for sound in sounds {
            XCTAssertNotNil(
                sound.bundleURL,
                "\(sound.id): bundleURL returned nil. " +
                "The file appears in paths(forResourcesOfType:) but cannot be " +
                "resolved to a URL — this will cause AlarmAudioPlayer to fall " +
                "back to the default chime instead of playing the custom sound."
            )
        }
    }

    // MARK: - UNNotificationSound name resolution

    func test_bundleRelativeSoundName_containsFilename() {
        for sound in NotificationSound.bundledSounds {
            let relativeName = sound.bundleRelativeSoundName
            XCTAssertTrue(
                relativeName.hasSuffix(sound.id),
                "\(sound.id): bundleRelativeSoundName '\(relativeName)' does not end " +
                "with the expected filename. UNNotificationSound will not find the file."
            )
        }
    }

    func test_unSound_nonNilForEachBundledSound() {
        for sound in NotificationSound.bundledSounds {
            XCTAssertNotNil(
                sound.unSound,
                "\(sound.id): unSound returned nil. " +
                "Background notifications will play the default chime instead of " +
                "the user-selected custom sound."
            )
        }
    }
}
