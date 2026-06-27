// NotificationSound.swift
import UserNotifications

struct NotificationSound: Identifiable, Hashable, Codable {

    let id: String

    // Explicit initializers — Swift suppresses the memberwise init
    // when any custom init is defined, so both must be declared.
    init(id: String)       { self.id = id }
    init(rawValue: String) { self.id = rawValue }

    // Backward-compatibility for code that reads .rawValue
    var rawValue: String { id }

    // MARK: - System presets
    static let vibrate   = NotificationSound(id: "vibrate")
    static let `default` = NotificationSound(id: "default")
    static let critical  = NotificationSound(id: "critical")

    /// Bundled WAV used as the looping tone for the "Default" sound. The real
    /// system default sound can't be looped on the locked screen, so "Default"
    /// loops this neutral tone instead. The leading "_" keeps it out of the
    /// user-facing sound picker (see `bundledSounds`).
    static let defaultLoopTone = "_DefaultAlarm.wav"

    /// Bundled WAV of pure digital silence, used for the "Vibrate Only" option
    /// under AlarmKit. AlarmKit always presents an alert *with* a sound (its
    /// `AlertSound` has no "none" case), but the system alarm still vibrates,
    /// so handing it a silent tone yields haptics-only — i.e. vibrate only.
    /// The leading "_" keeps it out of the user-facing picker (see `bundledSounds`).
    static let silentTone = "_Silence.wav"

    private static let systemIDs: Set<String> = ["vibrate", "default", "critical"]
    var isSystem: Bool { Self.systemIDs.contains(id) }

    // MARK: - AlarmKit sound mapping
    /// Filename to hand AlarmKit's `AlertSound.named(_:)`, or `nil` to use
    /// AlarmKit's built-in default alarm tone.
    ///
    /// - `vibrate`  → the reserved silent tone, so the alarm vibrates without an
    ///   audible sound. (Previously `vibrate` collapsed to `nil` → `.default`,
    ///   which made "Vibrate Only" ring out loud — the bug this fixes.)
    /// - `default` / `critical` → `nil` → AlarmKit default tone.
    /// - bundled `.wav` → its own filename.
    var alarmKitSoundName: String? {
        switch id {
        case "vibrate":           return Self.silentTone
        case "default", "critical": return nil
        default:                  return id
        }
    }

    // MARK: - Display name (English fallback / localization key for bundled sounds)
    var displayName: String {
        switch id {
        case "vibrate":  return "Vibrate Only"
        case "default":  return "Default"
        case "critical": return "Critical (ignores silent mode)"
        default:
            return (id as NSString)
                .deletingPathExtension
                .replacingOccurrences(of: "_", with: " ")
                .replacingOccurrences(of: "-", with: " ")
                .capitalized
        }
    }

    /// Key used for looking up a localized display name.
    /// System sounds use explicit keys; bundled sounds use their English display name
    /// (which is also registered as a key in Localizable.strings).
    var localizationKey: String {
        switch id {
        case "vibrate":  return "sound.vibrate"
        case "default":  return "sound.default"
        case "critical": return "sound.critical"
        default:         return displayName   // e.g. "Boat Horn", "Airport Chime"
        }
    }

    // MARK: - SF Symbol
    var systemImage: String {
        switch id {
        case "vibrate":  return "waveform"
        case "default":  return "bell"
        case "critical": return "bell.badge.waveform.fill"
        default:         return "music.note"
        }
    }

    // MARK: - Bundle discovery

    /// Returns the URL of this sound file in the app bundle, regardless of whether
    /// Xcode copied it to the bundle root or preserved it inside a Sounds/ subfolder.
    /// (PBXFileSystemSynchronizedRootGroup in Xcode 16+ preserves directory structure.)
    var bundleURL: URL? {
        guard !isSystem else { return nil }
        // Search both the bundle root AND the Sounds/ subfolder.
        // paths(forResourcesOfType:inDirectory:nil) only scans the top-level resource
        // directory; Xcode 16 PBXFileSystemSynchronizedRootGroup preserves the Sounds/
        // subfolder structure, so WAV files may land in GeoAlarm.app/Sounds/ instead.
        let candidates = Bundle.main.paths(forResourcesOfType: "wav", inDirectory: nil)
                       + Bundle.main.paths(forResourcesOfType: "wav", inDirectory: "Sounds")
        return candidates
            .first { URL(fileURLWithPath: $0).lastPathComponent == id }
            .map { URL(fileURLWithPath: $0) }
    }

