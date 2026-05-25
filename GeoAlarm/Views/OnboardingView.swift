// OnboardingView.swift
// Shown once on first launch. Explains the app and requests Always On location.

import SwiftUI

struct OnboardingView: View {

    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @EnvironmentObject var locationManager: LocationManager
    @State private var page = 0

    private let pages: [OnboardingPage] = [
        OnboardingPage(
            symbol: "zzz",
            symbolColor: .indigo,
            title: "Sleep through your commute",
            body: "GeoAlarm wakes you up when your device enters or leaves a location — not at a set time. Perfect for trains, buses, and long rides."
        ),
        OnboardingPage(
            symbol: "mappin.and.ellipse",
            symbolColor: .red,
            title: "Set an alarm anywhere",
            body: "Drop a pin on any stop, station, or landmark. Choose how close you need to be before the alarm fires, and whether it should repeat every trip."
        ),
        OnboardingPage(
            symbol: "clock.badge.checkmark",
            symbolColor: .teal,
            title: "Active time windows",
            body: "Only want the alarm to fire during your morning commute? Set a time window and GeoAlarm will ignore the location outside those hours."
        ),
        OnboardingPage(
            symbol: "location.fill",
            symbolColor: .orange,
            title: "Always On location needed",
            body: "GeoAlarm monitors your position in the background so it can alert you even while your phone is locked. Your location is never shared or stored outside the app."
        )
    ]

    var body: some View {
        VStack(spacing: 0) {

            // Pages
            TabView(selection: $page) {
                ForEach(pages.indices, id: \.self) { i in
                    pageView(pages[i]).tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            // Bottom action
            VStack(spacing: 12) {
                if page < pages.count - 1 {
                    Button("Next") {
                        withAnimation { page += 1 }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)

                    Button("Skip") {
                        hasSeenOnboarding = true
                    }
                    .foregroundStyle(.secondary)
                } else {
                    Button("Allow location access") {
                        locationManager.requestAlwaysAuthorization()
                        hasSeenOnboarding = true
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)

                    Button("Not now") {
                        hasSeenOnboarding = true
                    }
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 48)
            .padding(.top, 16)
        }
    }

    // MARK: - Page layout

    @ViewBuilder
    private func pageView(_ p: OnboardingPage) -> some View {
        VStack(spacing: 24) {
            Spacer()

            ZStack {
                Circle()
                    .fill(p.symbolColor.opacity(0.12))
                    .frame(width: 120, height: 120)
                Image(systemName: p.symbol)
                    .font(.system(size: 52))
                    .foregroundStyle(p.symbolColor)
            }

            VStack(spacing: 12) {
                Text(p.title)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)

                Text(p.body)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            }

            Spacer()
            Spacer()
        }
        .padding(.horizontal, 32)
    }
}

// MARK: - Page model

private struct OnboardingPage {
    let symbol:      String
    let symbolColor: Color
    let title:       String
    let body:        String
}

#Preview {
    OnboardingView()
        .environmentObject(LocationManager())
}
