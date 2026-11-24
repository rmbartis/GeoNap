// Copyright © 2026 Robert Bartis. All rights reserved.

// ContentView.swift
// Root navigation shell for the app.

import SwiftUI
import CoreLocation
import MessageUI

struct ContentView: View {
    @EnvironmentObject var locationManager: LocationManager
    @EnvironmentObject var alarmManager: AlarmManager
    @EnvironmentObject var languageManager: LanguageManager
    @Environment(\.languageBundle) private var bundle

    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @State private var showSettings       = false
    @State private var showMapOverview    = false
    @State private var showTransitAlarm   = false
    @State private var showAddAlarm       = false
    @State private var showMessageCompose = false
    @State private var spotlightAlarm: NapAlarm? = nil
    @State private var showCalendarScanReview = false

    /// Phase 3 (iOS 27 / iPhone Duo): with a regular-width window (open Duo,
    /// iPad, large iPhones in landscape) the app shows the alarm list and the
    /// selected alarm side by side in a NavigationSplitView. Compact width
    /// keeps the original single NavigationStack unchanged.
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    /// Alarm shown in the split view's detail column (regular width only).
    @State private var selectedAlarmID: UUID? = nil
    /// Draft for the Add Alarm screen, owned here rather than by AddAlarmView
    /// so typed input survives the screen being rebuilt when folding or
    /// unfolding iPhone Duo switches between the stack and split layouts.
    /// Replaced with a fresh one each time Add Alarm is opened from the menu.
    @State private var newAlarmDraft = AlarmViewModel()

    #if DEBUG
    // Makes transitAlarmLocked (and the Menu that reads it) re-render
    // whenever the simulated tier changes anywhere in the app — e.g. via
    // Settings' Tier Simulation picker, presented as a sheet over this same
    // view. Without this, ContentView has no reason to re-render after the
    // sheet dismisses, so the "+" menu's Transit Alarm row can keep showing
    // whatever lock state was true when ContentView last rendered, not the
    // tier you just switched to. Same fix TierGatedModifier.swift already
    // applies for Form-row gates (see its file header) — this Menu-based
    // gate needed its own copy since it can't use that modifier (Menu rows
    // don't support the trailing lock-badge layout it renders). RELEASE
    // builds never change tier at runtime, so this is compiled out there.
    @ObservedObject private var tierChangeObserver = TierChangeObserver.shared
    #endif

