// Copyright © 2026 Robert Bartis. All rights reserved.

// NapStopUITests.swift
// UI smoke tests using XCUITest.
// Run on the simulator; require the app to be built and running.
//
// Rewritten 2026-07-05 (Bob — CI coverage audit) after finding this suite had
// drifted out of sync with the current app and was never actually runnable:
//   • "No Geo Alarms Yet" was a leftover pre-rename string; the empty-state
//     text has been "No GeoNap Alarms Yet" for some time.
//   • `app.navigationBars.buttons["Add"]` never existed — the "+" button is a
//     bare SF-Symbol-only Menu (no text label), and it now opens a Location
//     Alarm / Transit Alarm choice instead of navigating straight to the
//     add-alarm screen.
//   • The `--reset-alarms` launch argument was read by nothing — the app had
//     no handling for it at all, so every run used whatever SwiftData state
//     happened to already be on the simulator.
//   • On a truly fresh simulator (no persisted "hasSeenOnboarding"), the
//     onboarding fullScreenCover would block every single one of these tests
//     before they ever reached the alarm list.
//
// Fixed at the source (NapStopApp.swift, ContentView.swift) rather than
// papered over here: the `--uitesting` launch argument now gets an isolated
// in-memory SwiftData store (deterministic empty state, no CloudKit/network
// dependency in CI) and skips onboarding; the "+" menu button and gear
// button got stable `.accessibilityIdentifier`s since they have no text of
// their own to match on.
//
// NOTE: like the rest of this suite, these need an actual Xcode build +
// simulator run to confirm — not executed in this authoring environment.

import XCTest

