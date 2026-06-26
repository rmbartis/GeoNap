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
                                    Text("Transit Alarm", bundle: bundle)
                                } icon: {
                                    Image(systemName: "tram.fill")
                                }
                            }
                        } label: {
                            Image(systemName: "plus")
                        }
                        .disabled(alarmManager.isAtRegionLimit)
                        .opacity(alarmManager.isAtRegionLimit ? 0.35 : 1)
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
