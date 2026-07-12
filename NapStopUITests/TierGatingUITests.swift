// Copyright © 2026 Robert Bartis. All rights reserved.

// TierGatingUITests.swift
// XCUITest coverage for the "visible but disabled" tier-gating pattern
// (TierGatedModifier.swift), added 2026-07-11.
//
// Unlike NapStopUITests, this suite does NOT launch the app from a shared
// setUpWithError() — the simulated tier has to be chosen BEFORE launch (via
// the --uitesting-tier launch argument, parsed in NapStopApp.init() into
// EntitlementManager.testOverride — see EntitlementManager.swift), and it
// differs per test method. Each test calls launch(tier:) itself instead.
//
// Extended 2026-07-11 (same day) to cover the full-app tier gating pass —
// Auto-Notify, Trigger Mode, Transit Alarms, Sound library, Calendar
// Scanning, and the Free-tier alarm cap — alongside the original Run
// Shortcut coverage. Each new gate gets one representative "locked at the
// tier below" + "unlocked at the required tier" pair rather than testing
// every AppTier case in the UI layer — TierGatingFeatureTests.swift and
// RunAlarmShortcutTests.swift already cover the exhaustive per-tier
// combinations at the unit level; these UI tests exist to confirm the
// actual rendered/interactive state matches what the unit tests assert
// about the underlying data, not to re-derive the same matrix twice.
//
// NOTE: like the rest of this suite, these need an actual Xcode build +
// simulator run to confirm — not executed in this authoring environment.

import XCTest