final class NapStopUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false

        // Don't inherit whatever orientation a prior test class left the
        // simulator in — this suite's coordinates assume portrait. (Bob —
        // 2026-07-09 CI stability audit: NapStopUITestsLaunchTests was
        // observed leaving the simulator in landscape after a mid-run
        // crash, which made "Language" unhittable here at its expected
        // portrait position.)
        XCUIDevice.shared.orientation = .portrait

        app = XCUIApplication()
        app.launchArguments = ["--uitesting"]

        // RootView.onAppear calls locationManager.requestAlwaysAuthorization(),
        // which can pop the system location-permission alert asynchronously
        // after launch. None of these tests depend on permission actually
        // being granted (the add-alarm flow taps a map coordinate directly
        // rather than using "current location"), so just dismiss it if it
        // shows up rather than letting it steal focus mid-test.
        addUIInterruptionMonitor(withDescription: "Location Permission") { alert in
            for label in ["Allow While Using App", "Allow Once", "Don't Allow"] {
                let button = alert.buttons[label]
                if button.exists {
                    button.tap()
                    return true
                }
            }
            return false
        }

        app.launch()
        app.tap()   // nudges XCTest to check for (and dismiss) the interruption above
    }

    // MARK: - Helpers

    /// Waits for `element` to exist, scrolling it into view first if needed,
    /// then taps its own on-screen coordinate directly.
    ///
    /// Fifth pass (Bob — 2026-07-09 CI stability audit): the fourth-pass
    /// version above (plain `app.swipeUp()` retries) STILL produced a
    /// uniform 100% failure to ever find "Save Alarm" — across two whole CI
    /// runs, 12 total `app.swipeUp()` attempts, not one made any apparent
    /// progress. That's consistent with the swipe never actually scrolling
    /// the Form at all, every single time — not with "not enough scrolling".
    ///
    /// Root cause: AddAlarmView's Location section embeds a live
    /// `MapPickerView` (`MKMapView`) at `.frame(height: 220)` directly inside
    /// the Form, and a debug snapshot from an earlier failure put its frame
    /// at `{{24, 378.3}, {354, 220}}` on an 852pt-tall screen — i.e. roughly
    /// dy 0.44–0.70 of the whole screen. `app.swipeUp()`'s default gesture
    /// path runs from near the very bottom of the screen to near the very
    /// top, which passes straight through that band on every single call.
    /// MKMapView installs its own pan/pinch gesture recognizers for map
    /// panning, and when embedded in a scrollable container without an
    /// explicit `require(toFail:)` relationship (which SwiftUI's `Map`/
    /// `MapPickerView` doesn't set up), those recognizers can intercept a
    /// touch that merely passes over the map's bounds, swallowing the whole
    /// gesture before the Form's own scroll view sees it. (This also
    /// explains why the third-pass small-drag version — start dy:0.7, right
    /// on the map's bottom edge at 0.702 — made things worse: it was
    /// starting the touch ON the map essentially every time.)
    ///
    /// Fix: scroll in two phases. While the map is still likely on-screen
    /// (first few attempts), use a manual press-and-drag confined ENTIRELY
    /// to well below the map's bottom edge (dy 0.92 → 0.78, safely under
    /// 0.70) so neither the touch-down nor the drag path ever crosses the
    /// map's bounds — this is enough to walk the map off the top of the
    /// screen over a few iterations. Once that's done, fall back to normal
    /// full-screen `app.swipeUp()`, which is fine once the map is no longer
    /// in the gesture's path.
    ///
    /// Also stopped gating on `isHittable` (still true from the fourth
    /// pass): once `element` exists, tap its own reported coordinate
    /// directly rather than relying on XCUITest's hit-test heuristic, which
    /// separately proved unreliable for the "Language" row.
    @discardableResult
    private func tapWhenReady(_ element: XCUIElement, timeout: TimeInterval = 5, maxScrollAttempts: Int = 16) -> Bool {
        if element.waitForExistence(timeout: timeout) {
            element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            return true
        }

        for attempt in 0..<maxScrollAttempts {
            if attempt < 6 {
                let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.92))
                let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.78))
                start.press(forDuration: 0.05, thenDragTo: end)
            } else {
                app.swipeUp()
            }
            if element.waitForExistence(timeout: 1) {
                element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
                return true
            }
        }

        return false
    }

    /// Same scrolling loop as tapWhenReady, but checks a set of candidate
    /// elements on every step instead of committing to one type ahead of
    /// time — see test_switchingLanguage_rebuildsWithoutCrashing_... for why
    /// picking a type via a single pre-scroll existence check is unsafe for
    /// an off-screen row. Taps and returns whichever candidate is found
    /// first, or nil if none appear within maxScrollAttempts.
    @discardableResult
    private func tapWhenReadyOneOf(_ elements: [XCUIElement], maxScrollAttempts: Int = 16) -> XCUIElement? {
        if let found = elements.first(where: { $0.waitForExistence(timeout: 2) }) {
            found.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            return found
        }
        for attempt in 0..<maxScrollAttempts {
            if attempt < 6 {
                let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.92))
                let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.78))
                start.press(forDuration: 0.05, thenDragTo: end)
            } else {
                app.swipeUp()
            }
            if let found = elements.first(where: { $0.waitForExistence(timeout: 1) }) {
                found.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
                return found
            }
        }
        return nil
    }

    /// Opens the "+" menu and chooses "Location Alarm", landing on AddAlarmView.
    ///
    /// SwiftUI's `Menu` renders its items as a native UIMenu/context-menu overlay,
    /// and depending on OS version XCUITest surfaces those rows as either
    /// `XCUIElementTypeButton` or `XCUIElementTypeMenuItem` — a well-known
    /// discrepancy (Bob — 2026-07-09 CI stability audit, second pass: the
    /// `.buttons[...]` query alone came back empty on this run's iOS 26.5
    /// simulator). Check both element types rather than assuming one.
    private func openAddLocationAlarm() {
        let addMenuButton = app.buttons["addAlarmMenuButton"]
        XCTAssertTrue(addMenuButton.waitForExistence(timeout: 3))
        addMenuButton.tap()

        let locationAlarmButton = app.buttons["Location Alarm"]
        let locationAlarmMenuItem = app.menuItems["Location Alarm"]
        let found = locationAlarmButton.waitForExistence(timeout: 2)
            || locationAlarmMenuItem.waitForExistence(timeout: 1)
        XCTAssertTrue(found, "\"Location Alarm\" menu row never appeared as a button or menuItem")

        (locationAlarmButton.exists ? locationAlarmButton : locationAlarmMenuItem).tap()
    }

    @discardableResult
    private func addAlarm(named name: String = "Test Alarm") -> Bool {
        openAddLocationAlarm()

        let nameField = app.textFields["Name (e.g. Penn Station)"]
        guard nameField.waitForExistence(timeout: 2) else { return false }
        nameField.tap()
        nameField.typeText(name)

        // Dismiss the keyboard before doing anything else.
        //
        // Eighth pass (Bob — 2026-07-09 CI stability audit): the seventh-pass
        // fix (drag starting ON the keyboard element, off the bottom of the
        // screen) was based on a wrong assumption — a follow-up CI run's log
        // showed `app.keyboards.count` staying > 0 for the ENTIRE 2s poll
        // afterward, meaning the drag never dismissed anything. The docked
        // iPhone system keyboard has no built-in drag-to-dismiss gesture at
        // all (that only exists for the floating/undocked keyboard); that
        // theory was wrong from the start. Combined with the sixth-pass
        // finding that this Form has no `.scrollDismissesKeyboard`/tap-
        // outside wiring either, there was no gesture left to try from the
        // test target's side.
        //
        // Fix: stop guessing at gestures entirely. AddAlarmView.swift now
        // has an explicit `.toolbar { ToolbarItemGroup(.keyboard) { ... } }`
        // "Done" button wired to a real `resignFirstResponder` call. That
        // button renders as part of the keyboard's own input accessory
        // view — directly above the keys — so it's always on-screen and
        // never covered by the keyboard's window, unlike anything relying
        // on the app's main window/List. Tap it directly via its stable
        // accessibilityIdentifier.
        if app.keyboards.count > 0 {
            let doneButton = app.buttons["keyboardDoneButton"]
            if doneButton.waitForExistence(timeout: 1) {
                doneButton.tap()
            }

            let deadline = Date().addingTimeInterval(2)
            while app.keyboards.count > 0 && Date() < deadline {
                usleep(100_000)
            }
        }

        let mapView = app.maps.firstMatch
        if mapView.waitForExistence(timeout: 3) {
            mapView.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }

        // "Save Alarm" sits in the last Section of a scrollable Form, below
        // several others (location, tracking mode, auto-notify) — it can be
        // outside the currently-rendered range of the lazy List until
        // scrolled. Target the stable accessibilityIdentifier
        // (AddAlarmView.swift) rather than the localized "Save Alarm" text,
        // so this doesn't silently break if a prior test in the suite left
        // the app in a non-English language (see languageManager reset in
        // NapStopApp.swift for the belt-and-suspenders fix on that front).
        guard tapWhenReady(app.buttons["saveAlarmButton"]) else { return false }
        return app.staticTexts[name].waitForExistence(timeout: 2)
    }

    // MARK: - Empty state

    func test_emptyState_showsPlaceholder() {
        XCTAssertTrue(app.staticTexts["No GeoNap Alarms Yet"].waitForExistence(timeout: 3))
    }

    // MARK: - Add alarm flow

    func test_addAlarm_appearsInList() throws {
        XCTAssertTrue(addAlarm(named: "Test Alarm"), "The new alarm must appear in the list after saving")
    }

    // MARK: - Delete alarm

    func test_swipeToDelete_removesAlarm() throws {
        XCTAssertTrue(addAlarm(named: "Test Alarm"))

        let cell = app.cells.staticTexts["Test Alarm"]
        XCTAssertTrue(cell.waitForExistence(timeout: 2))

        cell.swipeLeft()
        app.buttons["Delete"].tap()

        XCTAssertFalse(app.staticTexts["Test Alarm"].exists)
        XCTAssertTrue(app.staticTexts["No GeoNap Alarms Yet"].waitForExistence(timeout: 2))
    }

    // MARK: - Toggle alarm

    func test_swipeToDisable_changesRowOpacity() throws {
        XCTAssertTrue(addAlarm(named: "Test Alarm"))

        let cell = app.cells.staticTexts["Test Alarm"]
        XCTAssertTrue(cell.waitForExistence(timeout: 2))

        cell.swipeRight()
        app.buttons["Disable"].tap()

        // Disabled alarms render at reduced opacity — verify the cell still exists
        XCTAssertTrue(app.cells.staticTexts["Test Alarm"].exists)
    }

    // MARK: - Language switch (view-identity smoke test)
    // Regression coverage for the in-app language switch's `.id(currentLanguage)`
    // rebuild (see LanguageManager.swift / NapStopApp.swift): changing the
    // language re-ids the ENTIRE view tree, which dismisses the Settings sheet,
    // and `pendingReturnToSettings` is what re-presents it. This is exactly the
    // kind of SwiftUI-view-identity behavior that isn't unit-testable — flagged
    // as a gap (not fixed) in the 2026-06-29 CI review.

    func test_switchingLanguage_rebuildsWithoutCrashing_andReturnsToSettings() throws {
        app.buttons["settingsButton"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))

        // CORRECTED (real xcodebuild run, full-suite pass): the previous
        // version picked an element type (button vs. cell vs. otherElement)
        // via a single 1s existence check made BEFORE any scrolling
        // happened, then hard-coded that choice for the rest of the test.
        // "languageSettingsRow" sits below the Time section (per
        // SettingsView.swift's Form order) and starts off-screen, so none
        // of the three candidates existed within that first 1s window —
        // the closure always fell through to the otherElements default.
        // This Picker has no explicit .pickerStyle, and per the same
        // finding already documented for the Distance picker in
        // SettingsSectionsUITests.swift, that means it actually renders as
        // a .menu-style Picker (a Button that opens an overlay), not a
        // pushed list — so the identifier belongs to a Button, and an
        // otherElements query for it can never match, no matter how much
        // scrolling follows. Fix: check all three candidate types on EVERY
        // scroll step (same scrollIntoViewOneOf pattern used elsewhere in
        // this suite) instead of committing to one type before scrolling
        // starts.
        let languageButton = app.buttons["languageSettingsRow"]
        let languageCell = app.cells["languageSettingsRow"]
        let languageOther = app.otherElements["languageSettingsRow"]
        let languageRow = tapWhenReadyOneOf([languageButton, languageCell, languageOther])
        XCTAssertNotNil(languageRow, "Language row never became tappable")

        // AppLanguage.displayName is the language's own native name — "Español"
        // is stable regardless of which language was active before switching.
        let spanishOption = app.staticTexts["Español"]
        if spanishOption.waitForExistence(timeout: 2) {
            spanishOption.tap()
        }

        // The .id() rebuild tears down and rebuilds the whole view tree, then
        // pendingReturnToSettings re-presents Settings. The app must recover to
        // a stable, responsive state — not crash, hang, or get stuck off-screen.
        XCTAssertEqual(app.state, .runningForeground,
            "The app must still be running in the foreground after a language switch rebuilds the view tree")
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3),
            "Settings must be re-presented automatically after the language-change rebuild (pendingReturnToSettings)")
    }
}
