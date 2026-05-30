// HelpView.swift
// Scrollable help guide covering app concept, use cases, and controls.

import SwiftUI

struct HelpView: View {
    @Environment(\.languageBundle) private var bundle

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {

                helpSection(symbol: "lightbulb",   color: .yellow,
                            titleKey: "What is NapStop?",    bodyKey: "help.body.whatIsNapAlarm")
                helpSection(symbol: "list.star",    color: .blue,
                            titleKey: "Feature Summary",      bodyKey: "help.body.featureSummary")
                helpSection(symbol: "tram",         color: .blue,
                            titleKey: "Typical use cases",    bodyKey: "help.body.useCases")
                helpSection(symbol: "plus.circle",  color: .green,
                            titleKey: "Creating an alarm",    bodyKey: "help.body.creatingAlarm")
                helpSection(symbol: "arrow.up.left.and.arrow.down.right", color: .teal,
                            titleKey: "Radius",               bodyKey: "help.body.radius")
                helpSection(symbol: "repeat",       color: .indigo,
                            titleKey: "Repeat",               bodyKey: "help.body.repeat")
                helpSection(symbol: "clock",        color: .purple,
                            titleKey: "Active time window",   bodyKey: "help.body.timeWindow")
                helpSection(symbol: "tram.fill",    color: .teal,
                            titleKey: "Transit Alarms",       bodyKey: "help.body.transitAlarms")
                helpSection(symbol: "message.badge.filled.fill", color: .green,
                            titleKey: "Auto-Notify",          bodyKey: "help.body.autoNotify")
                helpSection(symbol: "bell.badge.waveform", color: .pink,
                            titleKey: "Alarm sound / vibrate", bodyKey: "help.body.soundVibrate")
                helpSection(symbol: "mic",          color: .indigo,
                            titleKey: "Siri & Shortcuts",     bodyKey: "help.body.siri")
                helpSection(symbol: "gear",         color: .gray,
                            titleKey: "Settings",             bodyKey: "help.body.settings")
                helpSection(symbol: "doc.text.magnifyingglass", color: .orange,
                            titleKey: "Reporting a problem",  bodyKey: "help.body.reportingProblem")
                helpSection(symbol: "hand.point.left", color: .cyan,
                            titleKey: "Managing alarms",      bodyKey: "help.body.managingAlarms")
                helpSection(symbol: "list.bullet.rectangle", color: .indigo,
                            titleKey: "Alarm list icons",     bodyKey: "help.body.alarmIcons")
                helpSection(symbol: "location.fill", color: .orange,
                            titleKey: "Always On location",   bodyKey: "help.body.alwaysOnLocation")
                helpSection(symbol: "bell.badge",   color: .red,
                            titleKey: "Notifications",        bodyKey: "help.body.notifications")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .navigationTitle(Text("Help", bundle: bundle))
        .navigationBarTitleDisplayMode(.large)
    }

    // MARK: - Section builder

    @ViewBuilder
    private func helpSection(symbol: String, color: Color, titleKey: String, bodyKey: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.title3.bold())
                    .foregroundStyle(color)
                    .frame(width: 28)
                Text(LocalizedStringKey(titleKey), bundle: bundle)
                    .font(.headline)
            }
            Text(LocalizedStringKey(bodyKey), bundle: bundle)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview {
    NavigationStack {
        HelpView()
    }
}
