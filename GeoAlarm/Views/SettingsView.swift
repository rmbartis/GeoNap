// SettingsView.swift
// User-facing preferences sheet.

import SwiftUI

struct SettingsView: View {

    @AppStorage(AppStorageKey.distanceUnit)  private var distanceUnitRaw = DistanceUnit.metric.rawValue
    @AppStorage(AppStorageKey.timeFormat)    private var timeFormatRaw   = TimeFormat.twelveHour.rawValue
    @AppStorage(AppStorageKey.debugLogging)  private var debugLoggingEnabled = false

    @EnvironmentObject private var languageManager: LanguageManager
    @Environment(\.languageBundle) private var bundle

    @Environment(\.dismiss) private var dismiss

    // Controls the confirmation alert shown before logging is enabled
    @State private var showEnableConfirmation = false
    // Controls the share sheet for exporting the log file
    @State private var shareItems: [Any] = []
    @State private var showShareSheet = false
    // Controls the "log cleared" feedback
    @State private var showClearedBanner = false

    private var distanceUnit: DistanceUnit {
        DistanceUnit(rawValue: distanceUnitRaw) ?? .metric
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
                        Text("Distance", bundle: bundle)
                    }
                } header: {
                    Text("Units", bundle: bundle)
                } footer: {
                    Text("Controls how radius is displayed and entered when creating alarms.", bundle: bundle)
                }

                // MARK: Time
                Section {
                    Picker(selection: $timeFormatRaw) {
                        ForEach(TimeFormat.allCases) { format in
                            Text(format.label).tag(format.rawValue)
                        }
                    } label: {
                        Text("Clock", bundle: bundle)
                    }
                } header: {
                    Text("Time", bundle: bundle)
                } footer: {
                    Text("Used when displaying and entering alarm time windows.", bundle: bundle)
                }

                // MARK: Language
                Section {
                    Picker(selection: Binding(
                        get: { languageManager.currentLanguage },
                        set: { languageManager.setLanguage($0) }
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
                        Label {
                            Text("Language", bundle: bundle)
                        } icon: {
                            Image(systemName: "globe")
                        }
                    }
                }

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
                } header: {
                    Text("Preview", bundle: bundle)
                }
            }
            .navigationTitle(Text("Settings", bundle: bundle))
            .navigationBarTitleDisplayMode(.inline)
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
                    NapStop will record detailed activity — location events, alarm triggers, \
                    transit feed downloads, and errors — to a log file on your device.

                    The file is stored at:
                    Files → On My iPhone → NapStop → NapStopDebug.log

                    This information is not sent anywhere automatically. \
                    If support requests it, you can find and share the file using the iOS Files app.
                    """, bundle: bundle)
            }
            // Share sheet for log export
            .sheet(isPresented: $showShareSheet) {
                ShareSheet(items: shareItems)
            }
        }
    }

    // MARK: - Debug section

    private var debugSection: some View {
        Section {
            // Toggle — intercept the "turning on" gesture to show the confirmation dialog
            Toggle(isOn: loggingToggleBinding) {
                Label {
                    Text("Enable Debug Log", bundle: bundle)
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
                Button {
                    let url = DebugLogger.shared.logFileURL
                    guard FileManager.default.fileExists(atPath: url.path) else { return }
                    shareItems = [url]
                    showShareSheet = true
                } label: {
                    Label {
                        Text("Share Log with Support", bundle: bundle)
                    } icon: {
                        Image(systemName: "square.and.arrow.up")
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
                Text("Logging is ON. Detailed activity is being recorded to NapStopDebug.log in the NapStop folder in the Files app. Disable when no longer needed.", bundle: bundle)
                    .foregroundStyle(.orange)
            } else {
                Text("Enable to capture detailed diagnostic information when troubleshooting an issue. Logging is off by default and does not run in the background.", bundle: bundle)
            }
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

// MARK: - UIActivityViewController wrapper

private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    SettingsView()
        .environmentObject(LanguageManager.shared)
}
