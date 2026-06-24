// AlarmAudioPlayer.swift
// Plays alarm sounds directly via AVAudioPlayer using the .alarm audio session
// category, which bypasses the iOS ringer/silent switch.
//
// Used by AlarmManager when the app is in the foreground so the user always
// hears the alarm regardless of whether the device is on silent.
//
// Background delivery (geo-fence fires while app is backgrounded) still relies
// on the notification's content.sound. To bypass the silent switch in the
// background, apply for Apple's Critical Alerts entitlement and switch
// NotificationSound.unSound to return .defaultCritical.
//
// CarPlay / Bluetooth: the session is configured with .allowBluetooth,
// .allowBluetoothA2DP, and .duckOthers so the alarm routes through car
// speakers and lowers any playing radio/music automatically.

import AVFoundation
import AudioToolbox
import UserNotifications

final class AlarmAudioPlayer: NSObject, AVAudioPlayerDelegate {

    private var player: AVAudioPlayer?
    private var isObservingRouteChanges = false
    private var isObservingInterruptions = false

    // Sound URL kept so we can restart playback after a hard interruption
    // (e.g. phone call) that invalidates the existing AVAudioPlayer instance.
    private var currentSoundURL: URL?

    // All AVAudioSession notifications (route change / interruption) are
    // delivered on an arbitrary thread, while play()/stop() run on the main
    // actor. We funnel every handler body onto this serial queue so access to
    // `player` and the session is never concurrent — the data race that could
    // crash the audio path mid-alarm (most visibly on CarPlay) is eliminated.
    private let workQueue = DispatchQueue.main

    // MARK: - Play

