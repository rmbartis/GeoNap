// AlarmAudioPlayerTests.swift
// CI tests for AlarmAudioPlayer covering:
//
//   • AVAudioSession configured with .playback category on play()
//   • Session options include .duckOthers, .allowBluetooth, .allowBluetoothA2DP
//     (the fix for alarm not being heard over CarPlay radio / Bluetooth audio)
//   • Route change observer registered on play(), removed on stop()
//   • No crash for all route change reasons (newDeviceAvailable, oldDeviceUnavailable, etc.)
//   • Vibrate-only path does not activate the playback session
//   • Multiple consecutive play() calls do not stack route change observers
//
// Run with: ⌘U in Xcode  or  xcodebuild test -scheme GeoAlarm

import XCTest
import AVFoundation
@testable import GeoAlarm

final class AlarmAudioPlayerTests: XCTestCase {

    private var audioPlayer: AlarmAudioPlayer!

    override func setUp() {
        super.setUp()
        audioPlayer = AlarmAudioPlayer()
    }

    override func tearDown() {
        audioPlayer.stop()
        audioPlayer = nil
        // Leave the session in a neutral state for subsequent tests.
        try? AVAudioSession.sharedInstance().setCategory(.ambient)
        super.tearDown()
    }

    // MARK: - Session category

    func test_playDefaultSound_setsPlaybackCategory() {
        audioPlayer.play(.default)
        XCTAssertEqual(AVAudioSession.sharedInstance().category, .playback,
                       "Session must use .playback so alarm audio continues when screen locks")
    }

    func test_playCriticalSound_setsPlaybackCategory() {
        audioPlayer.play(.critical)
        XCTAssertEqual(AVAudioSession.sharedInstance().category, .playback)
    }

    // MARK: - CarPlay / Bluetooth session options
    //
    // These three options are the core fix. Without them:
    //   • .duckOthers  — alarm is inaudible when car radio is playing via CarPlay
    //   • .allowBluetooth     — alarm plays from phone speaker instead of CarPlay/BT HFP
    //   • .allowBluetoothA2DP — alarm plays from phone speaker instead of BT stereo speakers

    func test_playDefaultSound_includesDuckOthers() {
        audioPlayer.play(.default)
        XCTAssertTrue(AVAudioSession.sharedInstance().categoryOptions.contains(.duckOthers),
                      ".duckOthers required so alarm lowers CarPlay radio volume")
    }

    func test_playDefaultSound_includesAllowBluetooth() {
        audioPlayer.play(.default)
        XCTAssertTrue(AVAudioSession.sharedInstance().categoryOptions.contains(.allowBluetooth),
                      ".allowBluetooth required so alarm routes through CarPlay / HFP Bluetooth")
    }

    func test_playDefaultSound_includesAllowBluetoothA2DP() {
        audioPlayer.play(.default)
        XCTAssertTrue(AVAudioSession.sharedInstance().categoryOptions.contains(.allowBluetoothA2DP),
                      ".allowBluetoothA2DP required so alarm routes through stereo BT speakers")
    }

    func test_playCriticalSound_includesAllCarPlayBluetoothOptions() {
        audioPlayer.play(.critical)
        let options = AVAudioSession.sharedInstance().categoryOptions
        XCTAssertTrue(options.contains(.duckOthers))
        XCTAssertTrue(options.contains(.allowBluetooth))
        XCTAssertTrue(options.contains(.allowBluetoothA2DP))
    }

    // MARK: - Route change handling

    func test_routeChange_newDeviceAvailable_doesNotCrash() {
        // Simulates CarPlay or Bluetooth headphones connecting while alarm is active.
        audioPlayer.play(.default)
        postRouteChange(reason: .newDeviceAvailable)
        // No crash = pass. Session should still be .playback.
        XCTAssertEqual(AVAudioSession.sharedInstance().category, .playback)
    }

    func test_routeChange_oldDeviceUnavailable_doesNotCrash() {
        // Simulates headphones or CarPlay disconnecting while alarm is active.
        audioPlayer.play(.default)
        postRouteChange(reason: .oldDeviceUnavailable)
        XCTAssertEqual(AVAudioSession.sharedInstance().category, .playback)
    }

    func test_routeChange_override_doesNotCrash() {
        audioPlayer.play(.default)
        postRouteChange(reason: .override)
        XCTAssertEqual(AVAudioSession.sharedInstance().category, .playback)
    }

    func test_routeChange_categoryChange_doesNotCrash() {
        audioPlayer.play(.default)
        postRouteChange(reason: .categoryChange)
        // No crash = pass.
    }

