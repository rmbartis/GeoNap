// SettingsView.swift
// User-facing preferences sheet.

import SwiftUI
import ContactsUI

struct SettingsView: View {

    @AppStorage(AppStorageKey.distanceUnit)  private var distanceUnitRaw  = DistanceUnit.imperial.rawValue
    @AppStorage(AppStorageKey.timeFormat)    private var timeFormatRaw    = TimeFormat.twelveHour.rawValue
    @AppStorage(AppStorageKey.coordFormat)   private var coordFormatRaw   = CoordFormat.dd.rawValue
    @AppStorage(AppStorageKey.debugLogging)  private var debugLoggingEnabled = false
    @AppStorage(AppStorageKey.autoSMSAutomationEnabled) private var autoSMSAutomationEnabled = false
    @AppStorage(AppStorageKey.defaultTriggerMode) private var defaultTriggerModeRaw = TriggerMode.distance.rawValue

    @EnvironmentObject private var languageManager: LanguageManager
    @Environment(\.languageBundle) private var bundle

    @Environment(\.dismiss) private var dismiss

    // Controls the confirmation alert shown before logging is enabled
    @State private var showEnableConfirmation = false
    // Controls the share sheet for exporting the log file
    // Controls the "log cleared" feedback
    @State private var showClearedBanner = false

    // Info popover state — one Bool per setting row
    @State private var infoDistance    = false
    @State private var infoTriggerMode = false
    @State private var infoCoords      = false
    @State private var infoClock       = false
    @State private var infoLanguage    = false
    @State private var infoDebugLog    = false

    // Auto-Notify Defaults state
    @State private var defaultContacts: [NotifyContact]  = []
    @State private var showContactPicker  = false
    @State private var showManualEntry    = false

    private var distanceUnit: DistanceUnit {
        DistanceUnit(rawValue: distanceUnitRaw) ?? .imperial
    }

    private var coordFormat: CoordFormat {
        CoordFormat(rawValue: coordFormatRaw) ?? .dd
    }

    private var timeFormat: TimeFormat {
        TimeFormat(rawValue: timeFormatRaw) ?? .twelveHour
    }