    /// Transit Alarms (the full Agency→Route→Stop GTFS wizard) require
    /// Gold+ — see monetization-tier-pricing memory.
    private var transitAlarmLocked: Bool { !EntitlementManager.isEntitled(to: .gold) }

    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                NavigationSplitView {
                    alarmList
                } detail: {
                    NavigationStack {
                        splitDetail
                            .navigationDestination(isPresented: $showAddAlarm) {
                                AddAlarmView(draft: newAlarmDraft)
                            }
                    }
                    // Fresh detail stack per selection, so picking another
                    // alarm doesn't leave a previously pushed screen on top.
                    .id(selectedAlarmID)
                }
            } else {
                NavigationStack {
                    alarmList
                        .navigationDestination(isPresented: $showAddAlarm) {
                            AddAlarmView(draft: newAlarmDraft)
                        }
                        .navigationDestination(item: $spotlightAlarm) { alarm in
                            AlarmDetailView(alarm: alarm)
                        }
                }
            }
        }
        .fullScreenCover(isPresented: Binding(
            get: { !hasSeenOnboarding },
            set: { if !$0 { hasSeenOnboarding = true } }
        )) {
            OnboardingView()
        }
        // After a language change re-ids the view tree (dismissing the Settings
        // sheet and landing on home), re-present Settings so the user stays put.
        .onAppear {
            if languageManager.pendingReturnToSettings {
                languageManager.pendingReturnToSettings = false
                showSettings = true
            }
        }
        // Alarm presentation (lock screen, sound, Stop/Snooze) is owned by AlarmKit
        // (see GeoAlarmScheduler) — no in-app full-screen ringing view is needed.
        //
        // Contact notification compose sheet — presented when an alarm with
        // Auto-Notify contacts fires and the app comes to the foreground.
        .sheet(isPresented: $showMessageCompose) {
            if let msg = alarmManager.pendingContactMessage {
                MessageComposeView(message: msg) {
                    alarmManager.pendingContactMessage = nil
                    showMessageCompose = false
                }
                .ignoresSafeArea()
            }
        }
        .onChange(of: alarmManager.pendingContactMessage) { _, newValue in
            guard newValue != nil else { return }
            // MFMessageComposeViewController can't be created on a device that
            // can't send texts (Simulator, iPad without iMessage, iPhone with
            // iMessage off and no SIM) — presenting it there crashes the app.
            guard MFMessageComposeViewController.canSendText() else {
                DebugLogger.shared.log("Auto-Notify: device can't send texts — compose sheet skipped", category: "AlarmManager")
                alarmManager.pendingContactMessage = nil
                return
            }
            showMessageCompose = true
        }
        // Spotlight deep link: when the user taps an alarm in Spotlight search,
        // navigate directly to its detail view.
        .onChange(of: alarmManager.spotlightAlarmID) { _, uuid in
            guard let uuid else { return }
            if horizontalSizeClass == .regular {
                selectedAlarmID = uuid
            } else {
                spotlightAlarm = alarmManager.alarms.first { $0.id == uuid }
            }
            alarmManager.spotlightAlarmID = nil   // consume so back-navigation works
        }
        // Split view: choosing a different alarm closes an Add Alarm screen
        // that was pushed over the previous selection.
        .onChange(of: selectedAlarmID) { _, _ in
            showAddAlarm = false
        }
        // Calendar Scanning "new trips found" notification deep link — see
        // CalendarScanNotificationDelegate. Opens straight to the review
        // sheet instead of just landing on the home screen.
        .onReceive(NotificationCenter.default.publisher(for: .calendarScanReviewRequested)) { _ in
            showCalendarScanReview = true
        }
    }

    /// The alarm list with its title, toolbar, sheets and status banners —
    /// shared by the phone (stack) and split-view layouts.
    private var alarmList: some View {
        AlarmListView(selection: horizontalSizeClass == .regular ? $selectedAlarmID : nil)
            .navigationTitle(Text("GeoNap", bundle: bundle))
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .sheet(isPresented: $showMapOverview) {
                MapOverviewView()
                    // Phase 3: on iPad / open iPhone Duo a default sheet is a
                    // small centered card — too cramped for a map. .page gives
                    // it a large page-sized sheet; phones are unaffected.
                    .presentationSizing(.page)
            }
            .sheet(isPresented: $showTransitAlarm) {
                TransitAlarmSheet()
            }
            .sheet(isPresented: $showCalendarScanReview) {
                NavigationStack {
                    CalendarScanSettingsView(openReviewOnAppear: true)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            newAlarmDraft = AlarmViewModel()
                            showAddAlarm = true
                        } label: {
                            Label {
                                Text("Location Alarm", bundle: bundle)
                            } icon: {
                                Image(systemName: "mappin.and.ellipse")
                            }
                        }
                        Button {
                            showTransitAlarm = true
                        } label: {
                            Label {
                                // Menu rows don't support an arbitrary
                                // trailing lock badge the way Form rows
                                // do (TierGatedModifier), so the tier
                                // requirement is spelled out inline in
                                // the label text instead, and the icon
                                // swaps to a lock — still "visible but
                                // disabled", just a different visual
                                // treatment forced by the container.
                                Text(transitAlarmLocked
                                     ? String(format: NSLocalizedString("menu.transitAlarm.locked", bundle: bundle, comment: ""), AppTier.gold.description)
                                     : NSLocalizedString("Transit Alarm", bundle: bundle, comment: ""))
                            } icon: {
                                Image(systemName: transitAlarmLocked ? "lock.fill" : "tram.fill")
                            }
                        }
                        // Real Button/.disabled() works correctly inside
                        // a Menu (unlike the onTapGesture-based Sound
                        // rows) — Transit Alarms require Gold+ (the
                        // whole Agency→Route→Stop GTFS wizard; see
                        // monetization-tier-pricing memory for why
                        // there's no partial/distance-only transit tier).
                        .disabled(transitAlarmLocked)
                        .accessibilityIdentifier("transitAlarmMenuButton")
                    } label: {
                        Image(systemName: "plus")
                    }
                    // A bare SF Symbol label has no stable, locale-independent
                    // accessibility label of its own to drive UI tests off of —
                    // this identifier is the test hook (NapStopUITests).
                    .accessibilityIdentifier("addAlarmMenuButton")
                    // Region limit (iOS 20-region cap, all tiers) OR the
                    // Free-tier 1-active-alarm cap — either blocks adding
                    // more. See AlarmManager.isAtFreeTierLimit.
                    .disabled(alarmManager.isAtRegionLimit || alarmManager.isAtFreeTierLimit)
                    .opacity((alarmManager.isAtRegionLimit || alarmManager.isAtFreeTierLimit) ? 0.35 : 1)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showMapOverview = true
                    } label: {
                        Image(systemName: "map")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityIdentifier("settingsButton")
                }
            }
            // Banner sits below the nav bar, pushing list content down.
            // safeAreaInset keeps toolbar buttons fully accessible.
            .safeAreaInset(edge: .top, spacing: 0) {
                // Permission denied/restricted is a hard blocker — nothing
                // else matters until it's fixed, so it stays exclusive.
                // Location-unavailable and syncing-with-iCloud are both
                // transient and can genuinely co-occur (e.g. right after a
                // restart, GPS and iCloud can both still be warming up) —
                // 2026-08-25: these used to be an if/else-if chain, which
                // meant a location hiccup could silently swallow the
                // syncing banner entirely. Stacked instead so both show
                // when both are true.
                if locationManager.authorizationStatus == .denied ||
                   locationManager.authorizationStatus == .restricted {
                    LocationPermissionBanner()
                } else {
                    VStack(spacing: 0) {
                        if locationManager.isLocationUnavailable {
                            LocationUnavailableBanner()
                        }
                        if alarmManager.isSyncingWithiCloud {
                            SyncingWithiCloudBanner()
                        }
                    }
                }
            }
    }

    /// Detail column of the split view: the selected alarm, or a placeholder.
    @ViewBuilder
    private var splitDetail: some View {
        if let id = selectedAlarmID,
           let alarm = alarmManager.alarms.first(where: { $0.id == id }) {
            AlarmDetailView(alarm: alarm)
        } else {
            ContentUnavailableView {
                Label {
                    Text(LocalizedStringKey(alarmManager.alarms.isEmpty
                                            ? "No GeoNap Alarms Yet"
                                            : "split.detail.placeholder"),
                         bundle: bundle)
                } icon: {
                    Image(systemName: "mappin.and.ellipse")
                }
            }
        }
    }
}

