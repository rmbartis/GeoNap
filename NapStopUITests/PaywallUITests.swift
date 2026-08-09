// Copyright © 2026 Robert Bartis. All rights reserved.

// PaywallUITests.swift
// Basic XCUITest coverage for PaywallView (Phase 3, item 10) — the only
// screen that calls PurchaseManager.purchase(_:) / .restorePurchases().
// Added 2026-08-09 after a test-coverage review found this screen, despite
// being the money-critical one in the app, had zero automated coverage of
// any kind (unit or UI) — see docs/app-store-release-checklist.md.
//
// Scope, deliberately: this does NOT attempt to drive a real purchase.
// GeoNap's scheme has no StoreKit Configuration file wired up for the
// GeoNapUITests target (only GeoNap.storekit exists on disk, unattached —
// see Phase 3 item 12), so `Product.products(for:)` is not guaranteed to
// resolve in CI/this environment; a test asserting the "Subscribe"/"Buy"
// buttons appear would be flaky through no fault of the app. Instead these
// tests exercise everything that does NOT depend on StoreKit product
// metadata loading:
//   - the screen opens and renders its header/free-tier card
//   - the "owned" rendering path (EntitlementManager.isEntitled, which reads
//     the --uitesting-tier override directly — no StoreKit involved) hides
//     every purchase button once a tier is already owned
//   - Restore Purchases and Not Now are present, tappable, and don't crash
//     or hang the app
// If Bob wires up the StoreKit Configuration file for UI testing later, a
// follow-up test asserting the buy buttons populate would be the natural
// next addition — flagged here rather than guessed at.
//
// Same duplication-over-sharing pattern as TierGatingUITests.swift (see that
// file's header): its own launch(tier:) rather than inheriting from
// NapStopUITests, since the tier has to be chosen before launch.
//
// NOTE: like the rest of this suite, these need an actual Xcode build +
// simulator run to confirm — not executed in this authoring environment.

import XCTest

final class PaywallUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Helpers

    /// Mirrors TierGatingUITests.launch(tier:) — see that file for why tier
    /// has to be a launch argument rather than something set post-launch.
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

    private func openSettings() {
        let settingsButton = app.buttons["settingsButton"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 3))
        settingsButton.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))
    }

    /// Settings' Plan section is the first section in the Form, so
    /// seePlansButton is normally on-screen without scrolling — scrollIntoView
    /// is still used defensively in case a future section is inserted above it.
    private func openPaywallFromSettings() {
        openSettings()
        let seePlansButton = app.buttons["seePlansButton"]
        XCTAssertTrue(scrollIntoView(seePlansButton), "\"See Plans\" row must be visible in Settings.")
        seePlansButton.tap()
    }

    // MARK: - Opens and renders

    func test_paywall_opensFromSettings_showsHeaderFreeCardAndRestoreButton() throws {
        launch(tier: "Free")
        openPaywallFromSettings()

        // paywall.title, en.lproj — see PaywallView.header.
        XCTAssertTrue(app.staticTexts["Unlock More with GeoNap"].waitForExistence(timeout: 3),
                      "Paywall header must render once presented.")

        // The free tier is always shown as an informational (non-purchasable)
        // card, independent of whether StoreKit products have loaded.
        XCTAssertTrue(app.staticTexts["Free"].waitForExistence(timeout: 2),
                      "Free tier card must render.")

        // Restore Purchases doesn't depend on Product.products(for:) resolving —
        // it must be present and enabled regardless of network/StoreKit state.
        let restoreButton = app.buttons["paywallRestoreButton"]
        XCTAssertTrue(scrollIntoView(restoreButton), "Restore Purchases must be visible.")
        XCTAssertTrue(restoreButton.isEnabled, "Restore Purchases must be enabled at every tier.")
    }

    // MARK: - Owned-tier rendering (StoreKit-independent)

    func test_paywall_platinumTier_ownedTiersHaveNoBuyButtons() throws {
        // At Platinum, EntitlementManager.isEntitled(to:) is true for every
        // purchasable tier — actionButton(...) must render "Included" for
        // all three instead of a Subscribe/Buy button. This path doesn't
        // touch StoreKit product metadata at all, so it's safe to assert on
        // unconditionally (see file header).
        launch(tier: "Platinum")
        openPaywallFromSettings()

        XCTAssertTrue(app.staticTexts["Unlock More with GeoNap"].waitForExistence(timeout: 3))

        XCTAssertFalse(app.buttons["paywallBuyButton.silver"].exists,
                       "Silver must show as Included, not a Subscribe button, once owned.")
        XCTAssertFalse(app.buttons["paywallBuyButton.gold"].exists,
                       "Gold must show as Included, not a Subscribe button, once owned.")
        XCTAssertFalse(app.buttons["paywallBuyButton.platinum"].exists,
                       "Platinum must show as Included, not a Buy button, once owned.")
    }

    // MARK: - Dismiss

    func test_paywall_notNowDismissesBackToSettings() throws {
        launch(tier: "Free")
        openPaywallFromSettings()

        XCTAssertTrue(app.staticTexts["Unlock More with GeoNap"].waitForExistence(timeout: 3))

        // paywall.notNow, en.lproj — toolbar cancellation button.
        let notNowButton = app.buttons["Not Now"]
        XCTAssertTrue(notNowButton.waitForExistence(timeout: 2))
        notNowButton.tap()

        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3),
                      "Dismissing the paywall must return to Settings underneath it.")
    }

    // MARK: - Restore doesn't crash or hang the app

    func test_paywall_restoreButtonTappable_appStaysResponsive() throws {
        launch(tier: "Free")
        openPaywallFromSettings()

        let restoreButton = app.buttons["paywallRestoreButton"]
        XCTAssertTrue(scrollIntoView(restoreButton))
        restoreButton.tap()

        // restorePurchases() calls AppStore.sync() and may fail fast (no
        // network entitlement / no StoreKit config in this environment) —
        // that's fine; this only asserts the app survives the tap rather
        // than hanging or crashing on whatever AppStore.sync() does here.
        XCTAssertEqual(app.state, .runningForeground,
                       "Tapping Restore Purchases must not crash or hang the app.")
    }
}
