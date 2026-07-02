// AlarmSchedulingTests.swift
// Tests for scheduling features that had zero coverage:
//   • isWithinWindow  — time window (normal and overnight) and day-of-week filter
//   • activeDays      — bitmask encode/decode, isEveryDay, activeDaysLabel
//   • CLCircularRegion — entry + exit flags for repeating alarms
//   • AlarmManager    — exit alarm fires, multiple alarms, triggerCount,
//                       repeating alarm re-arm, unknown regionID,
//                       window-blocked alarm, note appended to SMS body

import XCTest
import CoreLocation
@testable import GeoNap

// MARK: - Time-Window Tests ────────────────────────────────────────────────────

/// Tests for NapAlarm.isWithinWindow(at:).
/// The method has two independent guards: (1) day-of-week, (2) time range.
/// Both must pass for the method to return true.
final class TimeWindowTests: XCTestCase {

    // MARK: No time window — always fires

    func test_noTimeWindow_alwaysTrue() {
        let alarm = makeAlarm()
        alarm.hasTimeWindow = false
        XCTAssertTrue(alarm.isWithinWindow(at: anyDate()),
                      "When hasTimeWindow is false, alarm must always fire")
    }

    // MARK: Normal window (start < end, e.g. 08:00 – 10:00)

    func test_normalWindow_insideRange_returnsTrue() {
        let alarm = windowAlarm(startH: 8, startM: 0, endH: 10, endM: 0)
        XCTAssertTrue(alarm.isWithinWindow(at: time(h: 9, m: 0)))
    }

    func test_normalWindow_atExactStart_returnsTrue() {
        let alarm = windowAlarm(startH: 8, startM: 0, endH: 10, endM: 0)
        XCTAssertTrue(alarm.isWithinWindow(at: time(h: 8, m: 0)))
    }

    func test_normalWindow_atExactEnd_returnsTrue() {
        let alarm = windowAlarm(startH: 8, startM: 0, endH: 10, endM: 0)
        XCTAssertTrue(alarm.isWithinWindow(at: time(h: 10, m: 0)))
    }

    func test_normalWindow_beforeStart_returnsFalse() {
        let alarm = windowAlarm(startH: 8, startM: 0, endH: 10, endM: 0)
        XCTAssertFalse(alarm.isWithinWindow(at: time(h: 7, m: 59)))
    }

    func test_normalWindow_afterEnd_returnsFalse() {
        let alarm = windowAlarm(startH: 8, startM: 0, endH: 10, endM: 0)
        XCTAssertFalse(alarm.isWithinWindow(at: time(h: 10, m: 1)))
    }

    func test_normalWindow_midnight_returnsFalse() {
        let alarm = windowAlarm(startH: 8, startM: 0, endH: 10, endM: 0)
        XCTAssertFalse(alarm.isWithinWindow(at: time(h: 0, m: 0)))
    }

    // MARK: Overnight window (start > end, e.g. 22:00 – 06:00)

    func test_overnightWindow_afterStartInSameDay_returnsTrue() {
        // 22:30 is after start (22:00) → in window
        let alarm = windowAlarm(startH: 22, startM: 0, endH: 6, endM: 0)
        XCTAssertTrue(alarm.isWithinWindow(at: time(h: 22, m: 30)))
    }

    func test_overnightWindow_beforeEndNextDay_returnsTrue() {
        // 05:45 is before end (06:00) → still in window
        let alarm = windowAlarm(startH: 22, startM: 0, endH: 6, endM: 0)
        XCTAssertTrue(alarm.isWithinWindow(at: time(h: 5, m: 45)))
    }

    func test_overnightWindow_atExactStart_returnsTrue() {
        let alarm = windowAlarm(startH: 22, startM: 0, endH: 6, endM: 0)
        XCTAssertTrue(alarm.isWithinWindow(at: time(h: 22, m: 0)))
    }

    func test_overnightWindow_atExactEnd_returnsTrue() {
        let alarm = windowAlarm(startH: 22, startM: 0, endH: 6, endM: 0)
        XCTAssertTrue(alarm.isWithinWindow(at: time(h: 6, m: 0)))
    }