// MARK: - Permission Warning Banner
private struct LocationPermissionBanner: View {
    @Environment(\.languageBundle) private var bundle

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "location.slash.fill")
                .foregroundColor(.white)
            Text("Location access required. Enable in Settings.", bundle: bundle)
                .font(.caption)
                .foregroundColor(.white)
            Spacer()
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Text("Settings", bundle: bundle)
                    .font(.caption.bold())
                    .foregroundColor(.yellow)
            }
        }
        .padding(10)
        .background(Color.red.opacity(0.9))
        .cornerRadius(8)
        .padding(.horizontal)
        .padding(.top, 8)
    }
}

// MARK: - Location Unavailable Banner (airplane mode / no GPS fix)
private struct LocationUnavailableBanner: View {
    @Environment(\.languageBundle) private var bundle

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "airplane")
                .foregroundColor(.white)
            VStack(alignment: .leading, spacing: 2) {
                Text("Location signal lost", bundle: bundle)
                    .font(.caption.bold())
                    .foregroundColor(.white)
                Text("Alarms will resume when GPS is available.", bundle: bundle)
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.85))
            }
            Spacer()
        }
        .padding(10)
        .background(Color.orange.opacity(0.92))
        .cornerRadius(8)
        .padding(.horizontal)
        .padding(.top, 8)
    }
}

// MARK: - Syncing with iCloud Banner (non-blocking container resolve in progress)

/// Shown while NapStopApp is resolving the real CloudKit-backed store in
/// the background after launching on a temporary placeholder — see
/// ModelContainerFactory.resolveCloudKitContainerPatiently and
/// NapStopApp.resolveCloudKitContainerIfNeeded (2026-08-24, non-blocking
/// iCloud sync architecture). Styled to match LocationUnavailableBanner
/// above (Bob: "like location banner"), one severity step down — informational
/// blue rather than a warning color, since nothing is actually wrong here:
/// the app is fully usable on the placeholder the whole time this shows.
private struct SyncingWithiCloudBanner: View {
    @Environment(\.languageBundle) private var bundle

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "icloud.and.arrow.down")
                .foregroundColor(.white)
            VStack(alignment: .leading, spacing: 2) {
                Text("Syncing with iCloud", bundle: bundle)
                    .font(.caption.bold())
                    .foregroundColor(.white)
                Text("Your alarms will appear shortly.", bundle: bundle)
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.85))
            }
            Spacer()
        }
        .padding(10)
        .background(Color.blue.opacity(0.9))
        .cornerRadius(8)
        .padding(.horizontal)
        .padding(.top, 8)
    }
}

#Preview {
    ContentView()
        .environmentObject(LocationManager())
        .environmentObject(AlarmManager())
}
