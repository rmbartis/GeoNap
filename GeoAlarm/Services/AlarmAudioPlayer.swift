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

    private init() {
        // Resume looping playback after audio-session interruptions.
        //
        // When a geo-alarm fires, the companion UNNotificationSound (a one-shot
        // chime) is delivered by iOS almost simultaneously with AlarmAudioPlayer
        // starting AVAudioPlayer. iOS treats the notification chime as an audio
        // interruption: AVAudioPlayer stops and — without this observer — never
        // restarts, leaving the device silent on the lock screen despite the alarm
        // still being "active".
        //
        // AVAudioSession posts interruption notifications on the main thread, so
        // the Task dispatch below is safe with @MainActor isolation.
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            // queue: .main guarantees we are already on the main thread.
            // assumeIsolated() tells the compiler that without crossing any
            // actor boundary — so Notification need not be Sendable.
            MainActor.assumeIsolated {
                self.handleSessionInterruption(notification)
            }
        }

        // Re-activate with Bluetooth options when CarPlay connects or the route changes.
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            MainActor.assumeIsolated {
                self.handleRouteChange(notification)
            }
        }
    }

    // MARK: - Route change recovery
    //
    // When CarPlay connects/disconnects (or any output route changes) iOS may
    // reroute or interrupt the session. Re-activate with Bluetooth options so
    // the alarm follows the new output device automatically.

    private func handleRouteChange(_ notification: Notification) {
        guard isPlaying,
              let info = notification.userInfo,
              let reasonRaw = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonRaw)
        else { return }

        switch reason {
        case .newDeviceAvailable, .oldDeviceUnavailable, .override, .categoryChange:
            try? AVAudioSession.sharedInstance().setActive(true)
            audioPlayer?.play()
            DebugLogger.shared.log("AlarmAudioPlayer: re-activated after route change (\(reason.rawValue))", category: "Audio")
        default:
            break
        }
    }

    // MARK: - Interruption recovery

    private func handleSessionInterruption(_ notification: Notification) {
        guard
            isPlaying,
            let info = notification.userInfo,
            let typeRaw = info[AVAudioSessionInterruptionTypeKey] as? UInt,
            let type = AVAudioSession.InterruptionType(rawValue: typeRaw),
            type == .ended
        else { return }

        // Re-activate the session and resume the loop.
        // The notification chime is typically < 2 s; it is finished by the time
        // iOS posts the interruption-ended event.
        do {
            try AVAudioSession.sharedInstance().setActive(true)
            audioPlayer?.play()
            DebugLogger.shared.log("AlarmAudioPlayer: resumed after audio-session interruption", category: "Audio")
        } catch {
            DebugLogger.shared.log("AlarmAudioPlayer: resume failed after interruption — \(error.localizedDescription)", category: "Audio")
        }
    }

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
            // AudioServicesPlayAlertSoundWithCompletion is silenced when the device
            // is locked and the screen is off — it only plays in the foreground.
            // AVAudioPlayer with UIBackgroundModes:audio plays through a locked screen,
            // so we use the first available bundled sound as the looping alarm tone.
            // (The notification banner still uses UNNotificationSound.default for its
            // one-shot ding; this only affects the looping in-app alarm sound.)
            if let fallback = NotificationSound.bundledSounds.first {
                startBundledLoop(soundID: fallback.id)
            } else {
                startSystemSoundLoop()
            }
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
        // 1. Locate the WAV — bundle first, then Library/Sounds (where
        //    installBundledSoundsIfNeeded() copies files at each app launch).
        let sound = NotificationSound(id: soundID)
        let url: URL
        if let bundleURL = sound.bundleURL {
            url = bundleURL
        } else {
            let fm = FileManager.default
            guard let libURL = fm.urls(for: .libraryDirectory, in: .userDomainMask).first else {
                startSystemSoundLoop(); return
            }
            let candidate = libURL.appendingPathComponent("Sounds/\(soundID)")
            guard fm.fileExists(atPath: candidate.path) else {
                startSystemSoundLoop(); return
            }
            url = candidate
        }

        // 2. Activate the audio session and start looping.
        do {
            let session = AVAudioSession.sharedInstance()
            // .playback keeps audio alive in the background (requires UIBackgroundModes: audio).
            // .duckOthers       — lowers CarPlay radio so the alarm is audible over it
            // .allowBluetoothHFP  — routes alarm through CarPlay / HFP Bluetooth (hands-free)
            // .allowBluetoothA2DP — routes alarm through stereo BT speakers / AirPods
            try session.setCategory(.playback, mode: .default, options: [.duckOthers, .allowBluetoothHFP, .allowBluetoothA2DP])
            try session.setActive(true)
            let player = try AVAudioPlayer(contentsOf: url)
            player.numberOfLoops = -1   // loop forever
            player.volume = 1.0
            player.prepareToPlay()
            player.play()
            audioPlayer = player
            DebugLogger.shared.log("AlarmAudioPlayer: looping \(soundID)", category: "Audio")
        } catch {
            // The companion notification chime often grabs the audio session for ~2 s
            // immediately after a geo-alarm fires. Rather than falling back to a
            // different tone (which would ignore the user's sound choice), we retry
            // once the session is free. The interruption-ended observer also retries.
            DebugLogger.shared.log("AlarmAudioPlayer: session busy — retrying in 2 s (\(error.localizedDescription))", category: "Audio")
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                guard let self, self.isPlaying else { return }
                self.startBundledLoop(soundID: soundID)
            }
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
            // Callback is @Sendable — do NOT access @MainActor properties here.
            // Dispatch back to the main actor before reading any isolated state.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                guard let self, self.isPlaying, self.systemSoundLooping else { return }
                self.playSystemSoundStep()
            }
        }
    }

    private func startVibrateLoop() {
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        // No self capture needed: the timer is invalidated in stop(), so if it fires we're still playing.
        vibrateTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { _ in
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        }
    }
}