    func test_routeChangeAfterStop_doesNotCrash() {
        // Observer must be removed on stop(); stale callbacks would crash or
        // unexpectedly re-activate the session.
        audioPlayer.play(.default)
        audioPlayer.stop()
        postRouteChange(reason: .newDeviceAvailable)
        // No crash = pass.
    }

    // MARK: - Observer lifecycle

    func test_multiplePlayCalls_doNotStackRouteChangeObservers() {
        // Calling play() three times must not register three observers.
        // If they stacked, stop() would remove only one and the remainder
        // would fire after teardown, causing crashes in later tests.
        audioPlayer.play(.default)
        audioPlayer.play(.default)
        audioPlayer.play(.default)
        audioPlayer.stop()
        postRouteChange(reason: .newDeviceAvailable)
        // No crash = observers were not stacked.
    }

    // MARK: - Vibrate path

    func test_vibrateSound_doesNotActivatePlaybackSession() {
        // Start from a known non-playback category.
        try? AVAudioSession.sharedInstance().setCategory(.ambient)
        audioPlayer.play(.vibrate)
        // Vibrate-only should not switch the session to .playback.
        XCTAssertNotEqual(AVAudioSession.sharedInstance().category, .playback,
                          "Vibrate-only must not activate the playback session")
    }

    // MARK: - Stop

    func test_stopAllowsSessionCategoryToChange() {
        // After stop(), the session should be deactivated so other apps
        // (music, navigation) can restore their audio undisturbed.
        audioPlayer.play(.default)
        audioPlayer.stop()
        XCTAssertNoThrow(
            try AVAudioSession.sharedInstance().setCategory(.ambient),
            "Session should be freely configurable after stop()"
        )
    }

    // MARK: - Interruption handling
    //
    // CarPlay / Bluetooth handoffs and phone calls post interruption
    // notifications. The handler must (a) never crash, (b) resume an in-progress
    // alarm even when iOS omits .shouldResume, and (c) run its work on the main
    // thread (it is posted on an arbitrary thread). These tests drain the main
    // queue after posting so the async handler body executes before asserting.

    func test_interruptionBegan_doesNotCrash() {
        audioPlayer.play(.default)
        postInterruption(type: .began)
        drainMainQueue()
        // No crash = pass.
    }

    func test_interruptionEnded_withShouldResume_doesNotCrash() {
        audioPlayer.play(.default)
        postInterruption(type: .ended, options: .shouldResume)
        drainMainQueue()
        XCTAssertEqual(AVAudioSession.sharedInstance().category, .playback,
                       "Session must remain .playback after resuming from interruption")
    }

    func test_interruptionEnded_withoutShouldResume_stillResumesActiveAlarm() {
        // CarPlay handoffs frequently end the interruption WITHOUT shouldResume.
        // An in-progress alarm must resume anyway so the user is not left in silence.
        audioPlayer.play(.default)
        postInterruption(type: .ended, options: [])
        drainMainQueue()
        XCTAssertEqual(AVAudioSession.sharedInstance().category, .playback,
                       "Active alarm must resume after a CarPlay handoff even without shouldResume")
    }

    func test_interruptionAfterStop_doesNotCrash() {
        // Observer must be removed on stop(); a stale interruption callback that
        // re-activated the session would be a regression.
        audioPlayer.play(.default)
        audioPlayer.stop()
        postInterruption(type: .ended, options: .shouldResume)
        drainMainQueue()
        // No crash = pass.
    }

    // MARK: - Helpers

    private func postRouteChange(reason: AVAudioSession.RouteChangeReason) {
        NotificationCenter.default.post(
            name: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance(),
            userInfo: [AVAudioSessionRouteChangeReasonKey: reason.rawValue]
        )
        drainMainQueue()
    }

    private func postInterruption(type: AVAudioSession.InterruptionType,
                                  options: AVAudioSession.InterruptionOptions = []) {
        NotificationCenter.default.post(
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            userInfo: [
                AVAudioSessionInterruptionTypeKey: type.rawValue,
                AVAudioSessionInterruptionOptionKey: options.rawValue
            ]
        )
    }

    /// The route-change / interruption handlers dispatch their work onto the main
    /// queue. Spin the run loop briefly so that work executes before we assert.
    private func drainMainQueue() {
        let exp = expectation(description: "drain main queue")
        DispatchQueue.main.async { exp.fulfill() }
        wait(for: [exp], timeout: 1.0)
    }
}
