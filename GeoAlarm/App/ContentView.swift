// ContentView.swift
// Root navigation shell for the app.

import SwiftUI
import CoreLocation

struct ContentView: View {
    @EnvironmentObject var locationManager: LocationManager
    @EnvironmentObject var alarmManager: AlarmManager

    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @State private var showSettings      = false
    @State private var showMapOverview   = false
    @State private var showTransitAlarm  = false
    @State private var showAddAlarm      = false

    var body: some View {
        NavigationStack {
            AlarmListView()
                .navigationTitle("Geo Alarms")
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
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Menu {
                            Button {
                                showAddAlarm = true
                            } label: {
                                Label("Location Alarm", systemImage: "mappin.and.ellipse")
                            }
                            Button {
                                showTransitAlarm = true
                            } label: {
                                Label("Transit Alarm", systemImage: "tram.fill")
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
                    #if DEBUG
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Test Fire") {
                            // Pick first alarm regardless of state, reset it to
                            // active first so it can always be test-fired again.
                            if let first = alarmManager.alarms.first {
                                first.state = .active
                                alarmManager.handleRegionEvent(
                                    regionID: first.id.uuidString,
                                    event: first.regionEvent
                                )
                            }
                        }
                        .foregroundColor(.red)
                    }
                    #endif
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
    }
}

// MARK: - Permission Warning Banner
private struct LocationPermissionBanner: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "location.slash.fill")
                .foregroundColor(.white)
            Text("Location access required. Enable in Settings.")
                .font(.caption)
                .foregroundColor(.white)
            Spacer()
            Button("Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .font(.caption.bold())
            .foregroundColor(.yellow)
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
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "airplane")
                .foregroundColor(.white)
            VStack(alignment: .leading, spacing: 2) {
                Text("Location signal lost")
                    .font(.caption.bold())
                    .foregroundColor(.white)
                Text("Alarms will resume when GPS is available.")
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
