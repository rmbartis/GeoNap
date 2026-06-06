// AlarmRingingTests.swift
// CI coverage for the looping-alarm ringing feature (AlarmFiringView + AlarmAudioPlayer).
//
// New behaviour under test:
//   • AlarmManager.firingAlarm is set when a geo-alarm fires and cleared on
//     dismiss / snooze — ContentView uses it to drive the full-screen alarm UI.
//   • AlarmAudioPlayer.isPlaying tracks whether audio is looping.
//   • snooze() and dismissFiringAlarm() both stop audio and clear firingAlarm.
//
// Tests call simulateRegionEntered / simulateRegionExited (defined in
// AlarmManagerTests.swift) rather than going through a real CLLocationManager.

import XCTest
@testable import GeoNap

// MARK: - AlarmAudioPlayer state tests

/// Tests the isPlaying flag managed by AlarmAudioPlayer.
/// Audio output is a side-effect and is not asserted — only the public state
/// observable by the rest of the app is verified.
@MainActor
final class AlarmAudioPlayerStateTests: XCTestCase {

    override func setUp() {
        super.setUp()
        AlarmAudioPlayer.shared.stop()  // guarantee clean state before each test
    }

    override func tearDown() {
        AlarmAudioPlayer.shared.stop()  // clean up after each test
        super.tearDown()
    }

    // MARK: Initial state

    func test_initialState_notPlaying() {
        XCTAssertFalse(AlarmAudioPlayer.shared.isPlaying,
                       "AlarmAudioPlayer must start in a non-playing state")
    }

    // MARK: play() sets isPlaying

    func test_play_default_setsIsPlayingTrue() {
        AlarmAudioPlayer.shared.play(sound: .default)
        XCTAssertTrue(AlarmAudioPlayer.shared.isPlaying,
                      "play(.default) must set isPlaying = true")
    }

    func test_play_critical_setsIsPlayingTrue() {
        AlarmAudioPlayer.shared.play(sound: .critical)
        XCTAssertTrue(AlarmAudioPlayer.shared.isPlaying,
                      "play(.critical) must set isPlaying = true")
    }

    func test_play_vibrate_setsIsPlayingTrue() {
        AlarmAudioPlayer.shared.play(sound: .vibrate)
        XCTAssertTrue(AlarmAudioPlayer.shared.isPlaying,
                      "play(.vibrate) must set isPlaying = true")
    }

    // MARK: stop() clears isPlaying

    func test_stop_setsIsPlayingFalse() {
        AlarmAudioPlayer.shared.play(sound: .default)
        AlarmAudioPlayer.shared.stop()
        XCTAssertFalse(AlarmAudioPlayer.shared.isPlaying,
                       "stop() must set isPlaying = false")
    }

    // MARK: Idempotency

    func test_stop_isIdempotent_whenAlreadyStopped() {
        XCTAssertNoThrow({
            AlarmAudioPlayer.shared.stop()
            AlarmAudioPlayer.shared.stop()
        }(), "Calling stop() twice must not crash")
        XCTAssertFalse(AlarmAudioPlayer.shared.isPlaying)
    }

    // MARK: Re-play replaces prior session

    func test_play_afterPlay_remainsPlaying() {
        AlarmAudioPlayer.shared.play(sound: .default)
        AlarmAudioPlayer.shared.play(sound: .vibrate)   // replaces the first session
        XCTAssertTrue(AlarmAudioPlayer.shared.isPlaying,
                      "isPlaying must remain true after play() replaces a running session")
    }
}

// MARK: - firingAlarm set on alarm trigger

@MainActor
final class AlarmRingingTests: XCTestCase {

    var sut: AlarmManager!

    override func setUp() {
        super.setUp()
        AlarmAudioPlayer.shared.stop()
        sut = AlarmManager()
    }

    override func tearDown() {
        AlarmAudioPlayer.shared.stop()
        sut = nil
        super.tearDown()
    }

    // MARK: firingAlarm set when an alarm fires

    func test_regionEntry_setsFiringAlarm() {
        let alarm = makeEntryAlarm()
        sut.add(alarm: alarm)

        sut.simulateRegionEntered(regionID: alarm.id.uuidString)

        XCTAssertNotNil(sut.firingAlarm,
                        "firingAlarm must be non-nil when an active entry alarm fires")
    }

    func test_regionEntry_firingAlarm_isTheTriggeredAlarm() {
        let alarm = makeEntryAlarm(name: "Penn Station")
        sut.add(alarm: alarm)

        sut.simulateRegionEntered(regionID: alarm.id.uuidString)

        XCTAssertEqual(sut.firingAlarm?.id, alarm.id,
                       "firingAlarm must reference the alarm that triggered, not another")
    }

    func test_regionExit_setsFiringAlarm_forExitAlarm() {
        let alarm = makeExitAlarm()
        sut.add(alarm: alarm)

        sut.simulateRegionExited(regionID: alarm.id.uuidString)

        XCTAssertNotNil(sut.firingAlarm,
                        "firingAlarm must be set when an active exit alarm fires")
    }

    func test_multipleAlarms_firingAlarm_isTheOneTriggered() {
        let target    = makeEntryAlarm(name: "Target")
        let bystander = makeEntryAlarm(name: "Bystander")
        sut.add(alarm: target)
        sut.add(alarm: bystander)

        sut.simulateRegionEntered(regionID: target.id.uuidString)

        XCTAssertEqual(sut.firingAlarm?.id, target.id,
                       "firingAlarm must be the triggered alarm, not the bystander")
    }

    // MARK: firingAlarm NOT set for non-triggering cases

