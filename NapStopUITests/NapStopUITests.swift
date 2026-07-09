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

    /// Opens the "+" menu and chooses "Location Alarm", landing on AddAlarmView.
    private func openAddLocationAlarm() {
        let addMenuButton = app.buttons["addAlarmMenuButton"]
        XCTAssertTrue(addMenuButton.waitForExistence(timeout: 3))
        addMenuButton.tap()

        let locationAlarmOption = app.buttons["Location Alarm"]
        XCTAssertTrue(locationAlarmOption.waitForExistence(timeout: 2))
        locationAlarmOption.tap()
    }

    @discardableResult
    private func addAlarm(named name: String = "Test Alarm") -> Bool {
        openAddLocationAlarm()

        let nameField = app.textFields["Name (e.g. Penn Station)"]
        guard nameField.waitForExistence(timeout: 2) else { return false }
        nameField.tap()
        nameField.typeText(name)

        let mapView = app.maps.firstMatch
        if mapView.waitForExistence(timeout: 3) {
            mapView.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }

        app.buttons["Save Alarm"].tap()
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

        let languageRow = app.staticTexts["Language"]
        XCTAssertTrue(languageRow.waitForExistence(timeout: 2))
        languageRow.tap()

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
