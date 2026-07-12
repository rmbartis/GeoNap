// Copyright © 2026 Robert Bartis. All rights reserved.

// SoundPickerSection.swift
// Collapsible sound / vibrate picker for alarm creation forms.
//
// The sound list is built dynamically from NotificationSound.all —
// any .wav file added to NapAlarm/Sounds in Xcode appears automatically.
//
// Playback:
//   • Bundled .wav files → AVAudioPlayer (.playback category, audible over silent switch)
//   • .default / .critical → AudioServicesPlayAlertSound (tri-tone, respects ringer)
//   • .vibrate → AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)

import SwiftUI
import Combine
import AVFoundation
import AudioToolbox

// MARK: - Preview player

final class SoundPreviewPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {

    @Published var playingSound: NotificationSound? = nil

    private var player:    AVAudioPlayer?
    private var stopTimer: Timer?

    func toggle(_ sound: NotificationSound) {
        if playingSound == sound { stop(); return }
        stop()
        start(sound)
    }

    func stop() {
        player?.stop()
        player    = nil
        stopTimer?.invalidate()
        stopTimer = nil
        DispatchQueue.main.async { self.playingSound = nil }
    }

    // MARK: Private

    private func start(_ sound: NotificationSound) {
        playingSound = sound
        switch sound.id {
        case "vibrate":
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
            scheduleStop(after: 0.6)
        case "default", "critical":
            // Preview the actual neutral tone the "Default" alarm loops, so the
            // preview matches what fires. Fall back to the tri-tone if missing.
            if NotificationSound(id: NotificationSound.defaultLoopTone).bundleURL != nil {
                playBundled(NotificationSound(id: NotificationSound.defaultLoopTone))
                scheduleStop(after: 3.4)
            } else {
                AudioServicesPlayAlertSound(SystemSoundID(1007))
                scheduleStop(after: 1.8)
            }
        default:
            playBundled(sound)
        }
    }

    private func playBundled(_ sound: NotificationSound) {
        // Use bundleURL to locate the file regardless of whether it's at the
        // bundle root or in a Sounds/ subfolder (Xcode 16+ sync groups preserve
        // directory structure, so url(forResource:) alone won't find it).
        guard let url = sound.bundleURL else {
            DispatchQueue.main.async { self.playingSound = nil }
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: .mixWithOthers)
            try session.setActive(true)
            player = try AVAudioPlayer(contentsOf: url)
            player?.delegate = self
            player?.play()
        } catch {
            DispatchQueue.main.async { self.playingSound = nil }
        }
    }

    private func scheduleStop(after delay: TimeInterval) {
        stopTimer = Timer.scheduledTimer(withTimeInterval: delay,
                                         repeats: false) { [weak self] _ in
            DispatchQueue.main.async { self?.playingSound = nil }
        }
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async { self.playingSound = nil }
    }
    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        DispatchQueue.main.async { self.playingSound = nil }
    }
}

// MARK: - Section view

struct SoundPickerSection: View {

    @Binding var selection: NotificationSound
    @StateObject private var player = SoundPreviewPlayer()
    @State   private var isExpanded = false
    @Environment(\.languageBundle) private var bundle

    var body: some View {
        Section {
            if isExpanded {
                expandedList
            } else {
                collapsedRow
            }
        } header: {
            Text("Sound / Vibrate", bundle: bundle)
        }
        .onDisappear { player.stop() }
    }

    // MARK: Collapsed — single row, tap to open

    private var collapsedRow: some View {
        HStack(spacing: 12) {
            Image(systemName: selection.systemImage)
                .foregroundColor(iconColor(for: selection))
                .frame(width: 26)

            Text(NSLocalizedString(selection.localizationKey, bundle: bundle, comment: ""))
                .frame(maxWidth: .infinity, alignment: .leading)

            previewButton(for: selection)

            Image(systemName: "chevron.down")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.22)) { isExpanded = true }
        }
        // See AddAlarmView.swift's activeDaysRow for why this is needed —
        // a plain HStack (this row uses .onTapGesture, not a Button) doesn't
        // get its own accessibility node from .accessibilityIdentifier(_:)
        // alone. `.contain` keeps previewButton individually tappable while
        // making the row itself queryable/scrollable/tappable as one element.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("soundPickerCollapsedRow")
    }

    // MARK: Expanded — full dynamic list, tap a row to select and collapse

    /// Bundled travel sounds (Boat horn, Cable car bell, etc.) require
    /// Silver+ — see monetization-tier-pricing memory. System sounds
    /// (Vibrate/Default/Critical) are always free. Preview playback is
    /// intentionally NOT locked — letting a Free-tier user hear what they're
    /// missing is a reasonable teaser and doesn't unlock any real
    /// functionality; only actually SELECTING a locked sound is blocked.
    private func isLocked(_ sound: NotificationSound) -> Bool {
        !sound.isSystem && !EntitlementManager.isEntitled(to: .silver)
    }

    private var expandedList: some View {
        ForEach(NotificationSound.all) { sound in
            let locked = isLocked(sound)
            HStack(spacing: 12) {
                Image(systemName: sound.systemImage)
                    .foregroundColor(iconColor(for: sound))
                    .frame(width: 26)

                Text(NSLocalizedString(sound.localizationKey, bundle: bundle, comment: ""))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundColor(locked ? .secondary : .primary)

                previewButton(for: sound)

                if locked {
                    // This row is built with .onTapGesture rather than a
                    // Button/TextField, so plain .disabled() wouldn't
                    // actually block selection (SwiftUI's disabled
                    // environment value is ignored by raw gesture
                    // recognizers) — the guard inside onTapGesture below is
                    // what really blocks it. This lock badge is the visible
                    // half of the same "visible but disabled" pattern as
                    // TierGatedModifier, just applied manually since this
                    // row shape doesn't fit that modifier.
                    Label("Silver", systemImage: "lock.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .labelStyle(.titleAndIcon)
                        .fixedSize()
                        .accessibilityIdentifier("tierGatedLock.silver")
                } else {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .foregroundColor(.accentColor)
                        .opacity(selection == sound ? 1 : 0)
                        .frame(width: 16)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                guard !locked else { return }
                selection = sound
                player.stop()
                withAnimation(.easeInOut(duration: 0.22)) { isExpanded = false }
            }
            // Same reasoning as collapsedRow above.
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("soundRow.\(sound.id)")
        }
    }

    // MARK: Shared play/stop button

    private func previewButton(for sound: NotificationSound) -> some View {
        let isPlaying = player.playingSound == sound
        return Button {
            player.toggle(sound)
        } label: {
            ZStack {
                Circle()
                    .fill(isPlaying ? Color.accentColor : Color(.systemGray5))
                    .frame(width: 30, height: 30)
                Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(isPlaying ? .white : .accentColor)
                    .offset(x: isPlaying ? 0 : 1)
            }
            .animation(.easeInOut(duration: 0.15), value: isPlaying)
        }
        .buttonStyle(.plain)
    }

    // MARK: Icon colours — system sounds get distinct colours, bundled sounds use teal

    private func iconColor(for sound: NotificationSound) -> Color {
        switch sound.id {
        case "vibrate":  return .secondary
        case "default":  return .blue
        case "critical": return .red
        default:         return .teal
        }
    }
}

#Preview {
    NavigationStack {
        Form {
            SoundPickerSection(selection: .constant(.default))
        }
    }
}