    /// Returns the bundle-relative path string needed by UNNotificationSound.
    /// This is "Train Horn.wav" when the file is at the bundle root, or
    /// "Sounds/Train Horn.wav" when it lives in a subfolder.
    var bundleRelativeSoundName: String {
        guard let resourceURL = Bundle.main.resourceURL,
              let url = bundleURL
        else { return id }
        let relative = url.path.replacingOccurrences(of: resourceURL.path + "/", with: "")
        return relative.isEmpty ? id : relative
    }

    static var bundledSounds: [NotificationSound] {
        let allPaths = Bundle.main.paths(forResourcesOfType: "wav", inDirectory: nil)
                     + Bundle.main.paths(forResourcesOfType: "wav", inDirectory: "Sounds")
        return Array(Set(allPaths.map { URL(fileURLWithPath: $0).lastPathComponent }))
            .filter { !$0.hasPrefix("_") }   // exclude reserved tones (e.g. _DefaultAlarm.wav)
            .sorted()
            .map { NotificationSound(id: $0) }
    }

    static var all: [NotificationSound] {
        // .critical is omitted — Apple denied the Critical Alerts entitlement
        // (June 2026). UNNotificationSound.defaultCritical requires that entitlement;
        // without it the sound is silently downgraded and the option is misleading.
        var list: [NotificationSound] = [.vibrate, .default]
        list.append(contentsOf: bundledSounds)
        return list
    }

    // MARK: - UNNotificationSound
    var unSound: UNNotificationSound? {
        switch id {
        case "vibrate":  return nil
        case "default":  return .default
        case "critical": return .default  // Critical Alerts entitlement was denied; fall back to default
        default:
            // Use just the filename (e.g. "Train Horn.wav"), NOT a subfolder path.
            // UNNotificationSound only searches the bundle root and Library/Sounds —
            // subdirectory paths like "Sounds/Train Horn.wav" are silently ignored
            // and fall back to the default sound. installBundledSoundsIfNeeded()
            // (called at app startup) copies files into Library/Sounds so iOS finds them.
            return UNNotificationSound(named: UNNotificationSoundName(rawValue: id))
        }
    }

    // MARK: - Library/Sounds installation

    /// Copies all bundled WAV alarm sounds into the app's Library/Sounds directory
    /// so that UNNotificationSound(named:) can find them at notification delivery time.
    ///
    /// Background: UNNotificationSound only searches the bundle root and Library/Sounds —
    /// it does NOT recurse into subdirectories. Xcode 16's PBXFileSystemSynchronizedRootGroup
    /// preserves the Sounds/ folder structure in the built bundle, so the WAV files land at
    /// e.g. GeoAlarm.app/Sounds/Train Horn.wav rather than GeoAlarm.app/Train Horn.wav.
    /// Promoting them to Library/Sounds once at startup fixes this permanently.
    ///
    /// Safe to call on every launch — files that already exist are skipped.
    static func installBundledSoundsIfNeeded() {
        let fm = FileManager.default
        guard let libraryURL = fm.urls(for: .libraryDirectory, in: .userDomainMask).first else { return }
        let soundsDir = libraryURL.appendingPathComponent("Sounds", isDirectory: true)
        try? fm.createDirectory(at: soundsDir, withIntermediateDirectories: true)
        // Reserved tones are excluded from `bundledSounds` (the user-facing list),
        // but the silent tone still has to be on disk for AlarmKit's `.named(_:)`
        // lookup to resolve it for "Vibrate Only" alarms.
        for sound in bundledSounds + [NotificationSound(id: Self.silentTone)] {
            guard let srcURL = sound.bundleURL else { continue }
            let dstURL = soundsDir.appendingPathComponent(sound.id)
            guard !fm.fileExists(atPath: dstURL.path) else { continue }
            do {
                try fm.copyItem(at: srcURL, to: dstURL)
                DebugLogger.shared.log("Installed alarm sound to Library/Sounds: \(sound.id)", category: "Notifications")
            } catch {
                DebugLogger.shared.log("Failed to install alarm sound '\(sound.id)': \(error.localizedDescription)", category: "Notifications")
            }
        }
    }
}
