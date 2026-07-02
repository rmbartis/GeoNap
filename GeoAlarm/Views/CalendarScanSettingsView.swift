// CalendarScanSettingsView.swift
// Settings submenu for the Calendar Scanning feature: scans the user's
// calendars for upcoming events with a location and suggests location-based
// alarms. Strictly opt-in — calendarScanEnabled defaults to false.

import SwiftUI
import EventKit

struct CalendarScanSettingsView: View {

    @AppStorage(AppStorageKey.calendarScanEnabled)         private var scanEnabled = false
    @AppStorage(AppStorageKey.calendarScanModeRaw)         private var scanModeRaw = CalendarScanMode.automatic.rawValue
    @AppStorage(AppStorageKey.calendarScanNotifyOnResults) private var notifyOnResults = true
    @AppStorage(AppStorageKey.calendarScanLookaheadDays)   private var lookaheadDays = 14
    @AppStorage(AppStorageKey.calendarScanEnabledCalendarIDs)     private var enabledCalendarIDsRaw = "[]"
    @AppStorage(AppStorageKey.calendarScanHasCompletedFirstRun)   private var hasCompletedFirstRun = false

    @StateObject private var scanService = CalendarScanService()
    @Environment(\.languageBundle) private var bundle

    @State private var showFirstRunSheet = false

    private var scanMode: CalendarScanMode {
        CalendarScanMode(rawValue: scanModeRaw) ?? .automatic
    }

    private var enabledCalendarIDs: Set<String> {
        CalendarScanStorage.decodeStringSet(enabledCalendarIDsRaw)
    }

