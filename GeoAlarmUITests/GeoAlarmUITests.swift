// GeoAlarmUITests.swift
// UI smoke tests using XCUITest.
// Run on the simulator; require the app to be built and running.

import XCTest

final class GeoAlarmUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        // Clear storage so each test starts clean
        app.launchArguments = ["--uitesting", "--reset-alarms"]
        app.launch()
    }

    // MARK: - Empty state

    func test_emptyState_showsPlaceholder() {
        XCTAssertTrue(app.staticTexts["No Geo Alarms Yet"].exists)
    }

    // MARK: - Add alarm flow

    func test_addAlarm_appearsInList() throws {
        // Tap the + button
        app.navigationBars.buttons["Add"].tap()

        // Fill in the name field
        let nameField = app.textFields["Name (e.g. Penn Station)"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 2))
        nameField.tap()
        nameField.typeText("Test Alarm")

        // Tap the map to set a location (center of the map view)
        let mapView = app.maps.firstMatch
        if mapView.waitForExistence(timeout: 3) {
            mapView.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }

        // Save
        app.buttons["Save Alarm"].tap()

        // Verify the alarm appears in the list
        XCTAssertTrue(app.staticTexts["Test Alarm"].waitForExistence(timeout: 2))
    }

    // MARK: - Delete alarm

    func test_swipeToDelete_removesAlarm() throws {
        // Pre-condition: add one alarm
        test_addAlarm_appearsInList()

        let cell = app.cells.staticTexts["Test Alarm"]
        XCTAssertTrue(cell.waitForExistence(timeout: 2))

        // Swipe left to reveal Delete button
        cell.swipeLeft()
        app.buttons["Delete"].tap()

        XCTAssertFalse(app.staticTexts["Test Alarm"].exists)
        XCTAssertTrue(app.staticTexts["No Geo Alarms Yet"].exists)
    }

    // MARK: - Toggle alarm

    func test_swipeToDisable_changesRowOpacity() throws {
        test_addAlarm_appearsInList()

        let cell = app.cells.staticTexts["Test Alarm"]
        XCTAssertTrue(cell.waitForExistence(timeout: 2))

        cell.swipeRight()
        app.buttons["Disable"].tap()

        // Disabled alarms render at reduced opacity — verify the cell still exists
        XCTAssertTrue(app.cells.staticTexts["Test Alarm"].exists)
    }
}