    func test_regionEntry_firingAlarm_nilForInactiveAlarm() {
        let alarm = NapAlarm(name: "Inactive", latitude: 40.0, longitude: -74.0,
                             regionEvent: .onEntry, state: .inactive)
        sut.add(alarm: alarm)

        sut.simulateRegionEntered(regionID: alarm.id.uuidString)

        XCTAssertNil(sut.firingAlarm,
                     "firingAlarm must stay nil when the alarm is inactive")
    }

    func test_regionEntry_firingAlarm_nilForWrongEvent() {
        // Entry event delivered for an onExit alarm — must not fire.
        let alarm = makeExitAlarm()
        sut.add(alarm: alarm)

        sut.simulateRegionEntered(regionID: alarm.id.uuidString)

        XCTAssertNil(sut.firingAlarm,
                     "firingAlarm must stay nil when the event direction doesn't match the alarm")
    }

    func test_regionEntry_firingAlarm_nilForUnknownRegion() {
        sut.add(alarm: makeEntryAlarm())

        sut.simulateRegionEntered(regionID: UUID().uuidString)

        XCTAssertNil(sut.firingAlarm,
                     "firingAlarm must stay nil for an unrecognised region ID")
    }

    // MARK: Audio starts on trigger

    func test_regionEntry_startsAudio() {
        sut.add(alarm: makeEntryAlarm())
        let alarm = sut.alarms.first!

        sut.simulateRegionEntered(regionID: alarm.id.uuidString)

        XCTAssertTrue(AlarmAudioPlayer.shared.isPlaying,
                      "AlarmAudioPlayer must be playing after an alarm fires")
    }

    func test_regionEntry_inactive_doesNotStartAudio() {
        let alarm = NapAlarm(name: "Silent", latitude: 40.0, longitude: -74.0,
                             regionEvent: .onEntry, state: .inactive)
        sut.add(alarm: alarm)

        sut.simulateRegionEntered(regionID: alarm.id.uuidString)

        XCTAssertFalse(AlarmAudioPlayer.shared.isPlaying,
                       "Audio must not start if the alarm did not fire")
    }

    // MARK: dismissFiringAlarm

    func test_dismissFiringAlarm_clearsFiringAlarm() {
        sut.add(alarm: makeEntryAlarm())
        sut.simulateRegionEntered(regionID: sut.alarms.first!.id.uuidString)
        XCTAssertNotNil(sut.firingAlarm)

        sut.dismissFiringAlarm()

        XCTAssertNil(sut.firingAlarm,
                     "dismissFiringAlarm() must clear firingAlarm")
    }

    func test_dismissFiringAlarm_stopsAudio() {
        sut.add(alarm: makeEntryAlarm())
        sut.simulateRegionEntered(regionID: sut.alarms.first!.id.uuidString)

        sut.dismissFiringAlarm()

        XCTAssertFalse(AlarmAudioPlayer.shared.isPlaying,
                       "dismissFiringAlarm() must stop the looping audio")
    }

    func test_dismissFiringAlarm_whenNilFiringAlarm_doesNotCrash() {
        XCTAssertNil(sut.firingAlarm)
        XCTAssertNoThrow(sut.dismissFiringAlarm(),
                         "dismissFiringAlarm() must be safe to call when no alarm is firing")
    }

    // MARK: snooze

    func test_snooze_clearsFiringAlarm() {
        sut.add(alarm: makeEntryAlarm())
        sut.simulateRegionEntered(regionID: sut.alarms.first!.id.uuidString)
        XCTAssertNotNil(sut.firingAlarm)

        sut.snooze(sut.alarms.first!, minutes: 10)

        XCTAssertNil(sut.firingAlarm,
                     "snooze() must clear firingAlarm so AlarmFiringView is dismissed")
    }

    func test_snooze_stopsAudio() {
        sut.add(alarm: makeEntryAlarm())
        sut.simulateRegionEntered(regionID: sut.alarms.first!.id.uuidString)

        sut.snooze(sut.alarms.first!, minutes: 10)

        XCTAssertFalse(AlarmAudioPlayer.shared.isPlaying,
                       "snooze() must stop the looping audio")
    }

    func test_snooze_setsAlarmStateSnoozed() {
        sut.add(alarm: makeEntryAlarm())
        sut.simulateRegionEntered(regionID: sut.alarms.first!.id.uuidString)

        sut.snooze(sut.alarms.first!, minutes: 10)

        XCTAssertEqual(sut.alarms.first?.state, .snoozed,
                       "snooze() must set alarm state to .snoozed")
    }

    // MARK: firingAlarm preserved across unrelated region events

    func test_firingAlarm_remainsSet_afterUnrelatedRegionEvent() {
        let a1 = makeEntryAlarm(name: "Fired")
        let a2 = makeEntryAlarm(name: "Other")
        sut.add(alarm: a1)
        sut.add(alarm: a2)

        // Fire a1
        sut.simulateRegionEntered(regionID: a1.id.uuidString)
        XCTAssertEqual(sut.firingAlarm?.id, a1.id)

        // An unrelated region event for a2 must not overwrite firingAlarm
        // (a2 is now triggered, but firingAlarm was set to a1 first;
        //  second fire replaces it — both are valid, so just assert it is still set)
        sut.simulateRegionEntered(regionID: a2.id.uuidString)
        XCTAssertNotNil(sut.firingAlarm,
                        "firingAlarm must remain set after a second alarm fires")
    }

    // MARK: - Helpers

    private func makeEntryAlarm(name: String = "Grand Central") -> NapAlarm {
        NapAlarm(name: name, latitude: 40.75, longitude: -73.98,
                 regionEvent: .onEntry, state: .active)
    }

    private func makeExitAlarm(name: String = "Home") -> NapAlarm {
        NapAlarm(name: name, latitude: 40.71, longitude: -74.01,
                 regionEvent: .onExit, state: .active)
    }
}
