// ContentView.swift
// Root navigation shell for the app.

import SwiftUI
import CoreLocation

struct ContentView: View {
    @EnvironmentObject var locationManager: LocationManager
    @EnvironmentObject var alarmManager: AlarmManager

    var body: some View {
        NavigationStack {
            AlarmListView()
                .navigationTitle("Geo Alarms")
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        NavigationLink(destination: AddAlarmView()) {
                            Image(systemName: "plus")
                        }
                    }
                    #if DEBUG
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Test Fire") {
                            if let first = alarmManager.alarms.first(where: { $0.isActive }) {
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
        }
        // Show a banner if location permission is denied
        .overlay(alignment: .top) {
            if locationManager.authorizationStatus == .denied ||
               locationManager.authorizationStatus == .restricted {
                LocationPermissionBanner()
            }
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

#Preview {
    ContentView()
        .environmentObject(LocationManager())
        .environmentObject(AlarmManager())
}
