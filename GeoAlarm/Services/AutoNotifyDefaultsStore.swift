// Copyright © 2026 Robert Bartis. All rights reserved.

// AutoNotifyDefaultsStore.swift
// Read/write access to the CloudKit-synced Auto-Notify Defaults contact list
// (see AutoNotifyDefaultsRecord). Configured once at launch with the app's
// ModelContext, mirroring AlarmManager.setModelContext(_:) — kept as its own
// lightweight store rather than folded into AlarmManager because the
// Auto-Notify Defaults list is read from AlarmViewModel (a plain
// ObservableObject with no AlarmManager/environment access) via
// `Array<NotifyContact>.loadGlobalDefaults()`/`.saveAsGlobalDefaults()` in
// NapAlarm.swift — this store is what those two calls now delegate to, so
// every existing call site (AlarmViewModel.swift, TransitAlarmView.swift,
// SettingsView.swift) needed zero changes.
//
// Added 2026-07-11 to close a cross-device-sync gap: this data used to live
// in UserDefaults.standard (device-local only). See
// AutoNotifyDefaultsRecord.swift and the monetization-tier-pricing /
// cross-device-sync memory for the full story.

import Foundation
import SwiftData

enum AutoNotifyDefaultsStore {

    private static var modelContext: ModelContext?

    /// Call once at launch (RootView.onAppear, alongside
    /// alarmManager.setModelContext) before any load()/save() call.
    static func configure(_ context: ModelContext) {
        modelContext = context
        migrateFromUserDefaultsIfNeeded()
    }

    static func load() -> [NotifyContact] {
        guard let context = modelContext else { return [] }
        guard let record = fetchRecord(in: context) else { return [] }
        return [NotifyContact].fromJSON(record.contactsJSON)
    }

    static func save(_ contacts: [NotifyContact]) {
        guard let context = modelContext else { return }
        let json = contacts.toJSON()
        if let existing = fetchRecord(in: context) {
            existing.contactsJSON = json
        } else {
            context.insert(AutoNotifyDefaultsRecord(contactsJSON: json))
        }
        do {
            try context.save()
        } catch {
            DebugLogger.shared.log("AutoNotifyDefaultsStore save FAILED: \(error.localizedDescription)", category: "AutoNotifyDefaults")
        }
    }

    // MARK: - Private

    private static func fetchRecord(in context: ModelContext) -> AutoNotifyDefaultsRecord? {
        let id = AutoNotifyDefaultsRecord.sharedID
        let descriptor = FetchDescriptor<AutoNotifyDefaultsRecord>(
            predicate: #Predicate { $0.id == id }
        )
        return try? context.fetch(descriptor).first
    }

    /// One-time migration from the old UserDefaults.standard-backed storage
    /// so no one who'd already configured Auto-Notify Defaults loses their
    /// contacts when this ships. Only runs if the new store has never been
    /// written on this device (no record at all) — if a record already
    /// exists, even an empty one, this is a no-op, so a deliberately cleared
    /// list is never overwritten by stale UserDefaults data.
    private static func migrateFromUserDefaultsIfNeeded() {
        guard let context = modelContext else { return }
        guard fetchRecord(in: context) == nil else { return }
        let legacyJSON = UserDefaults.standard.string(forKey: AppStorageKey.defaultNotifyContacts) ?? ""
        guard !legacyJSON.isEmpty, legacyJSON != "[]" else { return }
        context.insert(AutoNotifyDefaultsRecord(contactsJSON: legacyJSON))
        do {
            try context.save()
            UserDefaults.standard.removeObject(forKey: AppStorageKey.defaultNotifyContacts)
            DebugLogger.shared.log("Auto-Notify Defaults migrated from UserDefaults to synced store", category: "AutoNotifyDefaults")
        } catch {
            DebugLogger.shared.log("Auto-Notify Defaults migration FAILED: \(error.localizedDescription)", category: "AutoNotifyDefaults")
        }
    }
}
