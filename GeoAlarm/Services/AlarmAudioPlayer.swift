// AlarmAudioPlayer.swift
// Plays the alarm sound — and loops it indefinitely — even when the geo-fence
// fires while the app is in the background, the screen is locked, or audio is
// routed to Bluetooth / CarPlay.
//
// WHY THE "KEEP-ALIVE" SESSION EXISTS
// -----------------------------------
// iOS does NOT reliably let an app *start* a fresh AVAudioSession from a
// background-triggered event (a region crossing). Attempting setActive(true) +
// play() at trigger time returns OSStatus -50 and the alarm is silent — this is
// exactly what the field logs showed (61 failures, 1 success, the success being
// in the foreground).
//
// The fix: as soon as an alarm is armed, begin a SILENT looping session
// (.mixWithOthers, volume 0) so the audio session is already active and owned by
// us. When the alarm actually fires we only have to SWAP the silent loop for the
// real WAV and switch to .duckOthers — no background "start", so no -50.
//
// Session options:
//   keep-alive (silent):  .mixWithOthers      — never disturbs the user's music
//   firing (audible):     .duckOthers, .allowBluetoothA2DP
//                                            — lowers CarPlay/BT audio, routes to it
//   NOTE: .allowBluetoothHFP is only valid with .playAndRecord; with .playback it
//   makes setCategory throw and silences the alarm — never use it here.

import AVFoundation
import AudioToolbox
import Foundation

@MainActor
final class AlarmAudioPlayer {

    static let shared = AlarmAudioPlayer()

    // MARK: - State
    private(set) var isPlaying = false        // true only while the AUDIBLE alarm is sounding
    private var armed = false                  // true while ≥1 alarm is monitored (keep-alive on)

    private var audioPlayer: AVAudioPlayer?    // the audible alarm WAV loop
    private var keepAlivePlayer: AVAudioPlayer? // the silent keep-alive loop
    private var vibrateTimer: Timer?
    private var systemSoundLooping = false
    private var currentSoundID: String?