    private var buildTimestamp: String { Build.timestamp }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {

                // MARK: Units
                Section {
                    Picker(selection: $distanceUnitRaw) {
                        ForEach(DistanceUnit.allCases) { unit in
                            Text(unit.label).tag(unit.rawValue)
                        }
                    } label: {
                        SettingInfoLabel(
                            title: "Distance",
                            isPresented: $infoDistance,
                            helpTitle: "Distance Unit",
                            helpBody: "Controls how the alarm radius is displayed and entered.\n\n• Metric — metres (m) and kilometres (km)\n• Imperial — feet (ft) and miles (mi)\n\nSwitching units does not change any saved alarm radii — values are always stored in metres internally."
                        )
                    }

                    Picker(selection: $coordFormatRaw) {
                        ForEach(CoordFormat.allCases) { fmt in
                            Text(fmt.label).tag(fmt.rawValue)
                        }
                    } label: {
                        SettingInfoLabel(
                            title: "Coordinates",
                            isPresented: $infoCoords,
                            helpTitle: "Coordinate Format",
                            helpBody: "Sets how geographic coordinates are entered and displayed when creating alarms.\n\n• DD – Decimal Degrees (40.712800, -74.006000)\nStandard format used by Google Maps, Apple Maps, and most GPS apps.\n\n• DMS – Degrees Minutes Seconds (40°42′46″N)\nTraditional map format used on paper charts and military navigation.\n\n• DDM – Degrees Decimal Minutes (40°42.767′N)\nCommon on handheld Garmin GPS devices and marine/aviation equipment.\n\nDD is recommended for most users."
                        )
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Units", bundle: bundle)
                } footer: {
                    Text("DD = Decimal Degrees  ·  DMS = Degrees Minutes Seconds  ·  DDM = Degrees Decimal Minutes", bundle: bundle)
                }

                // MARK: Alarm Trigger
                Section {
                    Picker(selection: $defaultTriggerModeRaw) {
                        ForEach(TriggerMode.allCases) { mode in
                            Text(NSLocalizedString(mode.localizationKey, bundle: bundle, comment: ""))
                                .tag(mode.rawValue)
                        }
                    } label: {
                        SettingInfoLabel(
                            title: "Trigger by",
                            isPresented: $infoTriggerMode,
                            helpTitle: "Alarm trigger",
                            helpBody: "Sets how new alarms are defined on the creation screen.\n\n• Distance (radius) — fire when you get within a set distance of the location (the original behavior).\n• Time (before arrival) — fire a chosen number of minutes before you arrive, estimated from your travel speed.\n\nTime mode briefly uses extra GPS as you approach the destination, which uses more battery. Existing alarms keep their own setting."
                        )
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Alarm Trigger", bundle: bundle)
                } footer: {
                    Text("trigger.mode.footer", bundle: bundle)
                }

                // MARK: Time
                Section {
                    Picker(selection: $timeFormatRaw) {
                        ForEach(TimeFormat.allCases) { format in
                            Text(format.label).tag(format.rawValue)
                        }
                    } label: {
                        SettingInfoLabel(
                            title: "Clock",
                            isPresented: $infoClock,
                            helpTitle: "Clock Format",
                            helpBody: "Controls how times are shown in alarm time windows.\n\n• 12-hour — uses AM/PM notation (e.g. 7:30 AM, 11:45 PM)\n• 24-hour — uses military time notation (e.g. 07:30, 23:45)\n\nThis setting does not affect your iPhone's system clock — it only changes how times appear inside GeoNap."
                        )
                    }
                } header: {
                    Text("Time", bundle: bundle)
                } footer: {
                    Text("Tap ⓘ next to the setting for more information.", bundle: bundle)
                }

                // MARK: Language
                Section {
                    Picker(selection: Binding(
                        get: { languageManager.currentLanguage },
                        set: { newLang in
                            // Flag BEFORE the change so the .id() rebuild (which
                            // dismisses this sheet) is followed by ContentView
                            // re-presenting Settings — keeping the user in place.
                            if newLang != languageManager.currentLanguage {
                                languageManager.pendingReturnToSettings = true
                            }
                            languageManager.setLanguage(newLang)
                        }
                    )) {
                        ForEach(AppLanguage.allCases) { lang in
                            Label {
                                Text(lang.displayName)
                            } icon: {
                                Text(lang.flag)
                            }
                            .tag(lang)
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "globe")
                                .foregroundStyle(.blue)
                            SettingInfoLabel(
                                title: "Language",
                                isPresented: $infoLanguage,
                                helpTitle: "In-App Language",
                                helpBody: "Changes the display language used throughout GeoNap — independently of your iPhone's system language.\n\nAffects all text including menus, alarm creation, help articles, and notification messages.\n\nCurrently supported: English, Spanish, French, German, Italian, Portuguese, Arabic, Hindi, Japanese, Simplified Chinese, Russian, Thai, and Vietnamese."
                            )
                        }
                    }
                }

                // MARK: Auto-Notify Defaults
                Section {
                    ForEach(defaultContacts) { contact in
                        defaultContactRow(contact)
                    }
                    .onDelete { offsets in
                        let removed = offsets.map { defaultContacts[$0].name }
                        defaultContacts.remove(atOffsets: offsets)
                        defaultContacts.saveAsGlobalDefaults()
                        DebugLogger.shared.log("Default Auto-Notify contact removed: \(removed.joined(separator: ", "))", category: "UI")
                    }

                    Button {
                        showContactPicker = true
                    } label: {
                        Label {
                            Text("Add from Contacts", bundle: bundle)
                        } icon: {
                            Image(systemName: "person.crop.circle.badge.plus")
                        }
                    }

                    Button {
                        showManualEntry = true
                    } label: {
                        Label {
                            Text("Add Manually", bundle: bundle)
                        } icon: {
                            Image(systemName: "plus.circle")
                        }
                    }
                } header: {
                    Text("Auto-Notify Defaults", bundle: bundle)
                } footer: {
                    Text("Contacts listed here are pre-filled when you enable Auto-Notify on a new alarm. When an alarm fires, all listed contacts are messaged automatically. You can adjust the list per-alarm.",
                         bundle: bundle)
                }

                // MARK: Auto-SMS (Shortcuts automation)
                autoSMSSection

                // MARK: Help & Legal
                Section {
                    NavigationLink(destination: HelpView()) {
                        Label {
                            Text("Help & User Guide", bundle: bundle)
                        } icon: {
                            Image(systemName: "questionmark.circle")
                        }
                    }
                    NavigationLink(destination: PrivacyView()) {
                        Label {
                            Text("Privacy & Location Sharing", bundle: bundle)
                        } icon: {
                            Image(systemName: "lock.shield")
                        }
                    }
                }

                // MARK: Debug Logging
                debugSection

                // MARK: About
                Section {
                    LabeledContent {
                        Text(buildTimestamp)
                            .foregroundStyle(.secondary)
                            .font(.system(.body, design: .monospaced))
                    } label: {
                        Text("Build", bundle: bundle)
                    }
                } header: {
                    Text("About", bundle: bundle)
                }

                // MARK: Preview
                Section {
                    LabeledContent {
                        Text(distanceUnit.formatted(meters: 500))
                            .foregroundStyle(.secondary)
                    } label: {
                        Text("Sample radius", bundle: bundle)
                    }
                    LabeledContent {
                        Text(timeFormat.formatTime(Date()))
                            .foregroundStyle(.secondary)
                    } label: {
                        Text("Sample time", bundle: bundle)
                    }
                    LabeledContent {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(CoordinateParser.format(latitude:  40.712800, format: coordFormat))
                                .foregroundStyle(.secondary)
                            Text(CoordinateParser.format(longitude: -74.006000, format: coordFormat))
                                .foregroundStyle(.secondary)
                        }
                        .font(.system(.caption, design: .monospaced))
                    } label: {
                        Text("Sample coords", bundle: bundle)
                    }
                } header: {
                    Text("Preview", bundle: bundle)
                }
            }
            .navigationTitle(Text("Settings", bundle: bundle))
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                defaultContacts = [NotifyContact].loadGlobalDefaults()
            }
            .onChange(of: distanceUnitRaw) { _, newValue in
                DebugLogger.shared.log("Setting changed: Distance unit → \(newValue)", category: "UI")
            }
            .onChange(of: coordFormatRaw) { _, newValue in
                DebugLogger.shared.log("Setting changed: Coordinate format → \(newValue)", category: "UI")
            }
            .onChange(of: timeFormatRaw) { _, newValue in
                DebugLogger.shared.log("Setting changed: Clock format → \(newValue)", category: "UI")
            }
            .background(
                ContactPickerView(isPresented: $showContactPicker) { contact in
                    addDefaultContact(contact)
                }
            )
            .sheet(isPresented: $showManualEntry) {
                AddContactManuallySheet { contact in
                    addDefaultContact(contact)
                }
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text("Done", bundle: bundle)
                    }
                }
            }
            // Confirmation dialog shown before enabling logging
            .alert(Text("Enable Debug Logging?", bundle: bundle), isPresented: $showEnableConfirmation) {
                Button {
                    debugLoggingEnabled = true
                    DebugLogger.shared.isEnabled = true
                } label: {
                    Text("Enable Logging", bundle: bundle)
                }
                Button(role: .cancel) {
                    // Leave the toggle off — don't enable
                    debugLoggingEnabled = false
                } label: {
                    Text("Cancel", bundle: bundle)
                }
            } message: {
                Text("""
                    GeoNap will record detailed activity — location events, alarm triggers, \
                    transit feed downloads, and errors — to a log file on your device.

                    The file is stored at:
                    Files → On My iPhone → GeoNap → GeoNapDebug.log

                    This information is not sent anywhere automatically. \
                    If support requests it, you can find and share the file using the iOS Files app.
                    """, bundle: bundle)
            }
        }
    }

    // MARK: - Auto-Notify helpers

    @ViewBuilder
    private func defaultContactRow(_ contact: NotifyContact) -> some View {
        HStack(spacing: 12) {
            Image(systemName: contact.systemImage)
                .foregroundStyle(.blue)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(contact.name)
                    .font(.body)
                Text(contact.value)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func addDefaultContact(_ contact: NotifyContact) {
        // Email contacts are not supported — phone/SMS only.
        guard !contact.isEmail else { return }
        guard !defaultContacts.contains(where: { $0.value == contact.value }) else { return }
        defaultContacts.append(contact)
        defaultContacts.saveAsGlobalDefaults()
        DebugLogger.shared.log("Default Auto-Notify contact added: '\(contact.name)'", category: "UI")
    }

    // MARK: - Debug section

    private var debugSection: some View {
        Section {
            // Toggle — intercept the "turning on" gesture to show the confirmation dialog
            Toggle(isOn: loggingToggleBinding) {
                Label {
                    SettingInfoLabel(
                        title: "Enable Debug Log",
                        isPresented: $infoDebugLog,
                        helpTitle: "Debug Logging",
                        helpBody: "Records detailed diagnostic information to a private log file stored only on your device.\n\nWhat is logged:\n• Location events and region crossings\n• Alarm trigger and snooze activity\n• Transit feed downloads\n• Errors and warnings\n\nFile location:\nGeoNapDebug.log in the app's Documents folder. You can also access it in the Files app under GeoNap → On My iPhone.\n\nNothing is sent automatically. If support requests it, share the log via the 'Share Log with Support' button that appears below when logging is enabled.\n\nLogging is off by default and does not run in the background when the app is closed. Disable it again once your issue is resolved."
                    )
                } icon: {
                    Image(systemName: "doc.text.magnifyingglass")
                }
            }

            if debugLoggingEnabled {
                // Log file size
                LabeledContent {
                    Text(DebugLogger.shared.logFileSizeString)
                        .foregroundStyle(.secondary)
                } label: {
                    Text("Log file size", bundle: bundle)
                }

                // Share log button
                if FileManager.default.fileExists(atPath: DebugLogger.shared.logFileURL.path) {
                    ShareLink(
                        item: DebugLogger.shared.logFileURL,
                        subject: Text("GeoNap Debug Log"),
                        message: Text("Debug log from GeoNap")
                    ) {
                        Label {
                            Text("Share Log with Support", bundle: bundle)
                        } icon: {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                }

                // Clear log button
                Button(role: .destructive) {
                    DebugLogger.shared.clearLog()
                    showClearedBanner = true
                } label: {
                    Label {
                        Text("Clear Log", bundle: bundle)
                    } icon: {
                        Image(systemName: "trash")
                    }
                }
                .alert(Text("Log Cleared", bundle: bundle), isPresented: $showClearedBanner) {
                    Button(role: .cancel) {} label: {
                        Text("OK", bundle: bundle)
                    }
                } message: {
                    Text("The debug log has been cleared. A new session header will be written on the next log entry.", bundle: bundle)
                }
            }

        } header: {
            Text("Support", bundle: bundle)
        } footer: {
            if debugLoggingEnabled {
                Text("Logging is ON. Detailed activity is being recorded to GeoNapDebug.log in the GeoNap folder in the Files app. Disable when no longer needed.", bundle: bundle)
                    .foregroundStyle(.orange)
            } else {
                Text("Enable to capture detailed diagnostic information when troubleshooting an issue. Logging is off by default and does not run in the background.", bundle: bundle)
            }
        }
    }

    // MARK: - Auto-SMS section

    private var autoSMSSection: some View {
        Section {
            // Hands-free switch: when on, the app suppresses its own pre-filled
            // compose sheet because the Shortcuts automation sends the SMS instead.
            Toggle(isOn: $autoSMSAutomationEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("settings.autoSMS.automationToggle", bundle: bundle)
                    Text("settings.autoSMS.automationToggleHelp", bundle: bundle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Step-by-step instructions
            VStack(alignment: .leading, spacing: 10) {
                Text("settings.autoSMS.description", bundle: bundle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Divider()

                Text("settings.autoSMS.setupTitle", bundle: bundle)
                    .font(.subheadline.weight(.medium))

                VStack(alignment: .leading, spacing: 6) {
                    AutoSMSStep(number: "1", textKey: "settings.autoSMS.step1")
                    AutoSMSStep(number: "2", textKey: "settings.autoSMS.step2")
                    AutoSMSStep(number: "3", textKey: "settings.autoSMS.step3a")
                    AutoSMSStep(number: "  ", textKey: "settings.autoSMS.step3b")
                    AutoSMSStep(number: "4", textKey: "settings.autoSMS.step4a")
                    AutoSMSStep(number: "  ", textKey: "settings.autoSMS.step4b")
                    AutoSMSStep(number: "  ", textKey: "settings.autoSMS.step4c")
                    AutoSMSStep(number: "5", textKey: "settings.autoSMS.step5")
                }
                .font(.subheadline)
            }
            .padding(.vertical, 4)

            // Deep-link button
            Button {
                if let url = URL(string: "shortcuts://create-shortcut") {
                    UIApplication.shared.open(url)
                }
            } label: {
                Label {
                    Text("Open Shortcuts App", bundle: bundle)
                } icon: {
                    Image(systemName: "arrow.up.right.square")
                }
            }
        } header: {
            Text("Auto-SMS (No Approval Needed)", bundle: bundle)
        } footer: {
            Text("settings.autoSMS.footer", bundle: bundle)
                .font(.caption)
        }
    }

    // MARK: - Toggle binding

    /// Custom binding so we can intercept the toggle turning ON and show a
    /// confirmation dialog before actually enabling logging.
    private var loggingToggleBinding: Binding<Bool> {
        Binding(
            get: { debugLoggingEnabled },
            set: { newValue in
                if newValue {
                    // Show the confirmation dialog — don't enable yet.
                    showEnableConfirmation = true
                } else {
                    // Turning off: disable immediately, no dialog needed.
                    debugLoggingEnabled = false
                    DebugLogger.shared.isEnabled = false
                }
            }
        )
    }
}


// MARK: - Auto-SMS step row

private struct AutoSMSStep: View {
    let number: String
    let textKey: String

    @Environment(\.languageBundle) private var bundle

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Text(number)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 16, alignment: .trailing)
            Text(NSLocalizedString(textKey, bundle: bundle, comment: ""))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Reusable info label with popover

private struct SettingInfoLabel: View {
    let title: String
    @Binding var isPresented: Bool
    let helpTitle: String
    let helpBody: String

    @Environment(\.languageBundle) private var bundle

    var body: some View {
        HStack(spacing: 6) {
            Text(NSLocalizedString(title, bundle: bundle, comment: ""))
            Button {
                isPresented = true
            } label: {
                Image(systemName: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $isPresented, arrowEdge: .top) {
                SettingHelpSheet(title: helpTitle, message: helpBody)
                    .presentationCompactAdaptation(.popover)
            }
        }
    }
}

private struct SettingHelpSheet: View {
    let title: String
    let message: String          // renamed from 'body' — avoids clash with SwiftUI's var body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(.blue)
                        .font(.title3)
                    Text(title)
                        .font(.headline)
                }
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 280, idealWidth: 320, maxWidth: 400,
               minHeight: 160, idealHeight: 220, maxHeight: 400)
    }
}

#Preview {
    SettingsView()
        .environmentObject(LanguageManager.shared)
}
