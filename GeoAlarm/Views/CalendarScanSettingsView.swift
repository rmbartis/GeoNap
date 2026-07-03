// CalendarScanSettingsView.swift
// Settings submenu for the Calendar Scanning feature: scans the user's
// calendars for upcoming events with a location and suggests location-based
// alarms. Strictly opt-in — calendarScanEnabled defaults to false.

import SwiftUI

struct CalendarScanSettingsView: View {

    /// When true, the pending-trips review sheet opens automatically as soon
    /// as there's something to show. Used for the "new trips found"
    /// notification deep link (ContentView presents this view with this set)
    /// so tapping the notification lands the user directly on the
    /// add/decline screen instead of just the Settings submenu (Bob, 2026-07-03).
    var openReviewOnAppear: Bool = false

    @AppStorage(AppStorageKey.calendarScanEnabled)         private var scanEnabled = false
    @AppStorage(AppStorageKey.calendarScanModeRaw)         private var scanModeRaw = CalendarScanMode.automatic.rawValue
    @AppStorage(AppStorageKey.calendarScanNotifyOnResults) private var notifyOnResults = true
    @AppStorage(AppStorageKey.calendarScanLookaheadDays)   private var lookaheadDays = 14
    @AppStorage(AppStorageKey.calendarScanEnabledCalendarIDs)     private var enabledCalendarIDsRaw = "[]"
    @AppStorage(AppStorageKey.calendarScanHasCompletedFirstRun)   private var hasCompletedFirstRun = false

    @StateObject private var scanService = CalendarScanService()
    @Environment(\.languageBundle) private var bundle
    @EnvironmentObject private var alarmManager: AlarmManager

    @State private var showFirstRunSheet = false

    // MARK: - Phase 2/3: scan pipeline state
    @State private var isScanning = false
    /// The current pending-review list — candidates found by a scan (manual
    /// or background) that the user hasn't yet added or declined. Loaded from
    /// CalendarScanCandidateStore on appear so a background scan's results
    /// are visible without requiring a fresh "Scan Now" tap (Phase 3).
    @State private var candidates: [CalendarTripCandidate] = []
    @State private var showReviewSheet = false
    @State private var showNoResultsAlert = false

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
                        .onChange(of: scanModeRaw) {
                            CalendarScanBackgroundTask.scheduleNextRefresh()
                        }

                        Toggle(isOn: $notifyOnResults) {
                            Text("Notify Me About New Trips", bundle: bundle)
                        }
                        .onChange(of: notifyOnResults) {
                            guard notifyOnResults else { return }
                            Task { await CalendarScanNotifier.requestAuthorizationIfNeeded() }
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
                            runScanNow()
                        } label: {
                            HStack {
                                Text("Scan Now", bundle: bundle)
                                if isScanning {
                                    Spacer()
                                    ProgressView()
                                }
                            }
                        }
                        .disabled(enabledCalendarIDs.isEmpty || isScanning)

