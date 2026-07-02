// PrivacyView.swift
// Full in-app privacy & location-sharing disclosure document.
// Accessible from Settings, near the Help button.

import SwiftUI

struct PrivacyView: View {
    @Environment(\.languageBundle) private var bundle

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {

                // MARK: Intro
                intro

                Divider()

                privacySection(icon: "location.fill",      iconColor: .blue,
                               titleKey: "Location Data",          bodyKey: "privacy.body.locationData")
                Divider()
                privacySection(icon: "internaldrive.fill", iconColor: .gray,
                               titleKey: "On-Device Storage",      bodyKey: "privacy.body.onDeviceStorage")
                Divider()
                privacySection(icon: "icloud.fill",        iconColor: .cyan,
                               titleKey: "iCloud Sync",            bodyKey: "privacy.body.iCloudSync")
                Divider()
                privacySection(icon: "tram.fill",          iconColor: .teal,
                               titleKey: "Transit Feed Downloads", bodyKey: "privacy.body.transitFeeds")
                Divider()
                privacySection(icon: "bell.fill",          iconColor: .red,
                               titleKey: "Notifications",          bodyKey: "privacy.body.notifications")
                Divider()
                privacySection(icon: "chart.bar.fill",     iconColor: .indigo,
                               titleKey: "Analytics & Crash Reporting", bodyKey: "privacy.body.analytics")
                Divider()
                privacySection(icon: "trash.fill",         iconColor: .orange,
                               titleKey: "Deleting Your Data",     bodyKey: "privacy.body.dataDeletion")
                Divider()
                privacySection(icon: "calendar.badge.clock", iconColor: .mint,
                               titleKey: "Calendar Access",        bodyKey: "privacy.body.calendarAccess")
                Divider()

                // MARK: Contact
                VStack(alignment: .leading, spacing: 8) {
                    Text("Questions", bundle: bundle)
                        .font(.headline)
                    Text(LocalizedStringKey("privacy.body.contact"), bundle: bundle)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 32)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
        }
        .navigationTitle(Text("Privacy & Location", bundle: bundle))
        .navigationBarTitleDisplayMode(.large)
    }

    // MARK: - Intro header

    private var intro: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "lock.shield.fill")
                    .font(.title2)
                    .foregroundColor(.green)
                Text("Your privacy matters", bundle: bundle)
                    .font(.title2.bold())
            }
            Text(LocalizedStringKey("privacy.intro"), bundle: bundle)
                .font(.body)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Section builder

    private func privacySection(
        icon: String,
        iconColor: Color,
        titleKey: String,
        bodyKey: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundColor(iconColor)
                    .frame(width: 22)
                Text(LocalizedStringKey(titleKey), bundle: bundle)
                    .font(.headline)
            }
            Text(LocalizedStringKey(bodyKey), bundle: bundle)
                .font(.body)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview {
    NavigationStack {
        PrivacyView()
    }
}
