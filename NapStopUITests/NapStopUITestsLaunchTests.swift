// Copyright © 2026 Robert Bartis. All rights reserved.

//
//  NapStopUITestsLaunchTests.swift
//  NapStopUITests
//
//  Created by bartis on 5/24/26.
//

import XCTest

final class NapStopUITestsLaunchTests: XCTestCase {

    // Was `true` (Xcode's default template value), which reruns testLaunch()
    // once per orientation x appearance-mode combination the scheme defines
    // — ~90 repeated launches, 12+ minutes, and the source of a mid-run
    // crash/restart during a 2026-07-09 CI run (Bob — CI stability audit).
    // Worse, it leaves the simulator's device orientation in whatever state
    // the last permutation used (observed: landscape), which then silently
    // broke portrait-assuming hit-testing in NapStopUITests, the next suite
    // to run on the same simulator instance. A single launch screenshot
    // doesn't need per-orientation coverage in CI; set explicitly if that
    // coverage is ever actually needed for a specific investigation.
    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        false
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunch() throws {
        let app = XCUIApplication()
        app.launch()

        // Insert steps here to perform after app launch but before taking a screenshot,
        // such as logging into a test account or navigating somewhere in the app
        // XCUIAutomation Documentation
        // https://developer.apple.com/documentation/xcuiautomation

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Launch Screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