final class TierGatingUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Helpers

    /// Launches with a specific simulated tier. See NapStopApp.init() /
    /// EntitlementManager.parseTierLaunchArgument(from:) for how the
    /// "--uitesting-tier <name>" argument is consumed.
    private func launch(tier: String) {
        app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--uitesting-tier", tier]

        // Same dismissal as NapStopUITests — none of these tests depend on
        // location permission actually being granted.
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

    /// Mirrors NapStopUITests.openAddLocationAlarm() — duplicated rather
    /// than shared, since this suite's setUp deliberately diverges (no
    /// fixed launch in setUp, tier passed per test) and inheriting from
    /// NapStopUITests would be misleading about that difference.
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

    /// Scrolls the Run Shortcut field into view without tapping it — these
    /// tests only need visibility + enabled/disabled state. Mirrors
    /// NapStopUITests.tapWhenReady's map-avoidance drag (see that file's
    /// header for why a plain swipeUp() alone is unsafe on this Form) minus
    /// the final tap.
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

    /// The lock/tier badge renders via SwiftUI's `Label`, which — like the
    /// Menu rows and Picker rows elsewhere in this app — doesn't reliably
    /// surface as one specific XCUIElementType across OS versions. Check
    /// several rather than assuming one (same defensive pattern as
    /// NapStopUITests.openAddLocationAlarm/languageRow).
    private func lockBadgeExists(tier: String) -> Bool {
        let identifier = "tierGatedLock.\(tier.lowercased())"
        return app.staticTexts[identifier].waitForExistence(timeout: 1)
            || app.otherElements[identifier].waitForExistence(timeout: 1)
            || app.images[identifier].waitForExistence(timeout: 1)
    }

    /// A Form/Section row built from a plain HStack (rather than a Button or
    /// Toggle) — e.g. activeDaysRow, soundPickerCollapsedRow, soundRow.* —
    /// commonly surfaces as XCUIElementTypeCell rather than
    /// XCUIElementTypeOther once it's inside a Form, especially when it also
    /// contains a nested interactive Button (the day buttons inside
    /// activeDaysRow; the preview Button inside soundPickerCollapsedRow/
    /// soundRow.*). Querying app.otherElements[...] alone for these missed
    /// every one of them regardless of tier (caught in CI, 2026-07-11/12) —
    /// same root cause NapStopUITests.languageRow already documented and
    /// worked around for languageSettingsRow. Fall back through
    /// button → cell → otherElements rather than assuming one element type.
    private func formRow(_ identifier: String) -> XCUIElement {
        let button = app.buttons[identifier]
        if button.waitForExistence(timeout: 1) { return button }
        let cell = app.cells[identifier]
        if cell.waitForExistence(timeout: 1) { return cell }
        return app.otherElements[identifier]
    }

    // MARK: - Run Shortcut field: visible but disabled below Gold

    func test_freeTier_runShortcutFieldVisibleButDisabled() throws {
        launch(tier: "Free")
        openAddLocationAlarm()

        let field = app.textFields["runShortcutNameField"]
        XCTAssertTrue(scrollIntoView(field), "Run Shortcut field must still be VISIBLE on Free tier — gated controls are disabled, never hidden.")
        XCTAssertFalse(field.isEnabled, "Run Shortcut field must be disabled below Gold tier.")
        XCTAssertTrue(lockBadgeExists(tier: "gold"), "A lock/tier badge naming the required tier must be visible next to the disabled field.")
    }

    func test_standardTier_runShortcutFieldVisibleButDisabled() throws {
        launch(tier: "Standard")
        openAddLocationAlarm()

        let field = app.textFields["runShortcutNameField"]
        XCTAssertTrue(scrollIntoView(field))
        XCTAssertFalse(field.isEnabled)
        XCTAssertTrue(lockBadgeExists(tier: "gold"))
    }

    func test_silverTier_runShortcutFieldVisibleButDisabled() throws {
        launch(tier: "Silver")
        openAddLocationAlarm()

        let field = app.textFields["runShortcutNameField"]
        XCTAssertTrue(scrollIntoView(field))
        XCTAssertFalse(field.isEnabled)
        XCTAssertTrue(lockBadgeExists(tier: "gold"))
    }

    func test_goldTier_runShortcutFieldEnabled_noLockBadge() throws {
        launch(tier: "Gold")
        openAddLocationAlarm()

        let field = app.textFields["runShortcutNameField"]
        XCTAssertTrue(scrollIntoView(field))
        XCTAssertTrue(field.isEnabled, "Run Shortcut field must be enabled at Gold tier.")
        XCTAssertFalse(lockBadgeExists(tier: "gold"), "No lock badge should render once the required tier is met.")

        // Confirm it's genuinely usable, not just reporting isEnabled==true.
        field.tap()
        field.typeText("Welcome Home")
        XCTAssertEqual(field.value as? String, "Welcome Home")
    }

    // MARK: - Auto-Notify toggle: Free disabled, Standard+ enabled

    func test_freeTier_autoNotifyToggleDisabled() throws {
        launch(tier: "Free")
        openAddLocationAlarm()

        let toggle = app.switches["autoNotifyToggle"]
        XCTAssertTrue(scrollIntoView(toggle), "Auto-Notify toggle must still be visible on Free tier.")
        XCTAssertFalse(toggle.isEnabled, "Auto-Notify must be disabled on Free tier — contact notify starts at Standard.")
        XCTAssertTrue(lockBadgeExists(tier: "standard"))
    }

    func test_standardTier_autoNotifyToggleEnabled() throws {
        launch(tier: "Standard")
        openAddLocationAlarm()

        let toggle = app.switches["autoNotifyToggle"]
        XCTAssertTrue(scrollIntoView(toggle))
        XCTAssertTrue(toggle.isEnabled, "Auto-Notify must be enabled at Standard+.")
        XCTAssertFalse(lockBadgeExists(tier: "standard"))
    }

    // MARK: - Active time window toggle: Free disabled, Standard+ enabled

    func test_freeTier_activeTimeWindowToggleDisabled() throws {
        launch(tier: "Free")
        openAddLocationAlarm()

        let toggle = app.switches["activeTimeWindowToggle"]
        XCTAssertTrue(scrollIntoView(toggle), "Active time window toggle must still be visible on Free tier.")
        XCTAssertFalse(toggle.isEnabled, "Active time window requires Standard+.")
        XCTAssertTrue(lockBadgeExists(tier: "standard"))
    }

    func test_standardTier_activeTimeWindowToggleEnabled() throws {
        launch(tier: "Standard")
        openAddLocationAlarm()

        let toggle = app.switches["activeTimeWindowToggle"]
        XCTAssertTrue(scrollIntoView(toggle))
        XCTAssertTrue(toggle.isEnabled, "Active time window must be usable at Standard+.")
        XCTAssertFalse(lockBadgeExists(tier: "standard"))
    }

    // MARK: - Repeat toggle + Active Days: Standard disabled, Silver+ enabled

    func test_standardTier_repeatAndActiveDaysDisabled() throws {
        launch(tier: "Standard")
        openAddLocationAlarm()

        let repeatToggle = app.switches["repeatToggle"]
        XCTAssertTrue(scrollIntoView(repeatToggle), "Repeat toggle must still be visible on Standard tier.")
        XCTAssertFalse(repeatToggle.isEnabled, "Repeat requires Silver+.")
        XCTAssertTrue(lockBadgeExists(tier: "silver"))

        let activeDaysRow = formRow("activeDaysRow")
        XCTAssertTrue(scrollIntoView(activeDaysRow), "Active Days row must still be visible on Standard tier.")
        XCTAssertFalse(activeDaysRow.isEnabled, "Active Days requires Silver+.")
    }

    func test_silverTier_repeatAndActiveDaysEnabled() throws {
        launch(tier: "Silver")
        openAddLocationAlarm()

        let repeatToggle = app.switches["repeatToggle"]
        XCTAssertTrue(scrollIntoView(repeatToggle))
        XCTAssertTrue(repeatToggle.isEnabled, "Repeat must be usable at Silver+.")
        XCTAssertFalse(lockBadgeExists(tier: "silver"))

        let activeDaysRow = formRow("activeDaysRow")
        XCTAssertTrue(scrollIntoView(activeDaysRow))
        XCTAssertTrue(activeDaysRow.isEnabled, "Active Days must be usable at Silver+.")
    }

    // MARK: - Dead Reckoning on Signal Loss: Silver disabled, Gold enabled
    //
    // Only rendered under Time-based trigger mode, itself Silver+ (see
    // below) — so these tests select Time mode first via a Silver launch,
    // then check the Dead Reckoning toggle specifically needs Gold on top.

    func test_silverTier_deadReckoningToggleDisabled() throws {
        launch(tier: "Silver")
        openAddLocationAlarm()

        let picker = app.segmentedControls["triggerModePicker"]
        XCTAssertTrue(scrollIntoView(picker))
        picker.buttons.element(boundBy: 1).tap() // "Time (before arrival)"

        let toggle = app.switches["deadReckoningToggle"]
        XCTAssertTrue(scrollIntoView(toggle), "Dead Reckoning toggle must still be visible at Silver.")
        XCTAssertFalse(toggle.isEnabled, "Dead Reckoning requires Gold.")
        XCTAssertTrue(lockBadgeExists(tier: "gold"))
    }

    func test_goldTier_deadReckoningToggleEnabled() throws {
        launch(tier: "Gold")
        openAddLocationAlarm()

        let picker = app.segmentedControls["triggerModePicker"]
        XCTAssertTrue(scrollIntoView(picker))
        picker.buttons.element(boundBy: 1).tap() // "Time (before arrival)"

        let toggle = app.switches["deadReckoningToggle"]
        XCTAssertTrue(scrollIntoView(toggle))
        XCTAssertTrue(toggle.isEnabled, "Dead Reckoning must be usable at Gold.")
        XCTAssertFalse(lockBadgeExists(tier: "gold"))
    }

    // MARK: - Trigger Mode picker: Distance/Standard disabled, Silver+ enabled

    func test_standardTier_triggerModePickerDisabled() throws {
        launch(tier: "Standard")
        openAddLocationAlarm()

        let picker = app.segmentedControls["triggerModePicker"]
        XCTAssertTrue(scrollIntoView(picker), "Trigger Mode picker must still be visible on Standard tier.")
        XCTAssertFalse(picker.isEnabled, "Time-based trigger mode requires Silver+ — the whole control is gated (no per-segment disable in a segmented Picker).")
        XCTAssertTrue(lockBadgeExists(tier: "silver"))
    }

    func test_silverTier_triggerModePickerEnabled() throws {
        launch(tier: "Silver")
        openAddLocationAlarm()

        let picker = app.segmentedControls["triggerModePicker"]
        XCTAssertTrue(scrollIntoView(picker))
        XCTAssertTrue(picker.isEnabled, "Trigger Mode picker must be enabled at Silver+.")
        XCTAssertFalse(lockBadgeExists(tier: "silver"))
    }

    // MARK: - Transit Alarm menu row: Standard disabled, Silver+ enabled

    func test_standardTier_transitAlarmMenuRowDisabled() throws {
        launch(tier: "Standard")

        let addMenuButton = app.buttons["addAlarmMenuButton"]
        XCTAssertTrue(addMenuButton.waitForExistence(timeout: 3))
        addMenuButton.tap()

        let transitButton = app.buttons["transitAlarmMenuButton"]
        let transitMenuItem = app.menuItems["transitAlarmMenuButton"]
        let found = transitButton.waitForExistence(timeout: 2) || transitMenuItem.waitForExistence(timeout: 1)
        XCTAssertTrue(found, "Transit Alarm row must still be VISIBLE on Standard tier — gated, not hidden.")

        let row = transitButton.exists ? transitButton : transitMenuItem
        XCTAssertFalse(row.isEnabled, "Transit Alarms require Silver+ — Standard only gets Location alarms.")
    }

    func test_silverTier_transitAlarmMenuRowEnabled() throws {
        launch(tier: "Silver")

        let addMenuButton = app.buttons["addAlarmMenuButton"]
        XCTAssertTrue(addMenuButton.waitForExistence(timeout: 3))
        addMenuButton.tap()

        let transitButton = app.buttons["transitAlarmMenuButton"]
        let transitMenuItem = app.menuItems["transitAlarmMenuButton"]
        let found = transitButton.waitForExistence(timeout: 2) || transitMenuItem.waitForExistence(timeout: 1)
        XCTAssertTrue(found)

        let row = transitButton.exists ? transitButton : transitMenuItem
        XCTAssertTrue(row.isEnabled, "Transit Alarms must be usable at Silver+.")
    }

    // MARK: - Sound library: Free locked on bundled sounds, Standard+ unlocked

    func test_freeTier_bundledSoundRowLocked() throws {
        launch(tier: "Free")
        openAddLocationAlarm()

        let collapsedRow = formRow("soundPickerCollapsedRow")
        XCTAssertTrue(scrollIntoView(collapsedRow), "Sound picker must be visible on Free tier.")
        collapsedRow.tap()

        // "Boat Horn.wav" is one of the bundled travel sounds — see
        // GeoAlarm/Sounds/. Requires Standard+; system sounds (Vibrate/
        // Default) are always free and not covered here.
        // Expanding the list adds ~10+ new rows below the already-scrolled
        // position of collapsedRow — a flat waitForExistence(timeout: 2)
        // isn't enough; this needs the same scroll-into-view retry loop as
        // every other row in this file (caught in CI, 2026-07-12).
        let boatHornRow = formRow("soundRow.Boat Horn.wav")
        XCTAssertTrue(scrollIntoView(boatHornRow), "Bundled sound rows must still be VISIBLE on Free tier — gated, not hidden.")
        XCTAssertTrue(lockBadgeExists(tier: "standard"), "A Standard-required lock badge must appear on locked bundled sound rows.")
    }

    func test_standardTier_bundledSoundRowUnlocked() throws {
        launch(tier: "Standard")
        openAddLocationAlarm()

        let collapsedRow = formRow("soundPickerCollapsedRow")
        XCTAssertTrue(scrollIntoView(collapsedRow))
        collapsedRow.tap()

        // See test_freeTier_bundledSoundRowLocked for why this needs
        // scrollIntoView rather than a flat waitForExistence.
        let boatHornRow = formRow("soundRow.Boat Horn.wav")
        XCTAssertTrue(scrollIntoView(boatHornRow))
        boatHornRow.tap()

        // Selecting it should collapse the list back to the single summary
        // row showing the newly selected sound — confirms the tap actually
        // registered as a selection, not just that the row exists.
        XCTAssertTrue(collapsedRow.waitForExistence(timeout: 2))
    }

    // MARK: - Calendar Scanning: Silver disabled, Gold enabled

    func test_silverTier_calendarScanningRowDisabled() throws {
        launch(tier: "Silver")

        app.buttons["settingsButton"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))

        let row = app.cells["calendarScanningRow"].exists
            ? app.cells["calendarScanningRow"]
            : app.buttons["calendarScanningRow"]
        XCTAssertTrue(scrollIntoView(row), "Calendar Scanning row must still be visible at Silver.")
        XCTAssertFalse(row.isEnabled, "Calendar Scanning requires Gold.")
    }

    func test_goldTier_calendarScanningRowEnabled() throws {
        launch(tier: "Gold")

        app.buttons["settingsButton"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))

        let row = app.cells["calendarScanningRow"].exists
            ? app.cells["calendarScanningRow"]
            : app.buttons["calendarScanningRow"]
        XCTAssertTrue(scrollIntoView(row))
        XCTAssertTrue(row.isEnabled, "Calendar Scanning must be usable at Gold.")
    }

    // MARK: - Auto-Notify Defaults (Settings): Free disabled, Standard+ enabled
    //
    // Same gate as the per-alarm autoNotifyToggle (Standard+) — these two
    // buttons manage the *default* contact list that pre-fills that toggle,
    // so they must honor the identical tier boundary. Added 2026-07-11 after
    // Bob reported them rendering fully active on Free tier in a screenshot.

    func test_freeTier_autoNotifyDefaultsButtonsDisabled() throws {
        launch(tier: "Free")

        app.buttons["settingsButton"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))

        let addFromContacts = app.buttons["addFromContactsButton"]
        let addManually = app.buttons["addManuallyButton"]
        XCTAssertTrue(scrollIntoView(addFromContacts), "Add from Contacts must still be visible on Free tier.")
        XCTAssertTrue(addManually.waitForExistence(timeout: 2))

        XCTAssertFalse(addFromContacts.isEnabled, "Add from Contacts requires Standard+ — contact notify starts at Standard.")
        XCTAssertFalse(addManually.isEnabled, "Add Manually requires Standard+.")
        XCTAssertTrue(lockBadgeExists(tier: "standard"))
    }

    func test_standardTier_autoNotifyDefaultsButtonsEnabled() throws {
        launch(tier: "Standard")

        app.buttons["settingsButton"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))

        let addFromContacts = app.buttons["addFromContactsButton"]
        let addManually = app.buttons["addManuallyButton"]
        XCTAssertTrue(scrollIntoView(addFromContacts))
        XCTAssertTrue(addManually.waitForExistence(timeout: 2))

        XCTAssertTrue(addFromContacts.isEnabled, "Add from Contacts must be usable at Standard+.")
        XCTAssertTrue(addManually.isEnabled, "Add Manually must be usable at Standard+.")
    }

    // MARK: - Set Up Automation (Settings, Auto-SMS section): Standard disabled, Silver+ enabled
    //
    // Added 2026-07-11 per Bob: this deep-links to Shortcuts' automation
    // creation screen, and leaving it tappable below Silver was judged a
    // confusing "backdoor" — a Free/Standard user could build the whole
    // Shortcuts automation manually even though the toggle that actually
    // activates it (autoSMSAutomationToggle) is Silver-gated. Gating this
    // button too closes that loophole and matches Silver's paywall intent.

    func test_standardTier_setUpAutomationButtonDisabled() throws {
        launch(tier: "Standard")

        app.buttons["settingsButton"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))

        let button = app.buttons["setUpAutomationButton"]
        XCTAssertTrue(scrollIntoView(button), "Set Up Automation must still be visible on Standard tier.")
        XCTAssertFalse(button.isEnabled, "Set Up Automation requires Silver+ — it's a backdoor to the automation the Silver-gated toggle activates.")
        XCTAssertTrue(lockBadgeExists(tier: "silver"))
    }

    func test_silverTier_setUpAutomationButtonEnabled() throws {
        launch(tier: "Silver")

        app.buttons["settingsButton"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))

        let button = app.buttons["setUpAutomationButton"]
        XCTAssertTrue(scrollIntoView(button))
        XCTAssertTrue(button.isEnabled, "Set Up Automation must be usable at Silver+.")
        XCTAssertFalse(lockBadgeExists(tier: "silver"))
    }

    // MARK: - Free-tier alarm cap: "+" button disables after one active alarm

    func test_freeTier_addButtonDisabledAfterOneAlarm() throws {
        launch(tier: "Free")

        let addMenuButton = app.buttons["addAlarmMenuButton"]
        XCTAssertTrue(addMenuButton.waitForExistence(timeout: 3))
        XCTAssertTrue(addMenuButton.isEnabled, "Must be able to add the first alarm on Free tier.")

        addMenuButton.tap()
        let locationAlarmButton = app.buttons["Location Alarm"]
        let locationAlarmMenuItem = app.menuItems["Location Alarm"]
        XCTAssertTrue(locationAlarmButton.waitForExistence(timeout: 2) || locationAlarmMenuItem.waitForExistence(timeout: 1))
        (locationAlarmButton.exists ? locationAlarmButton : locationAlarmMenuItem).tap()

        let nameField = app.textFields["Name (e.g. Penn Station)"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 2))
        nameField.tap()
        nameField.typeText("Only Alarm")

        if app.keyboards.count > 0 {
            let doneButton = app.buttons["keyboardDoneButton"]
            if doneButton.waitForExistence(timeout: 1) { doneButton.tap() }
        }

        let mapView = app.maps.firstMatch
        if mapView.waitForExistence(timeout: 3) {
            mapView.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }

        _ = scrollIntoView(app.buttons["saveAlarmButton"])
        app.buttons["saveAlarmButton"].tap()

        XCTAssertTrue(app.staticTexts["Only Alarm"].waitForExistence(timeout: 2), "The first Free-tier alarm must save normally.")
        XCTAssertFalse(addMenuButton.isEnabled, "The + button must disable once Free tier's one-active-alarm cap is reached.")
    }
}
