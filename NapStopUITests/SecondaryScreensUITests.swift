// Copyright © 2026 Robert Bartis. All rights reserved.

// SecondaryScreensUITests.swift
// Basic smoke coverage for the "ordinary" SwiftUI views that had zero
// automated coverage as of the 2026-08-09 test-coverage review: Settings'
// own rendering, HelpView, PrivacyView, AlarmDetailView, and
// CalendarScanSettingsView. Most of GeoNap's tier-gating behavior for these
// screens is already covered by TierGatingUITests.swift — this file exists
// purely to confirm each screen actually opens and renders its expected
// content, not to re-test gating.
//
// Deliberately shallow: these are read-only/navigation smoke tests (does the
// screen open, does its title/known content appear), not full interaction
// tests of every control on each screen — see PaywallUITests.swift and
// TierGatingUITests.swift for the deeper interaction coverage elsewhere.
//
// Same duplication-over-sharing pattern as the rest of this suite (own
// launch/helpers rather than inheriting NapStopUITests) — see
// TierGatingUITests.swift's header for the rationale.
//
// NOTE: like the rest of this suite, these need an actual Xcode build +
// simulator run to confirm — not executed in this authoring environment.

import XCTest

final class SecondaryScreensUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Helpers

    private func launch(tier: String) {
        app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--uitesting-tier", tier]

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
        app.tap()
    }

    @discardableResult
    private func scrollIntoView(_ element: XCUIElement, maxScrollAttempts: Int = 16) -> Bool {
        if element.waitForExistence(timeout: 2) { return true }
        for attempt in 0..<maxScrollAttempts {
            if attempt < 6 {
                let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.92))
                let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.78))
                start.press(forDuration: 0.05, thenDragTo: end)
            } else {
                app.swipeUp()
            }
            if element.waitForExistence(timeout: 1) { return true }
        }
        return false
    }

    /// Same scrolling loop as scrollIntoView, but checks a set of candidate
    /// elements on every step instead of just one — for rows where the
    /// underlying element type (Button vs. staticText vs. menuItem) can't be
    /// assumed ahead of time. Returns whichever candidate is found first, or
    /// nil if none appear within maxScrollAttempts.
    @discardableResult
    private func scrollIntoViewOneOf(_ elements: [XCUIElement], maxScrollAttempts: Int = 16) -> XCUIElement? {
        if let found = elements.first(where: { $0.waitForExistence(timeout: 2) }) { return found }
        for attempt in 0..<maxScrollAttempts {
            if attempt < 6 {
                let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.92))
                let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.78))
                start.press(forDuration: 0.05, thenDragTo: end)
            } else {
                app.swipeUp()
            }
            if let found = elements.first(where: { $0.waitForExistence(timeout: 1) }) { return found }
        }
        return nil
    }

    private func openSettings() {
        let settingsButton = app.buttons["settingsButton"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 3))
        settingsButton.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))
    }

    /// Mirrors NapStopUITests.addAlarm — duplicated rather than shared for
    /// the same reason TierGatingUITests.openAddLocationAlarm is (see that
    /// file's header): this suite's setUp deliberately diverges (tier passed
    /// per test).
    @discardableResult
    private func addAlarm(named name: String) -> Bool {
        let addMenuButton = app.buttons["addAlarmMenuButton"]
        XCTAssertTrue(addMenuButton.waitForExistence(timeout: 3))
        addMenuButton.tap()

        let locationAlarmButton = app.buttons["Location Alarm"]
        let locationAlarmMenuItem = app.menuItems["Location Alarm"]
        let found = locationAlarmButton.waitForExistence(timeout: 2) || locationAlarmMenuItem.waitForExistence(timeout: 1)
        XCTAssertTrue(found)
        (locationAlarmButton.exists ? locationAlarmButton : locationAlarmMenuItem).tap()

        let nameField = app.textFields["Name (e.g. Penn Station)"]
        guard nameField.waitForExistence(timeout: 2) else { return false }
        nameField.tap()
        nameField.typeText(name)

        if app.keyboards.count > 0 {
            let doneButton = app.buttons["keyboardDoneButton"]
            if doneButton.waitForExistence(timeout: 1) { doneButton.tap() }
        }

        let mapView = app.maps.firstMatch
        if mapView.waitForExistence(timeout: 3) {
            mapView.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }

        guard scrollIntoView(app.buttons["saveAlarmButton"]) else { return false }
        app.buttons["saveAlarmButton"].tap()
        return app.staticTexts[name].waitForExistence(timeout: 2)
    }

    // MARK: - SettingsView renders its own content

    func test_settings_helpAndPrivacyRows_andAboutSectionRender() throws {
        launch(tier: "Free")
        openSettings()

        XCTAssertTrue(scrollIntoView(app.staticTexts["Help & User Guide"]),
                      "Help & User Guide row must render in Settings.")
        // Same lazy-row-materialization flakiness as the "Disable alarm" row
        // in test_alarmList_tapRow_... below — a plain waitForExistence
        // right after scrolling to a neighboring row isn't reliable, so use
        // scrollIntoView for every row assertion in this test, not just the
        // ones scrollIntoView was already wrapping.
        XCTAssertTrue(scrollIntoView(app.staticTexts["Privacy & Location Sharing"]),
                      "Privacy & Location Sharing row must render in Settings.")

        XCTAssertTrue(scrollIntoView(app.staticTexts["About"]), "About section header must render.")
        XCTAssertTrue(scrollIntoView(app.staticTexts["Build"]), "Build row must render under About.")
    }

    // MARK: - HelpView

    func test_settings_helpRow_opensHelpView_showsContent() throws {
        launch(tier: "Free")
        openSettings()

        let helpRow = app.staticTexts["Help & User Guide"]
        XCTAssertTrue(scrollIntoView(helpRow))
        helpRow.tap()

        XCTAssertTrue(app.navigationBars["Help"].waitForExistence(timeout: 3), "HelpView must present with title \"Help\".")
        XCTAssertTrue(app.staticTexts["What is GeoNap?"].waitForExistence(timeout: 2),
                      "HelpView's first section must render.")
    }

    // MARK: - PrivacyView

    func test_settings_privacyRow_opensPrivacyView_showsContent() throws {
        launch(tier: "Free")
        openSettings()

        let privacyRow = app.staticTexts["Privacy & Location Sharing"]
        XCTAssertTrue(scrollIntoView(privacyRow))
        privacyRow.tap()

        XCTAssertTrue(app.navigationBars["Privacy & Location"].waitForExistence(timeout: 3),
                      "PrivacyView must present with title \"Privacy & Location\".")
        XCTAssertTrue(app.staticTexts["Location Data"].waitForExistence(timeout: 2),
                      "PrivacyView's Location Data section must render.")
    }

    // MARK: - AlarmDetailView

    func test_alarmList_tapRow_opensAlarmDetailView_showsStatusAndActions() throws {
        launch(tier: "Free")
        XCTAssertTrue(addAlarm(named: "Detail Test Alarm"))

        app.staticTexts["Detail Test Alarm"].tap()

        XCTAssertTrue(app.navigationBars["Detail Test Alarm"].waitForExistence(timeout: 3),
                      "AlarmDetailView must present with the alarm's own name as its title.")
        XCTAssertTrue(scrollIntoView(app.staticTexts["Status"]), "Status section header must render.")
        XCTAssertTrue(scrollIntoView(app.staticTexts["Edit Alarm"]), "Edit Alarm action must be present.")

        // CORRECTED AGAIN (real xcodebuild run, third time): even accepting
        // either label, the assertion still failed — this time neither
        // "Disable alarm" nor "Enable alarm" was ever found as a staticText,
        // across 20 combined scroll attempts, despite "Edit Alarm" (the row
        // directly above it) rendering fine as a staticText two lines
        // earlier in this same run. The difference: "Edit Alarm" is a
        // NavigationLink, but this toggle is a plain
        // `Button { } label: { Text(...) } }` (see AlarmDetailView.swift,
        // Actions section) — XCUITest folds a bare Button's Text-only label
        // into the Button's own accessibilityLabel, it does not also expose
        // a separate staticText child. Same button-vs-staticText ambiguity
        // as the Metric picker option and the "Location Alarm" menu button
        // elsewhere in this suite — check buttons, falling back to
        // staticTexts in case some render pathway differs.
        let disableButton = app.buttons["Disable alarm"]
        let enableButton = app.buttons["Enable alarm"]
        let disableText = app.staticTexts["Disable alarm"]
        let enableText = app.staticTexts["Enable alarm"]
        let disableCandidates = [disableButton, disableText]
        let enableCandidates = [enableButton, enableText]

        let sawDisable = scrollIntoViewOneOf(disableCandidates, maxScrollAttempts: 10) != nil
        let sawEnable = !sawDisable && scrollIntoViewOneOf(enableCandidates, maxScrollAttempts: 10) != nil
        XCTAssertTrue(sawDisable || sawEnable,
                      "The Actions section must show either \"Disable alarm\" or \"Enable alarm\" for a saved alarm.")

        let toggleElement = sawDisable
            ? (disableButton.exists ? disableButton : disableText)
            : (enableButton.exists ? enableButton : enableText)
        toggleElement.tap()

        let flippedCandidates = sawDisable ? enableCandidates : disableCandidates
        XCTAssertTrue(flippedCandidates.contains(where: { $0.waitForExistence(timeout: 2) }),
                      "Tapping the toggle action must flip its label — confirms the row is wired to alarm.isActive, not a static string.")
    }

    // MARK: - CalendarScanSettingsView (Platinum-gated entry point)

    func test_settings_calendarScanningRow_opensAtPlatinumTier() throws {
        launch(tier: "Platinum")
        openSettings()

        let row = app.cells["calendarScanningRow"].exists
            ? app.cells["calendarScanningRow"]
            : app.buttons["calendarScanningRow"]
        XCTAssertTrue(scrollIntoView(row), "Calendar Scanning row must be visible at Platinum.")
        row.tap()

        XCTAssertTrue(app.navigationBars["Calendar Scanning"].waitForExistence(timeout: 3),
                      "CalendarScanSettingsView must present with title \"Calendar Scanning\".")
    }
}
