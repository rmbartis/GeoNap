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

    // MARK: - Display name
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
    static var bundledSounds: [NotificationSound] {
        Bundle.main
            .paths(forResourcesOfType: "wav", inDirectory: nil)
            .map { URL(fileURLWithPath: $0).lastPathComponent }
            .sorted()
            .map { NotificationSound(id: $0) }
    }

    static var all: [NotificationSound] {
        // Explicit var avoids Swift misreading the .default keyword in an array literal
        var list: [NotificationSound] = [.vibrate, .default, .critical]
        list.append(contentsOf: bundledSounds)
        return list
    }

    // MARK: - UNNotificationSound
    var unSound: UNNotificationSound? {
        switch id {
        case "vibrate":  return nil
        case "default":  return .default
        case "critical": return .defaultCritical
        default:
            return UNNotificationSound(named: UNNotificationSoundName(rawValue: id))
        }
    }
}
