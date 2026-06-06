// AlarmAudioPlayer.swift
// Loops the alarm sound until stop() is called.
// Mirrors the sound-type logic in SoundPreviewPlayer but plays indefinitely.
//
// Sound routing:
//   bundled .wav  → AVAudioPlayer, numberOfLoops = -1, AVAudioSession .playback
//   "default" / "critical" → AudioServicesPlayAlertSoundWithCompletion recursive loop
//   "vibrate"    → Timer driving AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)

import AVFoundation
import AudioToolbox
import Foundation

@MainActor
final class AlarmAudioPlayer {

    static let shared = AlarmAudioPlayer()
    private init() {}

    private(set) var isPlaying = false

    private var audioPlayer: AVAudioPlayer?
    private var vibrateTimer: Timer?
    private var systemSoundLooping = false

    // MARK: - Public

    func play(sound: NotificationSound) {
        stop()
        isPlaying = true

        switch sound.id {
        case "vibrate":
            startVibrateLoop()
        case "default", "critical":
            startSystemSoundLoop()
        default:
            startBundledLoop(soundID: sound.id)
        }
    }

    func stop() {
        isPlaying = false
        systemSoundLooping = false

        audioPlayer?.stop()
        audioPlayer = nil

        vibrateTimer?.invalidate()
        vibrateTimer = nil

        try? AVAudioSession.sharedInstance().setActive(
            false, options: .notifyOthersOnDeactivation
        )
    }

    // MARK: - Private

    private func startBundledLoop(soundID: String) {
        // sound.id is the full filename, e.g. "Boat Horn.wav" — strip the extension.
        let name = (soundID as NSString).deletingPathExtension
        guard let url = Bundle.main.url(forResource: name, withExtension: "wav") else {
            startSystemSoundLoop()
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            // .playback keeps audio alive in the background (requires UIBackgroundModes: audio).
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true)
            let player = try AVAudioPlayer(contentsOf: url)
            player.numberOfLoops = -1   // loop forever
            player.volume = 1.0
            player.prepareToPlay()
            player.play()
            audioPlayer = player
        } catch {
            startSystemSoundLoop()
        }
    }

    private func startSystemSoundLoop() {
        // SystemSoundID 1007 = tri-tone; consistent with SoundPreviewPlayer.
        systemSoundLooping = true
        playSystemSoundStep()
    }

    private func playSystemSoundStep() {
        guard isPlaying, systemSoundLooping else { return }
        AudioServicesPlayAlertSoundWithCompletion(SystemSoundID(1007)) { [weak self] in
            guard let self, self.isPlaying, self.systemSoundLooping else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                self?.playSystemSoundStep()
            }
        }
    }

    private func startVibrateLoop() {
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        vibrateTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            guard let self, self.isPlaying else { return }
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        }
    }
}
