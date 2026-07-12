<!-- Copyright © 2026 Robert Bartis. All rights reserved. -->

# Live Activity / Dynamic Island — Xcode Setup

These are one-time manual steps in Xcode required to compile and run the Gold-tier
Live Activity / Dynamic Island countdown. All Swift source is already written —
this mirrors NapStopWatch/WATCH_SETUP.md exactly, same reasoning: creating a new
Xcode target isn't something that can be done safely by hand-editing
project.pbxproj, so it needs the Add Target wizard.

---

## 1. Add the Widget Extension target

1. In Xcode, go to **File → New → Target…**
2. Select the **iOS** tab, choose **Widget Extension**, click **Next**
3. Set:
   - Product Name: `GeoAlarmLiveActivity`
   - Bundle Identifier: `com.rmbartis.GeoNap.liveactivity`
   - Team: your Apple Developer account
   - **Uncheck** "Include Configuration App Intent" (not needed — this
     extension is Live-Activity-only, no configurable widget)
4. Click **Finish** — Xcode will ask to activate the scheme; click **Activate**

---

## 2. Source files — nothing to do here

Every file this target needs already lives inside the `GeoAlarmLiveActivity/`
folder, so Xcode 16's synchronized-group auto-membership picks it up
automatically — no File Inspector / Target Membership step required:

- `GeoAlarmLiveActivity/GeoAlarmLiveActivityWidget.swift` — the real widget UI
- `GeoAlarmLiveActivity/GeoAlarmActivityAttributes.swift` — a deliberate
  duplicate of `GeoAlarm/Models/GeoAlarmActivityAttributes.swift` (used by the
  main app target). See that file's header comment for why it's duplicated
  instead of shared — short version: cross-target membership for a file
  living in a *different* synchronized folder proved unreliable to set up
  through Xcode's UI, and since ActivityAttributes data crosses a real
  process boundary via Codable anyway, two identical struct definitions work
  exactly the same as one shared file. **If you ever change the attributes
  struct, change both copies.**

The main `GeoNap` app target already has its own copy
(`GeoAlarm/Models/GeoAlarmActivityAttributes.swift`) plus
`GeoAlarm/Services/LiveActivityManager.swift` — also automatic, no action
needed.

---

## 3. Confirm NSSupportsLiveActivities

Already set in `GeoAlarm/Info.plist` (`NSSupportsLiveActivities` = `true`) — nothing
to do here, just confirming so you don't go looking for a missing key.

---

## 4. Build and test

Since Live Activities need a real device or a recent-enough simulator with Dynamic
Island support:

- Run the **GeoNap** scheme (not the widget extension's own scheme — Live
  Activities are started BY the app, the extension only renders them) on an
  iPhone 14 Pro or later simulator/device for the Dynamic Island presentation,
  or any iOS 16.1+ device for the Lock Screen presentation.
- In Settings' DEBUG-only Tier Simulation, set the tier to **Gold** — the
  Activity only starts for Gold-entitled devices (see `LiveActivityManager.swift`).
- Create and activate an alarm; the Lock Screen banner / Dynamic Island should
  appear within a few seconds once a GPS fix comes in (`handleLocationUpdate` in
  `AlarmManager.swift` drives every update).
- To preview the widget UI in isolation without running the full app: open
  `GeoAlarmLiveActivityWidget.swift` and use the `#Preview` canvas at the
  bottom of the file.

---

## How data flows

```
AlarmManager.startMonitoring(_:)
  └─ LiveActivityManager.start(for:) → Activity<GeoAlarmActivityAttributes>.request(...)
       └─ AlarmManager.handleLocationUpdate(_:) (every GPS fix)
            └─ LiveActivityManager.update(alarmID:distanceRemaining:etaSeconds:)
                 └─ activity.update(...) → GeoAlarmLiveActivityWidget re-renders
AlarmManager.stopMonitoring(_:) / fire paths
  └─ LiveActivityManager.end(alarmID:) → activity.end(...)
```

See `LiveActivityManager.swift`'s header comment for why the Activity is ended
from more than one call site (the same "stale Live Activity" lesson already
learned once for AlarmKit's own system banner — see `NapStopApp.swift`).

---

## Troubleshooting: build errors right after running the wizard

Xcode's Widget Extension wizard generates its own starter template on top of
the real source files already in this folder — three extra files
(`GeoAlarmLiveActivity.swift`, `GeoAlarmLiveActivityControl.swift`,
`GeoAlarmLiveActivityLiveActivity.swift`) plus a `@main` in
`GeoAlarmLiveActivityBundle.swift`. These have already been emptied out /
repointed in the checked-in source (the bundle now only references
`GeoAlarmLiveActivityWidget()`, and `@main` was moved off the widget itself
onto the bundle) — if you re-run the wizard or restore the originals, redo
that step: only one `@main` per target, and the bundle should list only
`GeoAlarmLiveActivityWidget()`.

**`'main' attribute can only apply to one type in a module`** — means both
`GeoAlarmLiveActivityBundle.swift` and `GeoAlarmLiveActivityWidget.swift`
have `@main`. Fixed as of 2026-07-11 in the checked-in source; if it recurs,
remove `@main` from `GeoAlarmLiveActivityWidget.swift` (the bundle owns it).

**`Cannot find type 'GeoAlarmActivityAttributes' in scope`** — originally we
tried to fix this by adding `GeoAlarm/Models/GeoAlarmActivityAttributes.swift`
to the extension target's membership via the File Inspector. In practice
that checkbox proved hard to find/use reliably for a file that lives inside
a *different* synchronized folder than the one the target owns (Xcode 16's
`PBXFileSystemSynchronizedRootGroup` + cross-target exceptions are finicky,
and "Add Files..." doesn't help here since the file's already part of the
project via the synchronized group). **Fixed as of 2026-07-11** by giving
the extension its own copy of the struct —
`GeoAlarmLiveActivity/GeoAlarmActivityAttributes.swift` — which lives
inside the folder the extension target already owns, so it needs no manual
step at all. If this error recurs, check that this duplicate file still
exists and still matches the original property-for-property (see its
header comment).

**`SendProcessControlEvent:toPid: ... Failed to show Widget ... FBSOpenApplicationServiceErrorDomain Code=1 ... denied by service delegate (SBMainWorkspace)`**
— shows up when the **GeoAlarmLiveActivityExtension** scheme (not GeoNap) is
selected as the active scheme and you hit Run. A Live Activity extension has
no launch target of its own — it only renders when the app process calls
`Activity.request(...)`, so Xcode's attempt to hand it directly to
SpringBoard fails. Fix: in the scheme selector next to the Run button,
switch to **GeoNap** and run that instead (see step 4 above) — the
extension still builds and embeds automatically. If it still fails after
switching schemes, try Erase All Content and Settings on the simulator;
a previous failed widget launch attempt can leave SpringBoard in a state
that rejects the next one too.