    func test_overnightWindow_inGap_returnsFalse() {
        // 10:00 is between end (06:00) and start (22:00) — the gap
        let alarm = windowAlarm(startH: 22, startM: 0, endH: 6, endM: 0)
        XCTAssertFalse(alarm.isWithinWindow(at: time(h: 10, m: 0)))
    }

    func test_overnightWindow_justAfterEnd_returnsFalse() {
        let alarm = windowAlarm(startH: 22, startM: 0, endH: 6, endM: 0)
        XCTAssertFalse(alarm.isWithinWindow(at: time(h: 6, m: 1)))
    }

    // MARK: Day-of-week filter

    func test_activeDayFilter_blocksAlarmOnWrongDay() {
        let alarm = makeAlarm()
        alarm.hasTimeWindow = false
        // Monday only (weekday 2)
        alarm.activeDays = [2]
        // Feed a Sunday (weekday 1)
        let sunday = weekday(1)
        XCTAssertFalse(alarm.isWithinWindow(at: sunday),
                       "Alarm restricted to Monday must not fire on Sunday")
    }

    func test_activeDayFilter_allowsAlarmOnCorrectDay() {
        let alarm = makeAlarm()
        alarm.hasTimeWindow = false
        alarm.activeDays = [2]   // Monday only
        let monday = weekday(2)
        XCTAssertTrue(alarm.isWithinWindow(at: monday),
                      "Alarm restricted to Monday must fire on Monday")
    }

    func test_everyDay_alwaysAllowed() {
        let alarm = makeAlarm()
        alarm.hasTimeWindow = false
        alarm.activeDaysRaw = 127   // all days
        for wd in 1...7 {
            XCTAssertTrue(alarm.isWithinWindow(at: weekday(wd)),
                          "All-day alarm must fire on weekday \(wd)")
        }
    }

    // MARK: Combined day + time constraints

    func test_combined_correctDay_inWindow_returnsTrue() {
        let alarm = windowAlarm(startH: 7, startM: 0, endH: 9, endM: 0)
        // Weekdays only (Mon–Fri = 2–6)
        alarm.activeDays = Set(2...6)
        let tuesday8am = weekdayAtTime(weekday: 3, h: 8, m: 0)
        XCTAssertTrue(alarm.isWithinWindow(at: tuesday8am))
    }

    func test_combined_correctDay_outsideWindow_returnsFalse() {
        let alarm = windowAlarm(startH: 7, startM: 0, endH: 9, endM: 0)
        alarm.activeDays = Set(2...6)
        let tuesday11am = weekdayAtTime(weekday: 3, h: 11, m: 0)
        XCTAssertFalse(alarm.isWithinWindow(at: tuesday11am))
    }

    func test_combined_wrongDay_inWindow_returnsFalse() {
        let alarm = windowAlarm(startH: 7, startM: 0, endH: 9, endM: 0)
        alarm.activeDays = Set(2...6)   // weekdays only
        let saturday8am = weekdayAtTime(weekday: 7, h: 8, m: 0)
        XCTAssertFalse(alarm.isWithinWindow(at: saturday8am))
    }

    // MARK: - Helpers

    private func makeAlarm() -> NapAlarm {
        NapAlarm(name: "W", latitude: 40.0, longitude: -74.0)
    }

    /// Create a window alarm with the given 24-hour start/end.
    private func windowAlarm(startH: Int, startM: Int, endH: Int, endM: Int) -> NapAlarm {
        let alarm = makeAlarm()
        alarm.hasTimeWindow = true
        alarm.windowStart = time(h: startH, m: startM)
        alarm.windowEnd   = time(h: endH,   m: endM)
        return alarm
    }

    /// Date with a specific hour:minute on today's date, using the current Calendar.
    private func time(h: Int, m: Int) -> Date {
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        comps.hour   = h
        comps.minute = m
        comps.second = 0
        return Calendar.current.date(from: comps) ?? Date()
    }

