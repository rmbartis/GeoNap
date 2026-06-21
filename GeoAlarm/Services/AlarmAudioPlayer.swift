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
        // Pre-configure the audio session category at init time so it is always
        // .playback before the first play() call.  This reduces the chance of
        // setCategory failing when the alarm fires in the background (e.g. CarPlay
        // already has the session when the geo-fence wakes the app).
        try? AVAudioSession.sharedInstance().setCategory(
            .playback, mode: .default, options: [.duckOthers, .allowBluetoothA2DP]
        )

        // Resume looping playback after audio-session interruptions.
        //
        // When a geo-alarm fires, the companion UNNotificationSound (a one-shot
        // chime) is delivered by the system almost simultaneously with
        // AlarmAudioPlayer starting AVAudioPlayer.  iOS treats that chime as an
        // audio interruption; without this observer the player never restarts.
        //
        // NOTE: willPresent in AlarmManager suppresses the notification .sound
        // when the app is in the foreground, so on CarPlay the interruption is
        // avoided entirely — this observer is the safety net for the background /
        // lock-screen case.
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            MainActor.assumeIsolated {
                self.handleSessionInterruption(notification)
            }
        }

        // Re-activate when CarPlay connects or the audio route changes mid-alarm.
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

        // Re-activate the session and resume.
        // We deliberately ignore AVAudioSessionInterruptionOptionShouldResume —
        // for an alarm we always want to resume regardless of system hints.
        do {
            try AVAudioSession.sharedInstance().setActive(true)
            audioPlayer?.play()

            // On CarPlay the player may be non-nil but silently refuse to play
            // (play() returns false). If so, rebuild it via startBundledLoop.
            if let player = audioPlayer, !player.isPlaying, let id = currentSoundID {
                DebugLogger.shared.log(
                    "AlarmAudioPlayer: player present but not playing after interruption — restarting loop",
                    category: "Audio"
                )
                startBundledLoop(soundID: id)
            } else {
                DebugLogger.shared.log("AlarmAudioPlayer: resumed after interruption", category: "Audio")
            }
        } catch {
            // setActive failed — rebuild the entire player so we get fresh retries.
            DebugLogger.shared.log(
                "AlarmAudioPlayer: setActive failed after interruption (\(error.localizedDescription)) — restarting loop",
                category: "Audio"
            )
            if let id = currentSoundID {
                startBundledLoop(soundID: id)
            }
        }
    }

    private(set) var isPlaying = false

    private var audioPlayer: AVAudioPlayer?
    private var vibrateTimer: Timer?
    private var systemSoundLooping = false
    /// Tracks the active sound ID so the interruption handler can restart
    /// the loop if AVAudioPlayer fails to resume after a CarPlay route change.
    private var currentSoundID: String?

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
        currentSoundID = nil

        audioPlayer?.stop()
        audioPlayer = nil

        vibrateTimer?.invalidate()
        vibrateTimer = nil

        try? AVAudioSession.sharedInstance().setActive(
            false, options: .notifyOthersOnDeactivation
        )
    }

    // MARK: - Private

    private func startBundledLoop(soundID: String, attempt: Int = 1) {
        currentSoundID = soundID

        // 1. Locate the WAV — bundle first, then Library/Sounds.
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
        // The category was pre-configured in init(); setCategory here re-applies
        // it in case another part of the app changed it since launch.
        // .duckOthers       — lowers CarPlay radio so the alarm is audible over it
        // .allowBluetoothA2DP — routes through BT speakers / AirPods / CarPlay A2DP
        // NOTE: .allowBluetoothHFP is only valid with .playAndRecord — never use it
        // with .playback; it causes setCategory to throw and silences the alarm.
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.duckOthers, .allowBluetoothA2DP])
            try session.setActive(true)
            let player = try AVAudioPlayer(contentsOf: url)
            player.numberOfLoops = -1
            player.volume = 1.0
            player.prepareToPlay()
            let started = player.play()
            audioPlayer = player
            DebugLogger.shared.log(
                "AlarmAudioPlayer: looping \(soundID) (attempt \(attempt), play()=\(started))",
                category: "Audio"
            )
        } catch {
            // The audio session can be temporarily busy — most often because the
            // companion UNNotificationSound fires at almost the same instant.
            // Retry up to 4 times with increasing delays so we get the session
            // once the notification chime finishes (typically < 2 s).
            let maxAttempts = 4
            guard attempt < maxAttempts else {
                DebugLogger.shared.log(
                    "AlarmAudioPlayer: all \(maxAttempts) attempts failed for '\(soundID)' — \(error.localizedDescription)",
                    category: "Audio"
                )
                return
            }
            let delay = Double(attempt) * 0.5   // 0.5 s, 1.0 s, 1.5 s
            DebugLogger.shared.log(
                "AlarmAudioPlayer: session busy (attempt \(attempt)) — retrying in \(delay) s: \(error.localizedDescription)",
                category: "Audio"
            )
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, self.isPlaying else { return }
                self.startBundledLoop(soundID: soundID, attempt: attempt + 1)
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