    var body: some View {
        Form {
            Section {
                Toggle(isOn: Binding(
                    get: { scanEnabled },
                    set: handleScanEnabledChange
                )) {
                    Text("Scan Calendars for Trips", bundle: bundle)
                }
            } header: {
                Text("Calendar Scanning", bundle: bundle)
            } footer: {
                Text("settings.calendarScan.mainFooter", bundle: bundle)
            }

            if scanEnabled {
                if scanService.isAuthorized {
                    Section {
                        Picker(selection: $scanModeRaw) {
                            ForEach(CalendarScanMode.allCases) { mode in
                                Text(NSLocalizedString(mode.localizationKey, bundle: bundle, comment: ""))
                                    .tag(mode.rawValue)
                            }
                        } label: {
                            Text("Scan Mode", bundle: bundle)
                        }
                        .pickerStyle(.segmented)

                        Toggle(isOn: $notifyOnResults) {
                            Text("Notify Me About New Trips", bundle: bundle)
                        }

                        Stepper(value: $lookaheadDays, in: 1...60) {
                            HStack {
                                Text("Look Ahead (days)", bundle: bundle)
                                Spacer()
                                Text("\(lookaheadDays)")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } header: {
                        Text("Scan Behavior", bundle: bundle)
                    } footer: {
                        Text("settings.calendarScan.behaviorFooter", bundle: bundle)
                    }

                    Section {
                        ForEach(scanService.sourceGroups) { group in
                            calendarGroupSection(group)
                        }

                        Button {
                            // Phase 2: triggers an on-demand scan of enabled
                            // calendars and surfaces trip candidates for review.
                            // No-op placeholder for Phase 1.
                        } label: {
                            Text("Scan Now", bundle: bundle)
                        }
                        .disabled(enabledCalendarIDs.isEmpty)
                    } header: {
                        Text("Calendars", bundle: bundle)
                    }
                } else {
                    Section {
                        Button {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            Text("Open Settings", bundle: bundle)
                        }
                    } header: {
                        Text("Calendar Access Needed", bundle: bundle)
                    } footer: {
                        Text("settings.calendarScan.accessDeniedFooter", bundle: bundle)
                    }
                }
            }
        }
        .navigationTitle(Text("Calendar Scanning", bundle: bundle))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if scanEnabled && scanService.isAuthorized {
                scanService.refreshSourceGroups()
            }
        }
        .sheet(isPresented: $showFirstRunSheet, onDismiss: {
            hasCompletedFirstRun = true
        }) {
            CalendarFirstRunSheet(scanService: scanService,
                                   enabledCalendarIDsRaw: $enabledCalendarIDsRaw)
        }
    }

    // MARK: - Toggle handling

    private func handleScanEnabledChange(_ newValue: Bool) {
        scanEnabled = newValue
        guard newValue else {
            DebugLogger.shared.log("Calendar scanning disabled by user.", category: "CalendarScan")
            return
        }
        DebugLogger.shared.log("Calendar scanning enabled by user.", category: "CalendarScan")
        Task {
            let granted = await scanService.requestAccess()
            guard granted else {
                // Leave the toggle ON — don't silently revert. The "Calendar
                // Access Needed" section stays visible so the user can grant
                // access from iOS Settings without losing their choice.
                return
            }
            scanService.refreshSourceGroups()
            if !hasCompletedFirstRun {
                showFirstRunSheet = true
            }
        }
    }

    // MARK: - Per-source calendar rows

    @ViewBuilder
    private func calendarGroupSection(_ group: CalendarSourceGroup) -> some View {
        ForEach(group.calendars) { cal in
            Toggle(isOn: Binding(
                get: { enabledCalendarIDs.contains(cal.id) },
                set: { isOn in
                    var ids = enabledCalendarIDs
                    if isOn { ids.insert(cal.id) } else { ids.remove(cal.id) }
                    enabledCalendarIDsRaw = CalendarScanStorage.encodeStringSet(ids)
                }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(cal.title)
                    Text(group.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - First-run "select calendars" sheet (Option C)

/// Shown the first time the user enables calendar scanning and access is
/// granted. Pre-checks only the primary/iCloud source's calendars — every
/// other calendar starts unchecked (opt-out with a safe default, not
/// opt-in-per-calendar).
private struct CalendarFirstRunSheet: View {
    @ObservedObject var scanService: CalendarScanService
    @Binding var enabledCalendarIDsRaw: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.languageBundle) private var bundle

    var body: some View {
        NavigationStack {
            Form {
                ForEach(scanService.sourceGroups) { group in
                    Section {
                        ForEach(group.calendars) { cal in
                            Toggle(isOn: bindingFor(cal.id)) {
                                Text(cal.title)
                            }
                        }
                    } header: {
                        Text(group.title)
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Text("settings.calendarScan.firstRunFooter", bundle: bundle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(.thinMaterial)
            }
            .navigationTitle(Text("Select Calendars to Scan", bundle: bundle))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text("Continue", bundle: bundle)
                    }
                }
            }
            .onAppear(perform: seedDefaultSelectionIfNeeded)
        }
    }

    private func bindingFor(_ id: String) -> Binding<Bool> {
        Binding(
            get: { CalendarScanStorage.decodeStringSet(enabledCalendarIDsRaw).contains(id) },
            set: { isOn in
                var ids = CalendarScanStorage.decodeStringSet(enabledCalendarIDsRaw)
                if isOn { ids.insert(id) } else { ids.remove(id) }
                enabledCalendarIDsRaw = CalendarScanStorage.encodeStringSet(ids)
            }
        )
    }

    /// Pre-checks only the primary source's calendars, once, the first time
    /// this sheet appears with an empty selection.
    private func seedDefaultSelectionIfNeeded() {
        guard CalendarScanStorage.decodeStringSet(enabledCalendarIDsRaw).isEmpty else { return }
        guard let primaryID = scanService.primarySourceID,
              let primaryGroup = scanService.sourceGroups.first(where: { $0.id == primaryID }) else {
            return
        }
        let seeded = Set(primaryGroup.calendars.map(\.id))
        enabledCalendarIDsRaw = CalendarScanStorage.encodeStringSet(seeded)
    }
}

#Preview {
    NavigationStack {
        CalendarScanSettingsView()
    }
}