    /// Date whose weekday number equals `wd` (1=Sun … 7=Sat). Time is noon.
    private func weekday(_ wd: Int) -> Date {
        var comps = Calendar.current.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
        comps.weekday = wd
        comps.hour = 12; comps.minute = 0; comps.second = 0
        return Calendar.current.date(from: comps) ?? Date()
    }

    /// Date with specific weekday and hour:minute.
    private func weekdayAtTime(weekday wd: Int, h: Int, m: Int) -> Date {
        var comps = Calendar.current.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
        comps.weekday = wd
        comps.hour = h; comps.minute = m; comps.second = 0
        return Calendar.current.date(from: comps) ?? Date()
    }

    private func anyDate() -> Date { Date() }
}

// MARK: - ActiveDays Bitmask Tests ────────────────────────────────────────────

final class ActiveDaysTests: XCTestCase {

    private func alarm() -> NapAlarm {
        NapAlarm(name: "D", latitude: 40.0, longitude: -74.0)
    }

    // MARK: Default

    func test_default_isEveryDay() {
        XCTAssertTrue(alarm().isEveryDay)
        XCTAssertEqual(alarm().activeDaysRaw, 127)
    }

    func test_default_activeDaysLabel_isNil() {
        XCTAssertNil(alarm().activeDaysLabel(locale: Locale(identifier: "en_US"), bundle: .main),
                     "All-day alarms must return nil label")
    }

    // MARK: Encode (Set → Int)

    func test_setWeekdays_storesBitmask62() {
        // Mon–Fri = weekdays 2–6; bits 1–5 set → 0b0111110 = 62
        let a = alarm()
        a.activeDays = Set(2...6)
        XCTAssertEqual(a.activeDaysRaw, 62)
    }

    func test_setWeekend_storesBitmask65() {
        // Sun=1 (bit 0) + Sat=7 (bit 6) → 0b1000001 = 65
        let a = alarm()
        a.activeDays = [1, 7]
        XCTAssertEqual(a.activeDaysRaw, 65)
    }

    func test_setAllDays_storesBitmask127() {
        let a = alarm()
        a.activeDays = Set(1...7)
        XCTAssertEqual(a.activeDaysRaw, 127)
    }

    func test_setEmpty_treatedAsAllDays() {
        // Empty set → 127 (all days) so the alarm always fires
        let a = alarm()
        a.activeDays = []
        XCTAssertEqual(a.activeDaysRaw, 127)
        XCTAssertTrue(a.isEveryDay)
    }

    // MARK: Decode (Int → Set)

    func test_bitmask62_decodesAsWeekdays() {
        let a = alarm()
        a.activeDaysRaw = 62
        XCTAssertEqual(a.activeDays, Set(2...6))
    }

    func test_bitmask65_decodesAsWeekend() {
        let a = alarm()
        a.activeDaysRaw = 65
        XCTAssertEqual(a.activeDays, [1, 7])
    }

    func test_bitmask127_decodesAsAllDays() {
        let a = alarm()
        a.activeDaysRaw = 127
        XCTAssertEqual(a.activeDays, Set(1...7))
    }

    // MARK: isEveryDay

    func test_isEveryDay_falseWhenSubset() {
        let a = alarm()
        a.activeDays = Set(2...6)
        XCTAssertFalse(a.isEveryDay)
    }

    func test_isEveryDay_trueWhenFullSetAssigned() {
        let a = alarm()
        a.activeDays = Set(1...7)
        XCTAssertTrue(a.isEveryDay)
    }

    // MARK: activeDaysLabel

    func test_activeDaysLabel_weekdays() {
        let a = alarm()
        a.activeDays = Set(2...6)
        XCTAssertEqual(a.activeDaysLabel(locale: Locale(identifier: "en_US"), bundle: .main), "Weekdays")
    }

    func test_activeDaysLabel_weekends() {
        let a = alarm()
        a.activeDays = [1, 7]
        XCTAssertEqual(a.activeDaysLabel(locale: Locale(identifier: "en_US"), bundle: .main), "Weekends")
    }

