// HelpView.swift
// Scrollable help guide covering app concept, use cases, and controls.

import SwiftUI

struct HelpView: View {
    @Environment(\.languageBundle) private var bundle
    @State private var copied = false

    // All sections in order — used to build the full text for copying.
    private var sections: [(titleKey: String, bodyKey: String)] { [
        ("What is GeoNap?",                     "help.body.whatIsNapAlarm"),
        ("Typical use cases",                   "help.body.useCases"),
        ("Creating an alarm",                   "help.body.creatingAlarm"),
        ("Trigger: distance or time",           "help.body.timeBased"),
        ("Radius",                              "help.body.radius"),
        ("Repeat",                              "help.body.repeat"),
        ("Active time window",                  "help.body.timeWindow"),
        ("Transit Alarms",                      "help.body.transitAlarms"),
        ("Auto-Notify",                         "help.body.autoNotify"),
        ("Notifications",                       "help.body.notifications"),
        ("Alarm sound / vibrate",               "help.body.soundVibrate"),
        ("Siri & Shortcuts",                    "help.body.siri"),
        ("Apple Home Automation",               "help.body.appleAutomation"),
        ("Managing alarms",                     "help.body.managingAlarms"),
        ("Alarm list icons",                    "help.body.alarmIcons"),
        ("Settings",                            "help.body.settings"),
        ("Always On location",                  "help.body.alwaysOnLocation"),
        ("Minimum Requirements",                "help.body.minimumRequirements"),
        ("Feature Summary",                     "help.body.featureSummary"),
        ("Reporting a problem",                 "help.body.reportingProblem"),
    ] }

    private var fullHelpText: String {
        sections.map { s in
            let title = NSLocalizedString(s.titleKey, bundle: bundle, comment: "")
            let body  = NSLocalizedString(s.bodyKey,  bundle: bundle, comment: "")
            return "\(title)\n\(body)"
        }.joined(separator: "\n\n")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {

                helpSection(symbol: "lightbulb",   color: .yellow,
                            titleKey: "What is GeoNap?",     bodyKey: "help.body.whatIsNapAlarm")
                helpSection(symbol: "tram",         color: .blue,
                            titleKey: "Typical use cases",    bodyKey: "help.body.useCases")
                helpSection(symbol: "plus.circle",  color: .green,
                            titleKey: "Creating an alarm",    bodyKey: "help.body.creatingAlarm")
                helpSection(symbol: "timer",        color: .mint,
                            titleKey: "Trigger: distance or time", bodyKey: "help.body.timeBased")
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
                helpSection(symbol: "bell.badge",   color: .red,
                            titleKey: "Notifications",        bodyKey: "help.body.notifications")
                helpSection(symbol: "bell.badge.waveform", color: .pink,
                            titleKey: "Alarm sound / vibrate", bodyKey: "help.body.soundVibrate")
                helpSection(symbol: "mic",          color: .indigo,
                            titleKey: "Siri & Shortcuts",     bodyKey: "help.body.siri")
                helpSection(symbol: "house.fill",   color: .orange,
                            titleKey: "Apple Home Automation", bodyKey: "help.body.appleAutomation")
                helpSection(symbol: "hand.point.left", color: .cyan,
                            titleKey: "Managing alarms",      bodyKey: "help.body.managingAlarms")
                helpSection(symbol: "list.bullet.rectangle", color: .indigo,
                            titleKey: "Alarm list icons",     bodyKey: "help.body.alarmIcons")
                helpSection(symbol: "gear",         color: .gray,
                            titleKey: "Settings",             bodyKey: "help.body.settings")
                helpSection(symbol: "location.fill", color: .orange,
                            titleKey: "Always On location",   bodyKey: "help.body.alwaysOnLocation")
                helpSection(symbol: "iphone.and.ipad", color: .gray,
                            titleKey: "Minimum Requirements", bodyKey: "help.body.minimumRequirements")
                helpSection(symbol: "list.star",    color: .blue,
                            titleKey: "Feature Summary",      bodyKey: "help.body.featureSummary")
                helpSection(symbol: "doc.text.magnifyingglass", color: .orange,
                            titleKey: "Reporting a problem",  bodyKey: "help.body.reportingProblem")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .navigationTitle(Text("Help", bundle: bundle))
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    UIPasteboard.general.string = fullHelpText
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
                } label: {
                    Image(systemName: copied ? "checkmark.circle.fill" : "doc.on.doc")
                        .foregroundStyle(copied ? .green : .primary)
                        .animation(.easeInOut(duration: 0.2), value: copied)
                }
                .accessibilityLabel(copied ? "Copied" : "Copy all help text")
            }
        }
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

