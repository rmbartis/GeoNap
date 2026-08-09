// Copyright © 2026 Robert Bartis. All rights reserved.

// NapAlarmShortcutsTests.swift
// Added 2026-08-09 as part of a full test-coverage pass — GeoAlarm/Intents/
// had zero test coverage of any kind. This is the one file in that folder
// safely unit-testable without a production change: every other Intent
// (CreateAlarmIntent, EnableAlarmIntent/DisableAlarmIntent, NapAlarmQuery)
// calls IntentModelContainer.make() directly inside perform()/entities(for:),
// which hardcodes a real CloudKit-backed ModelContainer with no injection
// seam — calling those from a unit test would either hit the test runner's
// real on-disk/CloudKit store (unsafe, non-deterministic, exactly the kind
// of instability "maximum stable coverage" is supposed to avoid) or require
// adding a container-override parameter to IntentModelContainer, which is a
// production change Bob asked to skip for this pass.
//
// NapAlarmShortcuts.appShortcuts, by contrast, is pure declarative metadata:
// constructing each AppShortcut(intent:...) only builds the intent struct
// (no perform() call happens at construction time), so it's safe to
// construct in a unit test.
//
// CORRECTED 2026-08-09 (real xcodebuild run, Xcode 26.6/iOS 26.5 SDK): the
// first version of this file also asserted on `shortcut.phrases`,
// `.shortTitle`, and `.systemImageName` — all three failed to compile with
// "value of type 'AppShortcut' has no member ...". AppShortcut in this SDK
// is a write-only-at-init, otherwise opaque configuration type; none of the
// values passed into `AppShortcut(intent:phrases:shortTitle:systemImageName:)`
// are readable back out. This is the actual, compiler-verified API surface —
// not something guessable from documentation alone — so this file is now
// limited to the one thing that IS introspectable: how many shortcuts got
// registered.

import XCTest
@testable import GeoNap

final class NapAlarmShortcutsTests: XCTestCase {

    // MARK: - Every shortcut is registered

    func test_appShortcuts_registersAllFiveIntents() {
        let shortcuts = NapAlarmShortcuts.appShortcuts
        XCTAssertEqual(shortcuts.count, 5,
            "Expected Create, Enable, Disable, Notify Contacts, and Run Shortcut — update this count deliberately if a shortcut is added or removed.")
    }
}
