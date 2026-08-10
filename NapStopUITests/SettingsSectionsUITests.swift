// Copyright © 2026 Robert Bartis. All rights reserved.

// SettingsSectionsUITests.swift
// Added 2026-08-09 as part of a full test-coverage pass. SettingsView.swift
// is ~985 lines with a dozen distinct Form sections; existing coverage
// (TierGatingUITests.swift, SecondaryScreensUITests.swift, PaywallUITests.swift)
// each exercise one or two specific rows/gates, but nothing confirms the
// screen as a whole actually renders every section — a section silently
// failing to appear (a bad `if`, a crash-on-appear in one section's body)
// wouldn't be caught by any of those narrower tests. This file closes that
// gap with one broad render-smoke test, plus one real interaction test for
// the Units picker that wasn't covered anywhere else.
//
// Deliberately excludes the DEBUG-only "Tier Simulation" section — that
// section only exists in DEBUG builds (see SettingsView.swift's own #if
// DEBUG guard) and coupling a test to build configuration isn't worth it
// for a section that's developer tooling, not shipped UI.
//
// Same duplication-over-sharing pattern as the rest of this suite.
//
// NOTE: like the rest of this suite, these need an actual Xcode build +
// simulator run to confirm — not executed in this authoring environment.

import XCTest

final class SettingsSectionsUITests: XCTestCase {

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
    private func scrollIntoView(_ element: XCUIElement, maxScrollAttempts: Int = 20) -> Bool {
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

    private func openSettings() {
        let settingsButton = app.buttons["settingsButton"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 3))
        settingsButton.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))
    }

    /// Mirrors NapStopUITests.tapWhenReady — the "Distance" row's label is a
    /// SettingInfoLabel, which nests its own ⓘ info Button inside this
    /// Picker's tappable Form row. That's the exact same nested-interactive-
    /// control layout NapStopUITests.tapWhenReady's doc comment documents as
    /// making `app.staticTexts["Language"]`'s `isHittable` unreliable for
    /// languageSettingsRow — so this taps the element's own reported
    /// coordinate directly rather than trusting XCUITest's hit-test
    /// heuristic, same fix, same reason.
    @discardableResult
    private func tapWhenReady(_ element: XCUIElement, timeout: TimeInterval = 3) -> Bool {
        guard scrollIntoView(element) else { return false }
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        return true
    }

    /// Same button/menuItem/staticText fallback pattern as the Distance-row
    /// tap below — factored out so the distance-unit-picker test can select
    /// an explicit unit twice (once to force a known starting state, once to
    /// switch away from it) without duplicating the three-way lookup.
    @discardableResult
    private func selectDistanceUnitOption(_ label: String) -> Bool {
        let button = app.buttons[label]
        let menuItem = app.menuItems[label]
        let text = app.staticTexts[label]
        let found = button.waitForExistence(timeout: 2) || menuItem.waitForExistence(timeout: 1) || text.waitForExistence(timeout: 1)
        guard found else { return false }
        (button.exists ? button : (menuItem.exists ? menuItem : text)).tap()
        return true
    }

    // MARK: - Every section renders

    func test_settings_everySectionHeaderRenders() throws {
        // Free tier deliberately — every section here uses the "visible but
        // disabled" tier-gating pattern (TierGatedModifier), so section
        // headers themselves must render regardless of tier; this isn't
        // re-testing gating, just that the sections exist at all.
        launch(tier: "Free")
        openSettings()

        // Headers are listed top-to-bottom matching the Form's actual order
        // in SettingsView.swift, so each scrollIntoView only has to travel
        // forward — mirrors how NapStopUITests/TierGatingUITests scroll.
        let expectedHeadersInOrder = [
            "Plan",                          // settings.upgrade.sectionTitle
            "Units",
            "Alarm Trigger",
            "Time",
            "Auto-Notify Defaults",
            "Auto-SMS (No Approval Needed)",
            "Transit Feed Cache",
            "Support",
            "About",
            "Preview",
        ]

        for header in expectedHeadersInOrder {
            XCTAssertTrue(scrollIntoView(app.staticTexts[header]),
                          "Settings section header \"\(header)\" must render.")
        }
    }

    // MARK: - Distance unit picker actually changes displayed output

    func test_settings_distanceUnitPicker_updatesPreviewSampleRadius() throws {
        launch(tier: "Free")
        openSettings()

        // CORRECTED (real xcodebuild run, full-suite pass): this used to
        // just assert "1640 ft" on the assumption that Imperial is always
        // the default. DistanceUnit is stored via @AppStorage/UserDefaults,
        // which — unlike the SwiftData store (wiped every launch by
        // ModelContainerFactory.makeInMemory under --uitesting) — PERSISTS
        // across app relaunches on the same simulator. When this test had
        // already run once earlier on the same simulator (e.g. a prior
        // filtered run), the unit was left set to Metric, and "default is
        // Imperial" was false from the very first assertion. Force a known
        // unit explicitly before asserting on it, rather than trusting
        // whatever UserDefaults happens to already contain — makes the test
        // repeatable regardless of simulator history.
        XCTAssertTrue(tapWhenReady(app.staticTexts["Distance"]), "Distance row never became tappable.")
        XCTAssertTrue(selectDistanceUnitOption("Imperial (ft / mi)"), "Imperial option must appear after tapping the Distance row.")

        // Preview is the LAST section in the Form (Units, which contains
        // "Distance", is near the top) — scrollIntoView only ever scrolls
        // forward/down, so once we've scrolled all the way down to Preview
        // to check this, there is no way to scroll back up to reach
        // "Distance" again. Close and reopen Settings between the two
        // checks to reset the Form's scroll position to the top, rather
        // than trying to scroll backward.
        XCTAssertTrue(scrollIntoView(app.staticTexts["Sample radius"]))
        XCTAssertTrue(app.staticTexts["1640 ft"].waitForExistence(timeout: 2),
                      "After explicitly selecting Imperial, sample radius must read \"1640 ft\".")

        let doneButton = app.navigationBars["Settings"].buttons["Done"]
        XCTAssertTrue(doneButton.waitForExistence(timeout: 2))
        doneButton.tap()
        openSettings()

        // Use tapWhenReady (coordinate tap), not a plain .tap() — see that
        // helper's doc comment.
        XCTAssertTrue(tapWhenReady(app.staticTexts["Distance"]), "Distance row never became tappable.")

        // CORRECTED (real xcodebuild run, Xcode 26.6/iOS 26.5 SDK): this
        // Picker has no explicit .pickerStyle, and the original assumption
        // here — that it renders as a navigation-link push to a full-screen
        // list, the same as the Language row — turned out to be wrong for
        // this SDK/context. Tapping "Distance" never pushed a new
        // NavigationBar and "Metric (m / km)" never appeared as a
        // staticText no matter how long the test waited; the real failure
        // was "Metric option must appear in the pushed picker list", which
        // only makes sense if there's no pushed list at all — i.e. this
        // renders as a .menu-style Picker (a dropdown/context-menu overlay)
        // instead, whose options surface as buttons, not static text. This
        // is the exact same button-vs-menuItem-vs-staticText ambiguity
        // addAlarm() above already works around for the "Location Alarm"
        // row — same fallback pattern here rather than assuming one
        // element type.
        XCTAssertTrue(selectDistanceUnitOption("Metric (m / km)"), "Metric option must appear after tapping the Distance row.")

        // Whether this was a pushed list (auto-pops on selection) or a menu
        // overlay (dismisses itself), no manual back-navigation is needed
        // either way. Deliberately NOT tapping
        // navigationBars.buttons.element(boundBy: 0) here: Settings' only
        // toolbar button is the .confirmationAction "Done" button (no
        // leading button), so that query would risk hitting Done and
        // dismissing the whole Settings sheet instead of a nonexistent back
        // button.
        XCTAssertTrue(scrollIntoView(app.staticTexts["Sample radius"]))
        XCTAssertTrue(app.staticTexts["500 m"].waitForExistence(timeout: 2),
                      "After switching to Metric, sample radius must read \"500 m\" — confirms the picker actually drives DistanceUnit.formatted(meters:), not just its own selection state.")
    }
}