    func test_activeDaysLabel_customAbbreviations() {
        // Mon + Wed + Fri = weekdays 2, 4, 6
        let a = alarm()
        a.activeDays = [2, 4, 6]
        let label = a.activeDaysLabel(locale: Locale(identifier: "en_US"), bundle: .main) ?? ""
        XCTAssertTrue(label.contains("Mo"), "Label must contain Mo")
        XCTAssertTrue(label.contains("We"), "Label must contain We")
        XCTAssertTrue(label.contains("Fr"), "Label must contain Fr")
        XCTAssertFalse(label.contains("Tu"), "Label must not contain Tu")
    }

    func test_activeDaysLabel_nilWhenEveryDay() {
        let a = alarm()
        a.activeDaysRaw = 127
        XCTAssertNil(a.activeDaysLabel(locale: Locale(identifier: "en_US"), bundle: .main))
    }

    // MARK: Round-trip

    func test_roundTrip_weekdays() {
        let a = alarm()
        a.activeDays = Set(2...6)
        let raw = a.activeDaysRaw
        let b = alarm()
        b.activeDaysRaw = raw
        XCTAssertEqual(b.activeDays, Set(2...6))
    }
}

// MARK: - CLCircularRegion Repeating Tests ────────────────────────────────────

final class ClRegionRepeatingTests: XCTestCase {

    private func makeAlarm(event: RegionEvent, repeating: Bool) -> NapAlarm {
        NapAlarm(name: "R", latitude: 40.0, longitude: -74.0,
                 regionEvent: event, isRepeating: repeating)
    }

    func test_repeatingEntryAlarm_notifiesBothEntryAndExit() {
        // Repeating alarms must monitor BOTH directions so exit can re-arm.
        let alarm = makeAlarm(event: .onEntry, repeating: true)
        XCTAssertTrue(alarm.clRegion.notifyOnEntry, "Repeating entry alarm must notify on entry")
        XCTAssertTrue(alarm.clRegion.notifyOnExit,  "Repeating entry alarm must notify on exit to re-arm")
    }

    func test_repeatingExitAlarm_notifiesBothEntryAndExit() {
        let alarm = makeAlarm(event: .onExit, repeating: true)
        XCTAssertTrue(alarm.clRegion.notifyOnEntry, "Repeating exit alarm must notify on entry to re-arm")
        XCTAssertTrue(alarm.clRegion.notifyOnExit,  "Repeating exit alarm must notify on exit")
    }

    func test_nonRepeatingEntryAlarm_onlyNotifiesEntry() {
        let alarm = makeAlarm(event: .onEntry, repeating: false)
        XCTAssertTrue(alarm.clRegion.notifyOnEntry)
        XCTAssertFalse(alarm.clRegion.notifyOnExit)
    }

    func test_nonRepeatingExitAlarm_onlyNotifiesExit() {
        let alarm = makeAlarm(event: .onExit, repeating: false)
        XCTAssertFalse(alarm.clRegion.notifyOnEntry)
        XCTAssertTrue(alarm.clRegion.notifyOnExit)
    }
}

// MARK: - AlarmManager Region-Event Edge Cases ─────────────────────────────────

/// Supplements AlarmManagerTests with scenarios that were not covered:
/// exit alarm firing, multiple alarms, triggerCount, repeating re-arm,
/// unknown regionID (no-crash), time-window blocking, and note in SMS body.
@MainActor
final class AlarmManagerRegionEdgeCaseTests: XCTestCase {

    var sut: AlarmManager!

    override func setUp() {
        super.setUp()
        sut = AlarmManager()
    }

    override func tearDown() {
        sut = nil
        super.tearDown()
    }

    // MARK: Exit alarm actually fires

    func test_handleRegionExit_triggersOnExitAlarm() {
        // The existing suite only tests that EXIT does NOT trigger an onEntry alarm.
        // This test verifies that EXIT *does* trigger an onExit alarm.
        let alarm = NapAlarm(name: "Departure Stop", latitude: 40.7, longitude: -74.0,
                             regionEvent: .onExit, state: .active)
        sut.add(alarm: alarm)

        sut.simulateRegionExited(regionID: alarm.id.uuidString)

        XCTAssertEqual(sut.alarms.first?.state, .triggered,
                       "An active .onExit alarm must reach .triggered state when the region is exited")
    }

