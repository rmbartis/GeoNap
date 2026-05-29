// OnboardingView.swift
// Shown once on first launch.
// Page 0: language picker
// Pages 1–4: feature highlights + location permission request

import SwiftUI

struct OnboardingView: View {

    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @EnvironmentObject var locationManager: LocationManager
    @EnvironmentObject var languageManager: LanguageManager
    @Environment(\.languageBundle) private var bundle
    @State private var page = 0

    // The four feature-explanation slides (indices 1–4 in the TabView)
    private let featurePages: [OnboardingPage] = [
        OnboardingPage(
            symbol: "zzz",
            symbolColor: .indigo,
            titleKey: "Sleep through your commute",
            bodyKey: "NapStop wakes you up when your device enters or leaves a location — not at a set time. Perfect for trains, buses, and long rides."
        ),
        OnboardingPage(
            symbol: "mappin.and.ellipse",
            symbolColor: .red,
            titleKey: "Set an alarm anywhere",
            bodyKey: "Drop a pin on any stop, station, or landmark. Choose how close you need to be before the alarm fires, and whether it should repeat every trip."
        ),
        OnboardingPage(
            symbol: "clock.badge.checkmark",
            symbolColor: .teal,
            titleKey: "Active time windows",
            bodyKey: "Only want the alarm to fire during your morning commute? Set a time window and NapStop will ignore the location outside those hours."
        ),
        OnboardingPage(
            symbol: "location.fill",
            symbolColor: .orange,
            titleKey: "Always On location needed",
            bodyKey: "NapStop monitors your position in the background so it can alert you even while your phone is locked. Your location is never shared or stored outside the app."
        )
    ]

    // Total pages = language picker (0) + feature pages (1…N)
    private var totalPages: Int { featurePages.count + 1 }
    private var isLastPage: Bool { page == totalPages - 1 }

    var body: some View {
        VStack(spacing: 0) {

            TabView(selection: $page) {
                // Page 0 — language picker
                languagePickerPage
                    .tag(0)

                // Pages 1–4 — feature slides
                ForEach(featurePages.indices, id: \.self) { i in
                    featurePageView(featurePages[i])
                        .tag(i + 1)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            // Bottom action buttons
            VStack(spacing: 12) {
                if !isLastPage {
                    Button {
                        withAnimation { page += 1 }
                    } label: {
                        Text("Next", bundle: bundle)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Button {
                        hasSeenOnboarding = true
                    } label: {
                        Text("Skip", bundle: bundle)
                    }
                    .foregroundStyle(.secondary)
                } else {
                    Button {
                        locationManager.requestAlwaysAuthorization()
                        hasSeenOnboarding = true
                    } label: {
                        Text("Allow location access", bundle: bundle)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Button {
                        hasSeenOnboarding = true
                    } label: {
                        Text("Not now", bundle: bundle)
                    }
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 48)
            .padding(.top, 16)
        }
    }

    // MARK: - Language picker page

    private var languagePickerPage: some View {
        VStack(spacing: 20) {
            Spacer()

            VStack(spacing: 8) {
                Image(systemName: "globe")
                    .font(.system(size: 52))
                    .foregroundStyle(.blue)

                Text("Choose Your Language", bundle: bundle)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)

                Text("Select the language you'd like to use in NapStop. You can change this at any time in Settings.", bundle: bundle)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            }

            // Language grid — two columns
            let columns = [GridItem(.flexible()), GridItem(.flexible())]
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(AppLanguage.allCases) { lang in
                    languageCell(lang)
                }
            }
            .padding(.horizontal, 24)

            Spacer()
        }
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private func languageCell(_ lang: AppLanguage) -> some View {
        let isSelected = languageManager.currentLanguage == lang
        Button {
            languageManager.setLanguage(lang)
        } label: {
            HStack(spacing: 8) {
                Text(lang.flag)
                    .font(.title3)
                Text(lang.displayName)
                    .font(.subheadline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Color.accentColor.opacity(0.15) : Color(.secondarySystemGroupedBackground))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Feature slide layout

    @ViewBuilder
    private func featurePageView(_ p: OnboardingPage) -> some View {
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
                Text(LocalizedStringKey(p.titleKey), bundle: bundle)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)

                Text(LocalizedStringKey(p.bodyKey), bundle: bundle)
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
    let titleKey:    String
    let bodyKey:     String
}

#Preview {
    OnboardingView()
        .environmentObject(LocationManager())
        .environmentObject(LanguageManager.shared)
}