    func play(_ sound: NotificationSound) {
        stop()
        startObservingRouteChanges()
        startObservingInterruptions()
        switch sound.id {
        case "vibrate":
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)

        case "default":
            activateAlarmSession()
            // System alert sound (tri-tone) — 1007 is stable since iOS 4.
            AudioServicesPlayAlertSound(SystemSoundID(1007))

        case "critical":
            activateAlarmSession()
            AudioServicesPlayAlertSound(SystemSoundID(1007))

        default:
            playBundled(sound)
        }
    }

    func stop() {
        stopObservingRouteChanges()
        stopObservingInterruptions()
        currentSoundURL = nil
        player?.stop()
        player = nil
        // Deactivate so other audio (music, phone calls) can resume.
        try? AVAudioSession.sharedInstance().setActive(false,
              options: .notifyOthersOnDeactivation)
    }

    // MARK: - Private

    private func activateAlarmSession() {
        let session = AVAudioSession.sharedInstance()
        // .playback keeps audio running when the screen locks / app is backgrounded.
        // Options:
        //   .duckOthers          — lowers radio/music so the alarm is audible over CarPlay
        //   .allowBluetooth      — enables routing through HFP Bluetooth (hands-free / CarPlay)
        //   .allowBluetoothA2DP  — enables routing through A2DP Bluetooth (stereo car speakers)
        let options: AVAudioSession.CategoryOptions = [.duckOthers, .allowBluetooth, .allowBluetoothA2DP]
        do {
            try session.setCategory(.playback, mode: .default, options: options)
            try session.setActive(true)
        } catch {
            print("⚠️ AlarmAudioPlayer: could not activate audio session: \(error)")
        }
    }

    // MARK: - Route change handling
    //
    // When CarPlay connects or the audio route changes mid-alarm (e.g. user
    // plugs in/out), iOS may interrupt the session. Re-activate and resume.

    private func startObservingRouteChanges() {
        guard !isObservingRouteChanges else { return }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRouteChange(_:)),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )
        isObservingRouteChanges = true
    }

    private func stopObservingRouteChanges() {
        guard isObservingRouteChanges else { return }
        NotificationCenter.default.removeObserver(self, name: AVAudioSession.routeChangeNotification, object: nil)
        isObservingRouteChanges = false
    }

    @objc private func handleRouteChange(_ notification: Notification) {
        guard let reasonValue = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else { return }

        // NOTE: .categoryChange is intentionally NOT handled. We are the ones who
        // change the category (in activateAlarmSession), and reacting to it by
        // calling activateAlarmSession again would post another .categoryChange —
        // a feedback loop that thrashes the session and can starve the main
        // thread right as the alarm fires (the CarPlay failure mode). Real route
        // changes arrive via the device-availability / override reasons below.
        switch reason {
        case .newDeviceAvailable, .override, .oldDeviceUnavailable:
            // Hop to the main thread: AVAudioSession posts this on an arbitrary
            // thread, but `player` is otherwise only touched on main.
            workQueue.async { [weak self] in
                self?.reactivateAndResume(context: "route change")
            }

        default:
            break
        }
    }

    /// Reactivate the session and resume (or rebuild) the looping player.
    /// Must run on the main thread. Shared by route-change and interruption paths.
    private func reactivateAndResume(context: String) {
        activateAlarmSession()

        if let p = player {
            // AVAudioPlayer instance exists — just resume it on the new route.
            p.play()
        } else if let url = currentSoundURL {
            // The player may have been paused or deallocated by the route change /
            // interruption (e.g. CarPlay handoff, phone call). Rebuild and restart.
            do {
                let p = try AVAudioPlayer(contentsOf: url)
                p.delegate = self
                p.numberOfLoops = -1
                p.play()
                player = p
                print("🔔 AlarmAudioPlayer: rebuilt player after \(context)")
            } catch {
                print("⚠️ AlarmAudioPlayer: could not rebuild player after \(context): \(error)")
            }
        }
    }

    // MARK: - Interruption handling
    //
    // Bluetooth connect/disconnect and CarPlay handoff cause an AVAudioSession
    // interruption that pauses AVAudioPlayer. We must wait for .ended before
    // resuming, and check the shouldResume option iOS provides.
    //
    // In rare cases (e.g. phone call that ends mid-alarm) the player instance
    // is invalidated; we rebuild it from currentSoundURL in that path.

    private func startObservingInterruptions() {
        guard !isObservingInterruptions else { return }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption(_:)),
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance()
        )
        isObservingInterruptions = true
    }

    private func stopObservingInterruptions() {
        guard isObservingInterruptions else { return }
        NotificationCenter.default.removeObserver(self, name: AVAudioSession.interruptionNotification, object: nil)
        isObservingInterruptions = false
    }

    @objc private func handleInterruption(_ notification: Notification) {
        guard let typeValue = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }

        switch type {
        case .began:
            // iOS paused the player automatically — nothing to do here.
            print("🔇 AlarmAudioPlayer: audio session interrupted (e.g. BT connect, call)")

        case .ended:
            // Check if iOS says we should resume.
            let optionsValue = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)

            workQueue.async { [weak self] in
                guard let self else { return }

                // CarPlay and Bluetooth device handoffs often end the interruption WITHOUT
                // setting shouldResume — the audio route has simply moved to the car speakers.
                // We always want to resume an in-progress alarm after such a handoff, so if a
                // sound is still loaded we resume regardless of shouldResume. Only when there's
                // nothing left to play do we stay silent.
                let wasActiveAlarm = (self.player != nil || self.currentSoundURL != nil)
                guard options.contains(.shouldResume) || wasActiveAlarm else {
                    print("⚠️ AlarmAudioPlayer: interruption ended, nothing to resume — staying silent")
                    return
                }

                self.reactivateAndResume(context: "interruption")
                print("🔔 AlarmAudioPlayer: resumed after interruption")
            }

        @unknown default:
            break
        }
    }

    private func playBundled(_ sound: NotificationSound) {
        // Use sound.bundleURL — it searches the entire bundle recursively via
        // paths(forResourcesOfType:inDirectory:nil), so it finds files in folder
        // references (Sounds/) that Bundle.url(forResource:withExtension:) misses.
        guard let url = sound.bundleURL else {
            print("⚠️ AlarmAudioPlayer: bundled sound '\(sound.id)' not found — falling back to default")
            // Fall back to alert sound so the user hears *something*.
            activateAlarmSession()
            AudioServicesPlayAlertSound(SystemSoundID(1007))
            return
        }
        do {
            activateAlarmSession()
            currentSoundURL = url
            player = try AVAudioPlayer(contentsOf: url)
            player?.delegate = self
            player?.numberOfLoops = -1  // loop indefinitely until stop() is called
            player?.play()
        } catch {
            print("⚠️ AlarmAudioPlayer: playback error for '\(sound.id)': \(error)")
        }
    }

    // MARK: - AVAudioPlayerDelegate

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        self.player = nil
        try? AVAudioSession.sharedInstance().setActive(false,
              options: .notifyOthersOnDeactivation)
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        self.player = nil
        print("⚠️ AlarmAudioPlayer: decode error: \(String(describing: error))")
    }
}