    func test_handleRegionEntry_doesNotTrigger_onExitAlarm() {
        let alarm = NapAlarm(name: "Departure Stop", latitude: 40.7, longitude: -74.0,
                             regionEvent: .onExit, state: .active)
        sut.add(alarm: alarm)

        sut.simulateRegionEntered(regionID: alarm.id.uuidString)

        XCTAssertEqual(sut.alarms.first?.state, .active,
                       "An .onExit alarm must not trigger on region entry")
    }

    // MARK: Multiple alarms — only the matching one fires

    func test_handleRegionEntry_onlyTriggersMatchingAlarm() {
        let target  = NapAlarm(name: "Target",  latitude: 40.7, longitude: -74.0,
                               regionEvent: .onEntry, state: .active)
        let bystander = NapAlarm(name: "Other", latitude: 40.8, longitude: -74.1,
                                 regionEvent: .onEntry, state: .active)
        sut.add(alarm: target)
        sut.add(alarm: bystander)

        sut.simulateRegionEntered(regionID: target.id.uuidString)

        let targetState    = sut.alarms.first(where: { $0.id == target.id })?.state
        let bystanderState = sut.alarms.first(where: { $0.id == bystander.id })?.state
        XCTAssertEqual(targetState,    .triggered, "Target alarm must be triggered")
        XCTAssertEqual(bystanderState, .active,    "Bystander alarm must remain active")
    }

    // MARK: triggerCount increments

    func test_handleRegionEntry_incrementsTriggerCount() {
        let alarm = NapAlarm(name: "Count Test", latitude: 40.7, longitude: -74.0,
                             regionEvent: .onEntry, state: .active)
        XCTAssertEqual(alarm.triggerCount, 0, "triggerCount must start at 0")
        sut.add(alarm: alarm)

        sut.simulateRegionEntered(regionID: alarm.id.uuidString)

        XCTAssertEqual(sut.alarms.first?.triggerCount, 1,
                       "triggerCount must increment to 1 after first fire")
    }

    // MARK: Repeating alarm re-arms on opposite event

    func test_repeatingEntryAlarm_rearmsOnExit() {
        let alarm = NapAlarm(name: "Commuter", latitude: 40.7, longitude: -74.0,
                             regionEvent: .onEntry, state: .active, isRepeating: true)
        sut.add(alarm: alarm)

        // Trigger the alarm
        sut.simulateRegionEntered(regionID: alarm.id.uuidString)
        XCTAssertEqual(sut.alarms.first?.state, .triggered)

        // User leaves the region — alarm must re-arm
        sut.simulateRegionExited(regionID: alarm.id.uuidString)
        XCTAssertEqual(sut.alarms.first?.state, .active,
                       "Repeating alarm must re-arm after the user exits the region")
    }

    func test_repeatingExitAlarm_rearmsOnEntry() {
        let alarm = NapAlarm(name: "Return Trip", latitude: 40.7, longitude: -74.0,
                             regionEvent: .onExit, state: .active, isRepeating: true)
        sut.add(alarm: alarm)

        sut.simulateRegionExited(regionID: alarm.id.uuidString)
        XCTAssertEqual(sut.alarms.first?.state, .triggered)

        sut.simulateRegionEntered(regionID: alarm.id.uuidString)
        XCTAssertEqual(sut.alarms.first?.state, .active,
                       "Repeating exit alarm must re-arm when the user re-enters the region")
    }

    func test_nonRepeatingAlarm_doesNotRearm() {
        let alarm = NapAlarm(name: "One-Shot", latitude: 40.7, longitude: -74.0,
                             regionEvent: .onEntry, state: .active, isRepeating: false)
        sut.add(alarm: alarm)

        sut.simulateRegionEntered(regionID: alarm.id.uuidString)
        XCTAssertEqual(sut.alarms.first?.state, .triggered)

        // Exiting must NOT re-arm a non-repeating alarm
        sut.simulateRegionExited(regionID: alarm.id.uuidString)
        XCTAssertEqual(sut.alarms.first?.state, .triggered,
                       "Non-repeating alarm must stay triggered after the opposite event")
    }

