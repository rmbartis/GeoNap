// SoundPickerSection.swift
// Collapsible sound / vibrate picker for alarm creation forms.
//
// The sound list is built dynamically from NotificationSound.all —
// any .wav file added to GeoAlarm/Sounds in Xcode appears automatically.
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
            // 1007 = tri-tone; stable since iOS 4; respects ringer switch.
            AudioServicesPlayAlertSound(SystemSoundID(1007))
            scheduleStop(after: 1.8)
        default:
            playBundled(sound)
        }
    }

    private func playBundled(_ sound: NotificationSound) {
        // sound.id is the full filename, e.g. "boat-horn.wav"
        let nameWithoutExt = (sound.id as NSString).deletingPathExtension
        guard let url = Bundle.main.url(forResource: nameWithoutExt,
                                        withExtension: "wav") else {
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

            Text(selection.displayName)
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
    }

    // MARK: Expanded — full dynamic list, tap a row to select and collapse

    private var expandedList: some View {
        ForEach(NotificationSound.all) { sound in
            HStack(spacing: 12) {
                Image(systemName: sound.systemImage)
                    .foregroundColor(iconColor(for: sound))
                    .frame(width: 26)

                Text(sound.displayName)
                    .frame(maxWidth: .infinity, alignment: .leading)

                previewButton(for: sound)

                Image(systemName: "checkmark")
                    .font(.caption.weight(.bold))
                    .foregroundColor(.accentColor)
                    .opacity(selection == sound ? 1 : 0)
                    .frame(width: 16)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                selection = sound
                player.stop()
                withAnimation(.easeInOut(duration: 0.22)) { isExpanded = false }
            }
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

