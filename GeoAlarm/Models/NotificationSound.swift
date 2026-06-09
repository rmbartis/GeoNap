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

    private static let systemIDs: Set<String> = ["vibrate", "default", "critical"]
    var isSystem: Bool { Self.systemIDs.contains(id) }

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
        return Bundle.main
            .paths(forResourcesOfType: "wav", inDirectory: nil)
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
        Bundle.main
            .paths(forResourcesOfType: "wav", inDirectory: nil)
            .map { URL(fileURLWithPath: $0).lastPathComponent }
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
            // bundleRelativeSoundName resolves the correct path regardless of
            // whether Xcode copied the file to the bundle root or a subfolder.
            return UNNotificationSound(named: UNNotificationSoundName(rawValue: bundleRelativeSoundName))
        }
    }
}
