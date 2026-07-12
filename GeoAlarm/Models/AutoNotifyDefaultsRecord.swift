// Copyright © 2026 Robert Bartis. All rights reserved.

// AutoNotifyDefaultsRecord.swift
// Singleton SwiftData record holding the global Auto-Notify Defaults contact
// list (Settings → Auto-Notify Defaults — the list that pre-fills a new
// alarm's Auto-Notify contacts). CloudKit-synced via the same ModelContainer
// as NapAlarm/GTFSFeedModel (see NapStopApp.swift's `container`).
//
// Added 2026-07-11: this used to live in UserDefaults.standard, which is
// device-local only — a user who configured their default contacts on their
// iPhone would not see them on their iPad, even though alarms themselves,
// and per-alarm Auto-Notify contacts (NapAlarm.notifyContactsJSON), already
// sync fine. Bob flagged this as a cross-device-migration gap. Read/write
// access goes through AutoNotifyDefaultsStore, not this type directly — see
// that file for the load/save/migration logic.

import Foundation
import SwiftData

@Model
final class AutoNotifyDefaultsRecord {

    /// Fixed identifier, the same on every device. There is only ever one
    /// row: AutoNotifyDefaultsStore upserts against this exact id rather
    /// than managing a collection, so CloudKit sync merges every device's
    /// writes into a single record instead of creating duplicates.
    static let sharedID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    var id: UUID = AutoNotifyDefaultsRecord.sharedID

    /// JSON-encoded `[NotifyContact]` — same encode/decode helpers as
    /// NapAlarm.notifyContactsJSON (see `Array<NotifyContact>.fromJSON`/
    /// `.toJSON()` in NapAlarm.swift).
    var contactsJSON: String = "[]"

    init(contactsJSON: String = "[]") {
        self.id = Self.sharedID
        self.contactsJSON = contactsJSON
    }
}