                        if !candidates.isEmpty {
                            Button {
                                showReviewSheet = true
                            } label: {
                                Text(String(format: NSLocalizedString("settings.calendarScan.reviewPendingButton", bundle: bundle, comment: ""), candidates.count))
                            }
                        }
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
            candidates = CalendarScanCandidateStore.loadPending()
            if scanEnabled && scanService.isAuthorized {
                scanService.refreshSourceGroups()
            }
            if openReviewOnAppear && !candidates.isEmpty {
                showReviewSheet = true
            }
        }
        .onChange(of: scanEnabled) {
            CalendarScanBackgroundTask.scheduleNextRefresh()
        }
        .onChange(of: enabledCalendarIDsRaw) {
            CalendarScanBackgroundTask.scheduleNextRefresh()
        }
        .sheet(isPresented: $showFirstRunSheet, onDismiss: {
            hasCompletedFirstRun = true
        }) {
            CalendarFirstRunSheet(scanService: scanService,
                                   enabledCalendarIDsRaw: $enabledCalendarIDsRaw)
        }
        .sheet(isPresented: $showReviewSheet) {
            CalendarTripCandidateReviewSheet(
                candidates: candidates,
                onAdd: { candidate in decide(.added, for: candidate) },
                onDecline: { candidate in decide(.declined, for: candidate) }
            )
        }
        .alert(Text("settings.calendarScan.noResultsTitle", bundle: bundle), isPresented: $showNoResultsAlert) {
            Button {
                showNoResultsAlert = false
            } label: {
                Text("OK", bundle: bundle)
            }
        } message: {
            Text("settings.calendarScan.noResultsMessage", bundle: bundle)
        }
    }

    // MARK: - Scan Now

    private func runScanNow() {
        isScanning = true
        Task {
            let found = await scanService.scanForCandidates(
                enabledCalendarIDs: enabledCalendarIDs,
                lookaheadDays: lookaheadDays
            )
            let existingPending = CalendarScanCandidateStore.loadPending()
            let rawHandled = CalendarScanCandidateStore.loadHandled()
            // Drop "added" records whose alarm was since deleted (from the
            // normal alarm list, not this review sheet), so that event is
            // eligible to be re-offered instead of staying silently
            // suppressed forever (Bob, 2026-07-03).
            let existingAlarmEventIDs = Set(alarmManager.alarms.compactMap(\.calendarEventID))
            let handled = CalendarScanCandidateMerger.reconcileHandled(rawHandled, existingAlarmEventIDs: existingAlarmEventIDs)
            let result = CalendarScanCandidateMerger.mergeScanResults(found: found, existingPending: existingPending, handled: handled)
            CalendarScanCandidateStore.savePending(result.pending)
            CalendarScanCandidateStore.saveHandled(result.handled)

            isScanning = false
            candidates = result.pending
            if result.pending.isEmpty {
                showNoResultsAlert = true
            } else {
                showReviewSheet = true
            }
        }
    }

    /// Records the user's decision on a candidate (add or decline), persists
    /// it via CalendarScanCandidateMerger so it won't be re-offered unless the
    /// event's location later changes, and — for an add — creates the alarm.
    private func decide(_ action: CalendarScanCandidateAction, for candidate: CalendarTripCandidate) {
        if action == .added {
            // If this same calendar event previously produced an alarm — e.g. its
            // location changed since being added, which re-offers it as a fresh
            // candidate — remove the stale alarm first so re-adding doesn't leave
            // two alarms for one event (Bob, 2026-07-03).
            if let stale = CalendarScanCandidateMerger.staleAlarm(for: candidate, in: alarmManager.alarms) {
                DebugLogger.shared.log("Calendar Scanning: removing stale alarm '\(stale.name)' before re-adding updated event \(candidate.id)", category: "CalendarScan")
                alarmManager.delete(alarm: stale)
            }
            alarmManager.add(alarm: napAlarm(from: candidate))
        }
        let handled = CalendarScanCandidateStore.loadHandled()
        let (updatedPending, updatedHandled) = CalendarScanCandidateMerger.applyDecision(
            action, to: candidate, pending: candidates, handled: handled
        )
        CalendarScanCandidateStore.savePending(updatedPending)
        CalendarScanCandidateStore.saveHandled(updatedHandled)
        candidates = updatedPending
    }

    /// Builds a plain-vanilla NapAlarm from a scan candidate — sensible
    /// defaults (200 m radius, on-arrival, non-repeating). The user can edit
    /// any of these afterward from the normal alarm list, same as any other
    /// alarm; there's no separate "calendar alarm" type (mirrors the
    /// isTransitAlarm pattern's decision to feed into the same NapAlarm
    /// model rather than a parallel one).
    private func napAlarm(from candidate: CalendarTripCandidate) -> NapAlarm {
        NapAlarm(
            name: candidate.title.isEmpty ? candidate.locationTitle : candidate.title,
            latitude: candidate.latitude,
            longitude: candidate.longitude,
            radius: 200,
            regionEvent: .onEntry,
            note: candidate.locationTitle,
            calendarEventID: candidate.id
        )
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

// MARK: - Trip candidate review sheet (Phase 2/3)

/// Lists the trips currently awaiting a decision — found by the most recent
/// scan, manual or background (Phase 3 persists this list, so it also shows
/// candidates a background scan found before the user opened this screen).
/// Each row can be added as a normal alarm (+) or declined (X); either way it
/// leaves the pending list immediately via the parent's callbacks, which also
/// record the decision so it isn't re-offered unless the event's location
/// later changes.
private struct CalendarTripCandidateReviewSheet: View {
    /// Not @State — owned by the parent (CalendarScanSettingsView). Acting on
    /// a candidate calls back via `onAdd`/`onDecline`, which updates the
    /// parent's array; SwiftUI re-renders this sheet's content closure on
    /// that change, so the list updates without this view needing its own
    /// copy of the data.
    let candidates: [CalendarTripCandidate]
    let onAdd: (CalendarTripCandidate) -> Void
    let onDecline: (CalendarTripCandidate) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.languageBundle) private var bundle

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    var body: some View {
        NavigationStack {
            Group {
                if candidates.isEmpty {
                    ContentUnavailableView {
                        Label {
                            Text("settings.calendarScan.noResultsTitle", bundle: bundle)
                        } icon: {
                            Image(systemName: "calendar.badge.checkmark")
                        }
                    }
                } else {
                    List {
                        ForEach(candidates) { candidate in
                            row(for: candidate)
                        }
                    }
                }
            }
            .navigationTitle(Text("settings.calendarScan.reviewTitle", bundle: bundle))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text("Done", bundle: bundle)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func row(for candidate: CalendarTripCandidate) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(candidate.title.isEmpty ? candidate.locationTitle : candidate.title)
                    .font(.headline)
                Text(candidate.locationTitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(Self.dateFormatter.string(from: candidate.startDate))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                onDecline(candidate)
            } label: {
                Image(systemName: "xmark.circle")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("settings.calendarScan.declineCandidateAccessibilityLabel", bundle: bundle))

            Button {
                onAdd(candidate)
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("settings.calendarScan.addCandidateAccessibilityLabel", bundle: bundle))
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationStack {
        CalendarScanSettingsView()
    }
}