    private init() {
        // Resume the alarm after an audio-session interruption (e.g. the companion
        // notification chime, a phone call, or a Bluetooth/CarPlay handoff).
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] note in
            guard let self else { return }
            MainActor.assumeIsolated { self.handleSessionInterruption(note) }
        }
        // Re-activate when CarPlay connects or the route changes mid-alarm.
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] note in
            guard let self else { return }
            MainActor.assumeIsolated { self.handleRouteChange(note) }
        }
    }

    // MARK: - Keep-alive (called by AlarmManager when alarms are armed/disarmed)

    /// Begin holding the audio session active (silently) so a background-triggered
    /// alarm can make sound without iOS blocking a fresh session start (-50).
    func beginKeepAlive() {
        armed = true
        // Don't disturb an alarm that's already sounding.
        guard !isPlaying else { return }
        startSilentLoop()
    }

    /// Release the audio session when no alarms remain armed.
    func endKeepAlive() {
        armed = false
        guard !isPlaying else { return }   // an alarm is sounding; leave it be
        keepAlivePlayer?.stop()
        keepAlivePlayer = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        DebugLogger.shared.log("AlarmAudioPlayer: keep-alive stopped (no armed alarms)", category: "Audio")
    }

    private func startSilentLoop() {
        let session = AVAudioSession.sharedInstance()
        do {
            // .mixWithOthers so the silent loop never ducks the user's music/radio.
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
            let player = try AVAudioPlayer(data: Self.silentWAV)
            player.numberOfLoops = -1
            player.volume = 0
            player.prepareToPlay()
            let ok = player.play()
            keepAlivePlayer = player
            DebugLogger.shared.log("AlarmAudioPlayer: keep-alive session active (silent, play()=\(ok))", category: "Audio")
            logRoute("keep-alive")
        } catch {
            DebugLogger.shared.log("AlarmAudioPlayer: keep-alive start FAILED — \(error.localizedDescription)", category: "Audio")
        }
    }

    // MARK: - Fire the alarm

    func play(sound: NotificationSound) {
        stopAlarmPlayers()              // stop any prior alarm sound, keep the session
        keepAlivePlayer?.stop()        // silent loop gives way to the real alarm
        keepAlivePlayer = nil
        isPlaying = true

        // Use a ducking (mixable) playback configuration. This is the only mode
        // that lets our own AVAudioPlayer actually start on CarPlay (play()==true).
        //
        // NOTE / KNOWN LIMITATION: a non-mixing "primary" session returns
        // play()==false on CarPlay — iOS blocks an app that lacks the CarPlay
        // audio entitlement from becoming the car's primary audio source. So we
        // stay mixable + ducking, which works on the phone speaker, Bluetooth, and
        // CarPlay *when other audio is already playing*. In a SILENT car, CarPlay
        // does not route our secondary stream out loud; the audible alert there
        // comes from the notification's own sound, which the system plays.
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, options: [.duckOthers, .allowBluetoothA2DP])
            try session.setActive(true)
        } catch {
            // Not fatal: the keep-alive session is very likely still active.
            DebugLogger.shared.log("AlarmAudioPlayer: setCategory/Active at fire returned \(error.localizedDescription) — continuing (session likely already active)", category: "Audio")
        }
        logRoute("at fire")

        switch sound.id {
        case "vibrate":
            startVibrateLoop()
        case "default", "critical":
            if let fallback = NotificationSound.bundledSounds.first {
                startBundledLoop(soundID: fallback.id)
            } else {
                startSystemSoundLoop()
            }
        default:
            startBundledLoop(soundID: sound.id)
        }

        // CarPlay claims its audio channel for our stream only when something is
        // already driving it (other audio) or a route-change event fires. In a
        // silent car with no route change, the stream never becomes audible. Nudge
        // the session a couple of times to force it to claim the channel — this
        // mirrors the Bluetooth route-change recovery that already works.
        scheduleRouteClaimNudges()
    }

    /// Re-assert the active session and restart playback shortly after firing, to
    /// force CarPlay (with no other audio) to route our stream to the car speakers.
    private func scheduleRouteClaimNudges() {
        for delay in [0.4, 1.2, 2.5] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, self.isPlaying else { return }
                try? AVAudioSession.sharedInstance().setActive(true)
                if let p = self.audioPlayer, !p.isPlaying { p.play() }
                self.logRoute("after nudge (+\(delay)s)")
            }
        }
    }

    /// Logs the current output route + category so a debug log reveals whether the
    /// alarm is actually routed to CarPlay/Bluetooth or stuck on another output.
    private func logRoute(_ tag: String) {
        let s = AVAudioSession.sharedInstance()
        let outs = s.currentRoute.outputs.map { $0.portType.rawValue }.joined(separator: ",")
        DebugLogger.shared.log("AlarmAudioPlayer: route \(tag) → out=[\(outs.isEmpty ? "none" : outs)] cat=\(s.category.rawValue) mix=\(s.categoryOptions.contains(.mixWithOthers)) duck=\(s.categoryOptions.contains(.duckOthers))", category: "Audio")
    }

    /// Stop the audible alarm. If alarms are still armed, fall back to the silent
    /// keep-alive loop so the next alarm can also sound; otherwise release the session.
    func stop() {
        stopAlarmPlayers()
        isPlaying = false
        if armed {
            startSilentLoop()          // resume holding the session for the next alarm
        } else {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    private func stopAlarmPlayers() {
        systemSoundLooping = false
        currentSoundID = nil
        audioPlayer?.stop()
        audioPlayer = nil
        vibrateTimer?.invalidate()
        vibrateTimer = nil
    }

    // MARK: - Bundled WAV loop (the audible alarm)

    private func startBundledLoop(soundID: String, attempt: Int = 1) {
        currentSoundID = soundID

        // Locate the WAV — bundle first, then Library/Sounds.
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

        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.numberOfLoops = -1
            player.volume = 1.0
            player.prepareToPlay()
            let started = player.play()
            audioPlayer = player
            DebugLogger.shared.log("AlarmAudioPlayer: looping \(soundID) (attempt \(attempt), play()=\(started))", category: "Audio")
        } catch {
            // With the keep-alive session this should rarely happen, but keep a
            // short retry as a safety net in case the session is momentarily busy.
            let maxAttempts = 4
            guard attempt < maxAttempts else {
                DebugLogger.shared.log("AlarmAudioPlayer: all \(maxAttempts) attempts failed for '\(soundID)' — \(error.localizedDescription)", category: "Audio")
                return
            }
            let delay = Double(attempt) * 0.5
            DebugLogger.shared.log("AlarmAudioPlayer: play '\(soundID)' attempt \(attempt) failed — retry in \(delay)s: \(error.localizedDescription)", category: "Audio")
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, self.isPlaying else { return }
                self.startBundledLoop(soundID: soundID, attempt: attempt + 1)
            }
        }
    }

    private func startSystemSoundLoop() {
        systemSoundLooping = true
        playSystemSoundStep()
    }

    private func playSystemSoundStep() {
        guard isPlaying, systemSoundLooping else { return }
        AudioServicesPlayAlertSoundWithCompletion(SystemSoundID(1007)) { [weak self] in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                guard let self, self.isPlaying, self.systemSoundLooping else { return }
                self.playSystemSoundStep()
            }
        }
    }

    private func startVibrateLoop() {
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        vibrateTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { _ in
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        }
    }

    // MARK: - Interruption / route recovery (only while the alarm is sounding)

    private func handleSessionInterruption(_ notification: Notification) {
        guard isPlaying,
              let info = notification.userInfo,
              let typeRaw = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeRaw),
              type == .ended
        else { return }
        do {
            try AVAudioSession.sharedInstance().setActive(true)
            audioPlayer?.play()
            if let player = audioPlayer, !player.isPlaying, let id = currentSoundID {
                DebugLogger.shared.log("AlarmAudioPlayer: player not playing after interruption — restarting loop", category: "Audio")
                startBundledLoop(soundID: id)
            } else {
                DebugLogger.shared.log("AlarmAudioPlayer: resumed after interruption", category: "Audio")
            }
        } catch {
            DebugLogger.shared.log("AlarmAudioPlayer: setActive failed after interruption (\(error.localizedDescription)) — restarting loop", category: "Audio")
            if let id = currentSoundID { startBundledLoop(soundID: id) }
        }
    }

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
            logRoute("after route change")
        default:
            break
        }
    }

    // MARK: - Silent WAV used to hold the session open

    /// 1 s of 8 kHz mono 16-bit PCM silence, built in memory (no bundled asset).
    private static let silentWAV: Data = {
        let sampleRate = 8000, seconds = 1, bytesPerSample = 2
        let dataSize = sampleRate * seconds * bytesPerSample
        var d = Data()
        func le32(_ v: UInt32) { var x = v.littleEndian; d.append(Data(bytes: &x, count: 4)) }
        func le16(_ v: UInt16) { var x = v.littleEndian; d.append(Data(bytes: &x, count: 2)) }
        d.append(Data("RIFF".utf8)); le32(UInt32(36 + dataSize)); d.append(Data("WAVE".utf8))
        d.append(Data("fmt ".utf8)); le32(16); le16(1); le16(1)
        le32(UInt32(sampleRate)); le32(UInt32(sampleRate * bytesPerSample))
        le16(UInt16(bytesPerSample)); le16(16)
        d.append(Data("data".utf8)); le32(UInt32(dataSize))
        d.append(Data(count: dataSize))
        return d
    }()
}