    // MARK: Unknown regionID — graceful no-op

    func test_handleRegionEntry_unknownRegionID_noStateChange() {
        let alarm = NapAlarm(name: "Real", latitude: 40.7, longitude: -74.0,
                             regionEvent: .onEntry, state: .active)
        sut.add(alarm: alarm)

        sut.simulateRegionEntered(regionID: UUID().uuidString)   // bogus ID

        XCTAssertEqual(sut.alarms.first?.state, .active,
                       "Unknown regionID must not change any alarm state")
    }

    func test_handleRegionEntry_emptyAlarmList_doesNotCrash() {
        // No alarms — must be a graceful no-op
        XCTAssertNoThrow(sut.simulateRegionEntered(regionID: UUID().uuidString))
    }

    // MARK: Time-window blocks alarm

    func test_handleRegionEntry_doesNotFire_outsideTimeWindow() throws {
        // Build an alarm whose window is 01:00–02:00, then fire it at noon.
        // isWithinWindow will return false → alarm stays active.
        let alarm = NapAlarm(
            name: "Night Train",
            latitude: 40.7, longitude: -74.0,
            regionEvent: .onEntry, state: .active,
            hasTimeWindow: true,
            windowStart: hhmm(1, 0),
            windowEnd:   hhmm(2, 0)
        )
        sut.add(alarm: alarm)

        // We can't feed a custom "now" to handleRegionEvent directly,
        // so we check that the alarm does NOT fire when the current real
        // time is outside 01:00–02:00. This test is meaningful only when
        // run outside that window. Skip gracefully during that hour.
        let hour = Calendar.current.component(.hour, from: Date())
        guard hour != 1 else {
            throw XCTSkip("Skipping window-block test: current hour is 01 (inside window)")
        }

        sut.simulateRegionEntered(regionID: alarm.id.uuidString)
        XCTAssertEqual(sut.alarms.first?.state, .active,
                       "Alarm outside its time window must not trigger")
    }

    // MARK: Auto-Notify body includes alarm note

    func test_autoNotify_smsBody_appendsNote_whenNonEmpty() {
        let alarm = NapAlarm(name: "Hotel Stop", latitude: 40.7, longitude: -74.0,
                             regionEvent: .onEntry, state: .active, note: "Check in today")
        alarm.notifyContact = true
        alarm.notifyContactList = [NotifyContact(name: "Mom", value: "+15551112222")]
        sut.add(alarm: alarm)

        sut.simulateRegionEntered(regionID: alarm.id.uuidString)

        let body = sut.pendingContactMessage?.body ?? ""
        XCTAssertTrue(body.contains("Check in today"),
                      "SMS body must include alarm note. Got: \(body)")
    }

    func test_autoNotify_smsBody_noExtraContent_whenNoteEmpty() {
        let alarm = NapAlarm(name: "Silent Stop", latitude: 40.7, longitude: -74.0,
                             regionEvent: .onEntry, state: .active, note: "")
        alarm.notifyContact = true
        alarm.notifyContactList = [NotifyContact(name: "Bob", value: "+15559998888")]
        sut.add(alarm: alarm)

        sut.simulateRegionEntered(regionID: alarm.id.uuidString)

        let body = sut.pendingContactMessage?.body ?? ""
        // Body should end with a period (no trailing note text)
        XCTAssertTrue(body.hasSuffix("."),
                      "SMS body without a note must end with a period. Got: \(body)")
    }

    // MARK: - Helpers

    /// Build a Date for today at the given hour and minute.
    private func hhmm(_ h: Int, _ m: Int) -> Date {
        var c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        c.hour = h; c.minute = m; c.second = 0
        return Calendar.current.date(from: c) ?? Date()
    }
}
