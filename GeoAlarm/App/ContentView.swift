// Copyright © 2026 Robert Bartis. All rights reserved.

// ContentView.swift
// Root navigation shell for the app.

import SwiftUI
import CoreLocation

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

    /// Transit Alarms (the full Agency→Route→Stop GTFS wizard) require
    /// Silver+ — see monetization-tier-pricing memory.
    private var transitAlarmLocked: Bool { !EntitlementManager.isEntitled(to: .silver) }

    var body: some View {
        NavigationStack {
            AlarmListView()
                .navigationTitle(Text("GeoNap", bundle: bundle))
                .sheet(isPresented: $showSettings) {
                    SettingsView()
                }
                .sheet(isPresented: $showMapOverview) {
                    MapOverviewView()
                }
                .sheet(isPresented: $showTransitAlarm) {
                    TransitAlarmSheet()
                }
                .sheet(isPresented: $showCalendarScanReview) {
                    NavigationStack {
                        CalendarScanSettingsView(openReviewOnAppear: true)
                    }
                }
                .navigationDestination(isPresented: $showAddAlarm) {
                    AddAlarmView()
                }
                .navigationDestination(item: $spotlightAlarm) { alarm in
                    AlarmDetailView(alarm: alarm)
                }
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Menu {
                            Button {
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
                                         ? String(format: NSLocalizedString("menu.transitAlarm.locked", bundle: bundle, comment: ""), AppTier.silver.description)
                                         : NSLocalizedString("Transit Alarm", bundle: bundle, comment: ""))
                                } icon: {
                                    Image(systemName: transitAlarmLocked ? "lock.fill" : "tram.fill")
                                }
                            }
                            // Real Button/.disabled() works correctly inside
                            // a Menu (unlike the onTapGesture-based Sound
                            // rows) — Transit Alarms require Silver+ (the
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
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            showMapOverview = true
                        } label: {
                            Image(systemName: "map")
                        }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
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
                if locationManager.authorizationStatus == .denied ||
                   locationManager.authorizationStatus == .restricted {
                    LocationPermissionBanner()
                } else if locationManager.isLocationUnavailable {
                    LocationUnavailableBanner()
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
            if newValue != nil { showMessageCompose = true }
        }
        // Spotlight deep link: when the user taps an alarm in Spotlight search,
        // navigate directly to its detail view.
        .onChange(of: alarmManager.spotlightAlarmID) { _, uuid in
            guard let uuid else { return }
            spotlightAlarm = alarmManager.alarms.first { $0.id == uuid }
            alarmManager.spotlightAlarmID = nil   // consume so back-navigation works
        }
        // Calendar Scanning "new trips found" notification deep link — see
        // CalendarScanNotificationDelegate. Opens straight to the review
        // sheet instead of just landing on the home screen.
        .onReceive(NotificationCenter.default.publisher(for: .calendarScanReviewRequested)) { _ in
            showCalendarScanReview = true
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

#Preview {
    ContentView()
        .environmentObject(LocationManager())
        .environmentObject(AlarmManager())
}
