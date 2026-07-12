<!-- Copyright © 2026 Robert Bartis. All rights reserved. -->

# Apple Watch Setup — Xcode Steps

These are one-time manual steps in Xcode required to compile and run the Watch app
and complication. All Swift source files are already written — this mirrors
GeoAlarmLiveActivity/LIVE_ACTIVITY_SETUP.md, though the Watch App target hit its
own, different category of surprise (see the correction below and Troubleshooting
at the bottom).

---

## Correction, 2026-07-11: the Watch App target's real folder is this one

An earlier version of this doc (still readable in the sibling `NapStopWatch/`
folder, now just a breadcrumb) assumed typing Product Name `NapStopWatch` would
make Xcode adopt the existing `NapStopWatch/` folder — that's what happened for
the Live Activity extension and the Watch **Widget** Extension below, but **not**
for the Watch **App** target. Xcode silently created a brand-new synchronized
folder called **`NapStopWatch Watch App`** (this one, note the space) containing
its own default "Hello, world!" template, and never touched the hand-written
`NapStopWatch/` folder at all. The Watch app Bob was testing was that default
template the whole time — no build errors, because it was internally consistent,
just not our code. Symptoms this produced: wrong app name on the Watch home
screen ("NapStopWatch" — Xcode's target name, since fixed to "GeoNapWatch"), no
app icon (the generated `AppIcon.appiconset` had no image in it), and no alarm
data ever showing up (the real `WatchAlarmStore`/`NearestAlarmView` weren't part
of the build at all).

**Fixed by copying the real source directly into this folder** (not by
re-running the wizard) — `NapStopWatchApp.swift`, `NearestAlarmView.swift`,
`WatchAlarmStore.swift`, `WatchAlarmPayload.swift` all live here now, Xcode's
generated `ContentView.swift` is emptied out, and the app icon is populated
from the main app's `AppIcon-1024.png`. **If you ever re-run "File → New →
Target…" for a watchOS App in this project, expect the same thing to happen
again** — check whether the resulting synchronized folder is named exactly
`NapStopWatch` or has something appended, and if it's different, that's where
your real source needs to go, not the old folder.

---

## 1. Add the Watch App target (already done — for reference only)

1. In Xcode, go to **File → New → Target…**
2. Select the **watchOS** tab. In the **Application** section, choose the
   tile simply labeled **App** (a circular "A" icon) — newer Xcode versions
   dropped the separate "Watch App" label. Click **Next**.
3. On the options screen:
   - Product Name: `NapStopWatch` — but see the correction above; Xcode may
     still land on a differently-named folder regardless.
   - **Bundle Identifier is not directly editable here** — it's derived from
     Organization Identifier + Product Name automatically. That's fine, it's
     not read anywhere in code.
   - Under the radio buttons, pick **"Watch App for Existing iOS App"** (NOT
     "Watch-only App", which is the default and creates a standalone app with
     no connection to GeoNap) — then pick **GeoNap** in the dropdown that
     becomes enabled below it.
   - Testing System: leave default.
4. Click **Finish** — Xcode will ask to activate the scheme; click **Activate**

---

## 2. Add the Watch Widget Extension target (already done — for reference only)

1. **File → New → Target…**
2. Select **watchOS** tab, choose **Widget Extension**, click **Next**
3. Set:
   - Product Name: `NapStopWatchWidget` (this one DID correctly adopt the
     existing `NapStopWatchWidget/` folder — no correction needed here)
   - **Uncheck** "Include Control" (we don't need a Control Center widget)
   - **Uncheck** "Include Configuration App Intent"
4. Click **Finish**

---

## 3. Source files

### "NapStopWatch Watch App" target (this folder — automatic now):
- `NapStopWatchApp.swift`
- `WatchAlarmStore.swift`
- `NearestAlarmView.swift`
- `WatchAlarmPayload.swift`
- `Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png`

### NapStopWatchWidget target (automatic, correctly adopted its own folder):
- `NapStopWatchWidget/NapStopComplication.swift`
- `NapStopWatchWidget/WatchAlarmPayload.swift`

### GeoNap (iOS) target — already there:
- `GeoAlarm/Services/WatchConnectivityManager.swift`
- `GeoAlarm/Models/WatchAlarmPayload.swift`

**Why three copies of `WatchAlarmPayload.swift`, not one shared file?** Same
fix applied to `GeoAlarmActivityAttributes.swift` for the Live Activity
extension — see that file's header comment and
`GeoAlarmLiveActivity/LIVE_ACTIVITY_SETUP.md`. Cross-target membership for a
file living in a *different* synchronized folder proved unreliable through
Xcode's UI in practice, and since this data crosses a real process boundary
(iOS app ↔ Watch app ↔ complication) via `WCSession`/Codable anyway, three
identical struct definitions are functionally equivalent to one shared file.
**If you ever change this struct, change all three copies.**

---

## 4. Enable App Groups capability (required for data sharing)

The Watch app and the complication extension run in separate processes. They share
alarm data through an App Group container. You must enable this on **all three targets**.

### For each of: GeoNap, "NapStopWatch Watch App", NapStopWatchWidgetExtension
### (check the exact target names in the target list — Xcode may append
### "Extension" to the widget target, as it did for Live Activity):
1. Select the target in Xcode → **Signing & Capabilities** tab
2. Click **+ Capability** → add **App Groups**
3. Click **+** and add the group: `group.com.rmbartis.NapAlarm`
4. Make sure the checkbox next to the group is ticked

> The group name must be identical across all three targets, and must match
> exactly what `WatchAlarmStore.swift` and `NapStopComplication.swift`
> already hard-code (`group.com.rmbartis.NapAlarm` — a leftover from before
> the app was renamed to GeoNap, but it's what the code actually reads/writes,
> so use it as-is rather than "correcting" it to match the current bundle ID).

---

## 5. Add WatchConnectivity framework to the iOS target

1. Select the **GeoNap** iOS target → **General** tab
2. Scroll to **Frameworks, Libraries, and Embedded Content**
3. Click **+** → search for `WatchConnectivity` → click **Add**

The Watch targets automatically link WatchConnectivity and WidgetKit.

---

## 6. Build and test

Since you don't have a physical Apple Watch:

- Use the **watchOS Simulator**: in Xcode, pair a Watch simulator to the iPhone
  simulator via **Window → Devices and Simulators**
- Run the **"NapStopWatch Watch App"** scheme on the Watch simulator (unlike
  the Live Activity extension, the Watch app scheme IS meant to be run
  directly — it's a real standalone app, not something only launched by the
  phone). If your run-destination picker only shows iPad/plain-iPhone
  simulators with no Watch options, the active scheme is set to **GeoNap**
  instead — switch the scheme selector (top-left, next to the Run button)
  to the Watch scheme.
- Create/fire an alarm on the iOS sim; the Watch simulator should receive the
  applicationContext update within a few seconds and show it in the alarm list
- The Watch should also haptic-buzz and show a local notification the moment
  an alarm transitions to triggered (see "How data flows" below). The first
  time you run the Watch app, it will prompt for notification permission —
  allow it, or the alert step silently does nothing.
- The app should now show as **GeoNapWatch** on the Watch home screen, with
  the same icon as the iPhone app.
- To preview the complication without running: open `NapStopWatchWidget/NapStopComplication.swift`
  and use the **#Preview** canvas at the bottom of the file

---

## How data flows

```
iPhone AlarmManager
  └─ save() → WatchConnectivityManager.updateWatch()
       └─ WCSession.updateApplicationContext(["watchAlarms": Data])
            └─ Watch WatchAlarmStore.session(_:didReceiveApplicationContext:)
                 ├─ Persists to UserDefaults(suiteName: "group.com.rmbartis.NapAlarm")
                 ├─ Updates @Published alarms → NearestAlarmView refreshes
                 ├─ WidgetCenter.reloadAllTimelines() → Complication refreshes
                 │    └─ AlarmProvider reads same UserDefaults group
                 └─ Diffs old vs. new payloads; for any alarm newly
                      transitioned to "triggered":
                      ├─ WKInterfaceDevice.current().play(.notification) (haptic)
                      └─ UNUserNotificationCenter local notification (immediate)
```

**Why the alert exists:** AlarmKit's own alert (the thing you see/hear fire on
the iPhone) is iPhone-only — it does not mirror to a paired Watch. Without
this, firing an alarm updated the Watch's data silently with no way to notice
unless you had the Watch app open at that exact moment. See
`WatchAlarmStore.swift`'s header comment for the full reasoning, including
why the diff is against the *previous* payload snapshot (so relaunching the
Watch app doesn't re-alert for an alarm that was already triggered before).

---

## Troubleshooting (confirmed 2026-07-11, from live setup)

**Watch home screen shows the wrong app / no icon / no alarm data.** This was
the big one — see the Correction section at the top. Fixed by moving real
source into `NapStopWatch Watch App/` (this folder) instead of the orphaned
`NapStopWatch/`, populating the app icon, and setting
`INFOPLIST_KEY_CFBundleDisplayName = GeoNapWatch` in `project.pbxproj` for
both Debug and Release configs of the "NapStopWatch Watch App" target.

**The Widget Extension target (step 2) generated boilerplate**, same as the
Live Activity extension before it: a `NapStopWatchWidget.swift` plain widget
stub and a `NapStopWatchWidgetBundle.swift` with `@main`, sitting right
alongside the real `NapStopComplication.swift` (which already had its own
`@main` from before the target existed). Result: `'main' attribute can only
apply to one type in a module`. **Already fixed in the checked-in source** —
`NapStopWatchWidget.swift` emptied out, `@main` removed from
`NapStopComplication.swift`, and `NapStopWatchWidgetBundle.swift`'s `body`
now references `NapStopComplication()`. If this recurs:
1. Find the generated bundle file (`NapStopWatchWidgetBundle.swift`) — it
   should be the only thing with `@main`.
2. Empty out the generated widget stub rather than deleting.
3. Point the bundle's `body` at `NapStopComplication()` only.
4. Make sure `NapStopComplication.swift` itself does NOT also declare `@main`.

**Testing in the watchOS Simulator: haptics never fire, period.** There's no
Taptic Engine hardware to emulate, so `WKInterfaceDevice.current().play(...)`
is always a silent no-op in Simulator. This is a Simulator limitation, not a
bug — it'll work on a real Apple Watch. Don't use "did I feel a buzz" as a
Simulator test signal; only the notification banner is verifiable there.

**Notification banner didn't show even though the code ran.** Fixed
2026-07-11 — `UNUserNotificationCenter` suppresses banners/sound by default
for any notification delivered while the requesting app is in the
foreground, which is exactly the case if you're looking at
`NearestAlarmView` when the alarm fires (the common case testing in
Simulator). `WatchAlarmStore` now conforms to
`UNUserNotificationCenterDelegate` and sets itself as
`UNUserNotificationCenter.current().delegate` in `init`, returning
`[.banner, .list, .sound]` from `willPresent` so the alert shows regardless
of whether the Watch app is currently open.

**List syncs fine but no haptic/notification on a real fire.** Fixed
2026-07-11 — the original diff logic compared `state` (not-triggered →
triggered) to detect a "new" fire, which misses an alarm that's already
sitting in the triggered state when it fires again (a repeat alarm, or
re-running Simulate Trigger on an already-triggered alarm). `state` doesn't
change in that case. Now diffs `triggerCount` instead, which increments on
every fire regardless of current state — see the updated comment on
`alertForNewlyTriggeredAlarms` in `WatchAlarmStore.swift`. If you still
don't see/feel anything after this fix, double-check notification
permission is actually granted (Watch Settings app → Notifications →
GeoNapWatch, may require scrolling past the global toggles at the top) —
easy to accidentally decline the one-time prompt, and Simulator doesn't
always let the app re-prompt without an Erase All Content and Settings.

**`Cannot find type 'WatchAlarmPayload' in scope`** — preempted by giving
each target its own copy of `WatchAlarmPayload.swift`. If you hit it anyway,
confirm the duplicate file is actually present in that target's folder and
still matches the other copies property-for-property.

**`Type 'WatchAlarmStore' does not conform to protocol 'ObservableObject'` /
`Cannot find 'WatchConnectivityManager' in scope`.** Two separate issues
from the same root cause — the file was written and never actually compiled
until this target existed for real (see the Correction above). Fixed:
1. Added `import Combine` — this target's Swift settings
   (`SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY`) require it explicitly
   for `@Published`/`ObservableObject`, unlike the main iOS target where it
   came in transitively.
2. `WatchConnectivityManager` lives in the iOS target only — the Watch app
   can't see it. Replaced `WatchConnectivityManager.alarmsKey` with a local
   `nonisolated static let storageKey = "watchAlarms"` (same duplication
   reasoning as `WatchAlarmPayload.swift`, and matches the literal already
   hard-coded in `NapStopComplication.swift`). Marked `nonisolated` because
   it's read from `didReceiveApplicationContext`, which runs off the main
   actor — same fix pattern as `EntitlementManager.TierChangeObserver`
   earlier in this project's history.

**Run-destination picker only shows iPad/iPhone simulators, no Watch
options.** The active scheme is set to **GeoNap**, not the Watch scheme —
watchOS destinations only appear for a watchOS-targeting scheme. Switch the
scheme selector, not the destination picker.

**Running the wrong scheme causes a SpringBoard/process-control error.**
That's the Live Activity extension's failure mode (it has no launch target of
its own), not the Watch app's — the Watch app scheme is meant to be run
directly. If you see this error while trying to run the Watch app, you
likely have **NapStopWatchWidgetExtension** selected instead of
**"NapStopWatch Watch App"**.
