// AlarmAudioPlayerSessionTests.swift
// Verifies that AlarmAudioPlayer configures AVAudioSession correctly for
// CarPlay and Bluetooth playback.
//
// Core fix being tested: the session must include .duckOthers, .allowBluetoothHFP,
// and .allowBluetoothHFPA2DP so the alarm:
//   • is audible over a playing CarPlay radio (duckOthers)
//   • routes through CarPlay / HFP Bluetooth speakers (allowBluetooth)
//   • routes through stereo Bluetooth speakers / AirPods (allowBluetoothA2DP)
//
// Without these options iOS defaults to the built-in speaker even when
// CarPlay or Bluetooth is connected, and the radio is not lowered.
//
// Run with ⌘U in Xcode or: xcodebuild test -scheme GeoNap

import XCTest
import AVFoundation
@testable import GeoNap

@MainActor
final class AlarmAudioPlayerSessionTests: XCTestCase {

    override func setUp() async throws {
        try await super.setUp()
        // Start from a known non-playback category.
        try AVAudioSession.sharedInstance().setCategory(.ambient)
    }

    override func tearDown() async throws {
        AlarmAudioPlayer.shared.stop()
        // Leave the session in a neutral state for subsequent tests.
        try? AVAudioSession.sharedInstance().setCategory(.ambient)
        try await super.tearDown()
    }

    // MARK: - Session category

    func test_play_bundledSound_setsPlaybackCategory() throws {
        guard let sound = NotificationSound.bundledSounds.first else {
            throw XCTSkip("No bundled sounds available — add a .wav to the Sounds/ folder")
        }
        AlarmAudioPlayer.shared.play(sound: sound)
        XCTAssertEqual(AVAudioSession.sharedInstance().category, .playback,
                       "Session must use .playback so alarm audio continues when screen locks")
    }

    // MARK: - CarPlay / Bluetooth session options (the core fix)

    func test_play_bundledSound_includesDuckOthers() throws {
        guard let sound = NotificationSound.bundledSounds.first else {
            throw XCTSkip("No bundled sounds available")
        }
        AlarmAudioPlayer.shared.play(sound: sound)
        XCTAssertTrue(AVAudioSession.sharedInstance().categoryOptions.contains(.duckOthers),
                      ".duckOthers required so alarm lowers CarPlay radio volume")
    }

    func test_play_bundledSound_includesAllowBluetooth() throws {
        guard let sound = NotificationSound.bundledSounds.first else {
            throw XCTSkip("No bundled sounds available")
        }
        AlarmAudioPlayer.shared.play(sound: sound)
        XCTAssertTrue(AVAudioSession.sharedInstance().categoryOptions.contains(.allowBluetoothHFP),
                      ".allowBluetoothHFP required so alarm routes through CarPlay / HFP Bluetooth")
    }

    func test_play_bundledSound_includesAllowBluetoothA2DP() throws {
        guard let sound = NotificationSound.bundledSounds.first else {
            throw XCTSkip("No bundled sounds available")
        }
        AlarmAudioPlayer.shared.play(sound: sound)
        XCTAssertTrue(AVAudioSession.sharedInstance().categoryOptions.contains(.allowBluetoothHFPA2DP),
                      ".allowBluetoothHFPA2DP required so alarm routes through stereo BT speakers")
    }

    // MARK: - Route change handling

    func test_routeChange_newDeviceAvailable_doesNotCrash() throws {
        guard let sound = NotificationSound.bundledSounds.first else {
            throw XCTSkip("No bundled sounds available")
        }
        AlarmAudioPlayer.shared.play(sound: sound)
        postRouteChange(reason: .newDeviceAvailable)
        // No crash + still playing = pass
        XCTAssertTrue(AlarmAudioPlayer.shared.isPlaying)
    }

    func test_routeChange_oldDeviceUnavailable_doesNotCrash() throws {
        guard let sound = NotificationSound.bundledSounds.first else {
            throw XCTSkip("No bundled sounds available")
        }
        AlarmAudioPlayer.shared.play(sound: sound)
        postRouteChange(reason: .oldDeviceUnavailable)
        XCTAssertTrue(AlarmAudioPlayer.shared.isPlaying)
    }

    func test_routeChangeAfterStop_doesNotCrash() throws {
        guard let sound = NotificationSound.bundledSounds.first else {
            throw XCTSkip("No bundled sounds available")
        }
        AlarmAudioPlayer.shared.play(sound: sound)
        AlarmAudioPlayer.shared.stop()
        postRouteChange(reason: .newDeviceAvailable)
        // No crash = observer was not left dangling after stop()
    }

    // MARK: - Vibrate path

    func test_vibrateSound_doesNotActivatePlaybackSession() {
        try? AVAudioSession.sharedInstance().setCategory(.ambient)
        AlarmAudioPlayer.shared.play(sound: NotificationSound(id: "vibrate"))
        XCTAssertNotEqual(AVAudioSession.sharedInstance().category, .playback,
                          "Vibrate-only must not activate the playback session")
    }

    // MARK: - Stop

    func test_stopAllowsSessionCategoryToChange() throws {
        guard let sound = NotificationSound.bundledSounds.first else {
            throw XCTSkip("No bundled sounds available")
        }
        AlarmAudioPlayer.shared.play(sound: sound)
        AlarmAudioPlayer.shared.stop()
        XCTAssertNoThrow(
            try AVAudioSession.sharedInstance().setCategory(.ambient),
            "Session should be freely configurable after stop()"
        )
    }

    // MARK: - Helpers

    private func postRouteChange(reason: AVAudioSession.RouteChangeReason) {
        NotificationCenter.default.post(
            name: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance(),
            userInfo: [AVAudioSessionRouteChangeReasonKey: reason.rawValue]
        )
    }
}
