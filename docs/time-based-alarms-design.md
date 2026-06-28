# Design Doc: Time-Based Alarms (Hybrid Approach)

**Status:** Proposed · **Author:** GeoNap team · **Created:** 2026-06-28
**Target branch:** `time-based-alarms` (cut from `alarmkit-migration`)

## 1. Summary

Add a Settings option that lets an alarm's trigger be defined either by **distance**
(today's behavior — a fixed-radius geofence) or by **time** ("wake me _X_ minutes
before arrival"). The time-based mode estimates arrival using a rolling-average
travel speed and fires the alarm when the estimated time of arrival (ETA) drops to
the requested lead time.

This is the canonical nap-on-transit use case: a rider sets a destination, naps,
and wants to be woken a fixed number of minutes before the stop — independent of
how far away that turns out to be in metres.

## 2. Background: how triggering works today

- Background triggering is done **entirely** by iOS fixed-radius region monitoring
  (`CLCircularRegion` via `LocationManager.startMonitoring(region:)`). iOS wakes the
  app at the boundary even while suspended, at near-zero battery cost.
- Continuous location streaming (`startUpdatingLocation`) runs **only while the app
  is foregrounded**. There is no `allowsBackgroundLocationUpdates`, so continuous
  fixes stop when the app is suspended. (Confirmed in `LocationManager.swift`; the
  debug log shows 1 Hz fixes while active and multi-hour gaps while suspended.)
- `Info.plist` already declares the `location` background mode, so enabling
  continuous background updates requires **no new entitlement** — only a code flag.
- `NapAlarm.radius` is a simple `Double` (default 200 m). No lead-time concept exists.
- A GTFS transit feature already exists (`Transit/GTFSService.swift`,
  `TransitAlarmView.swift`) and is the natural future source of route-accurate ETAs.

## 3. The core problem

A live ETA = remaining distance ÷ rolling-average speed must be **recomputed
continuously**. That is fundamentally incompatible with a single fixed circle set
once at creation time, because:

1. Travel speed is unknown at creation (the user is stationary, about to nap).
2. A `CLCircularRegion` radius cannot adapt as speed changes mid-journey.

Therefore time-based triggering is **not** merely a different way to compute the
radius — it needs a different background execution model (continuous GPS) for the
portion of the trip where timing precision matters.

## 4. Goals / Non-goals

**Goals**
- Per-alarm choice of distance-based or time-based triggering, gated by a Settings
  toggle that changes the creation screen input (radius slider ⟷ "minutes before").
- Time-based alarms fire within a reasonable tolerance of the requested lead time.
- Keep battery cost bounded — do **not** stream GPS for the whole journey.
- Preserve today's distance-based behavior unchanged as the default.

**Non-goals (this iteration)**
- Route-accurate (along-track) distance. v1 uses straight-line distance; GTFS
  integration is a follow-up (see §10).
- Multi-leg journeys / transfers.
- Changing the AlarmKit presentation/snooze behavior.

## 5. Design: the hybrid model

Keep region monitoring as the low-power "get close" layer; add continuous tracking
only for the final approach.

1. **Arm (at creation/save).** Convert the requested lead time `L` (minutes) into a
   generous **outer geofence** radius using a capped assumed speed `Vcap`:
   `outerRadius = clamp(Vcap * L, minOuter, maxOuter)`.
   Example: `L = 5 min`, `Vcap = 40 m/s (~144 km/h)` → ~12 km ring.
   Monitor it the cheap way (`CLCircularRegion`, notify on entry).
2. **Idle far away.** Until the user enters the outer ring, the app stays suspended —
   identical battery profile to today.
3. **Activate near destination.** On `didEnterRegion` for the outer ring, the app
   wakes and enables continuous background tracking
   (`allowsBackgroundLocationUpdates = true`, `startUpdatingLocation`).
4. **Track + estimate.** Maintain a rolling-average speed over recent accurate fixes;
   each update compute straight-line distance to the destination and `ETA = dist / v`.
5. **Fire.** When `ETA <= L`, present the AlarmKit alarm (reuse the existing
   `GeoAlarmScheduler.fire` path) and stop continuous tracking.
6. **Backstops.** Also keep a small **inner distance geofence** (e.g. the current
   default radius) so that if GPS is lost (tunnel) or speed can't be estimated, the
   alarm still fires on proximity rather than never firing.

```
        outer ring (≈ Vcap × L)              destination
   ──────●───────────────────────────────────────●──────
         │ enter → wake app, start continuous     │ inner ring (proximity backstop)
         │ tracking + ETA engine                  │
         └───── fire when ETA ≤ L minutes ────────┘
```

## 6. Data model changes (`NapAlarm`)

```swift
enum TriggerMode: String, Codable { case distance, time }

var triggerMode: TriggerMode = .distance     // new; default preserves today's behavior
var leadTimeMinutes: Int = 5                  // used when triggerMode == .time
// `radius` retained: distance mode uses it directly; time mode uses it as the
// inner proximity backstop radius.
```

SwiftData migration: additive, defaulted — existing alarms deserialize as `.distance`.

## 7. LocationManager changes

- Add `startContinuousUpdates()` / `stopContinuousUpdates()` that set
  `allowsBackgroundLocationUpdates`, `pausesLocationUpdatesAutomatically = false`,
  and start/stop `startUpdatingLocation`. Only invoked during final approach.
- Add a rolling-speed estimator fed by `didUpdateLocations`:
  - Keep a short window (e.g. last 45–60 s) of fixes with `horizontalAccuracy >= 0`
    **and** `< 50 m` (reject the coarse wake-up fixes documented in the GPS analysis).
  - Average `CLLocation.speed` over the window (ignore negative/invalid speeds);
    fall back to deriving speed from successive distance/time deltas when
    `speed` is unreliable.
- Expose `currentETA(to:)` returning `TimeInterval?` (nil when speed ≈ 0 or no fixes).

## 8. AlarmManager arm/fire logic

- **Arm:** when `triggerMode == .time`, register the outer ring (entry) + inner ring
  (proximity backstop). When `.distance`, behave exactly as today.
- **On outer-ring entry:** start continuous tracking and an ETA evaluation loop.
- **Fire when** `ETA <= leadTimeMinutes` **or** inner-ring proximity hit **or** an
  explicit max-approach timeout — whichever first. Then `GeoAlarmScheduler.fire(...)`
  and `stopContinuousUpdates()`.
- Respect the existing `isWithinWindow()` time-window guard and the single-fire state
  machine (`isActive` gate) already in `handleRegionEvent`.

## 9. ETA algorithm (pseudocode)

```
window = fixes in last 60s with accuracy in [0, 50)
v = robustMean(window.map{ $0.speed >= 0 ? $0.speed : derivedSpeed($0) })
if v < vMin (e.g. 1.0 m/s):           // stopped at a signal/station
    eta = ∞                            // do not fire on time; rely on backstops
else:
    dist = haversine(current, destination)
    eta  = dist / v
fire if eta <= leadTimeMinutes * 60
```

Weight recent fixes more heavily so deceleration near the stop is reflected quickly.

## 10. Known accuracy limitations (be explicit with users)

- **Straight-line vs. route distance.** Haversine underestimates the real track/road
  path, biasing the alarm **early**. Largest error source in v1. GTFS route geometry
  (existing `GTFSService`) is the fix and should be the v2 ETA source.
- **Deceleration near stops.** Rolling average lags exactly where precision matters;
  recency weighting mitigates.
- **GPS dropouts** (tunnels/cuttings): handled by the inner proximity backstop.
- **Low-accuracy fixes** corrupt speed/ETA; the `< 50 m` accuracy gate is mandatory.

## 11. Battery

Continuous GPS costs roughly 10–20%/hour. The hybrid confines that cost to the final
approach (inside the outer ring), so a long nap far from the destination is as cheap
as today. Surface a one-line battery note in the time-mode UI.

## 12. Settings / UX

- **Settings:** new toggle "Alarm trigger by: Distance / Time (minutes before arrival)".
  Global default for the creation screen input mode (still overridable per alarm if we
  choose to expose it on the form later).
- **Creation screen:** in time mode, replace the radius slider with a "Wake me ___
  minutes before arrival" stepper; keep the map destination picker unchanged. Show the
  computed outer-ring estimate and the battery note.
- Localize all new strings across the existing 13 languages; keep
  `LocalizationTests` tokens intact.

## 13. Edge cases

- Speed ≈ 0 → ETA undefined → never fire early; backstops cover it.
- Overshoot (already past destination when activated) → fire immediately.
- User sets time mode but travels on foot → still works (low Vcap → small outer ring);
  consider a mode-appropriate `Vcap`.
- App killed during approach → relaunch re-arms rings from persisted alarms;
  continuous tracking resumes on next outer-ring entry / significant-location change.

## 14. Testing

- Unit: ETA math (incl. v≈0, invalid speeds, accuracy gating), outer-radius
  computation, model migration defaults.
- Simulation: feed recorded `.gpx`/log traces (e.g. `PennStation.gpx`) through the ETA
  engine and assert fire timing within tolerance.
- Device: real transit run; verify fire lead time, battery delta, and tunnel/backstop
  behavior. (Xcode + device required — cannot build against the iOS SDK in this env.)

## 15. Phased plan

1. **Scaffolding (low risk):** `TriggerMode` + `leadTimeMinutes` on `NapAlarm`
   (migration), Settings toggle, creation-screen input switch. No behavior change to
   distance alarms.
2. **ETA engine:** rolling-speed estimator + `currentETA(to:)` + unit tests with
   simulated traces.
3. **Hybrid arm/fire:** outer + inner ring registration, continuous-tracking
   activation on outer entry, ETA fire + backstops in `AlarmManager`.
4. **Polish:** battery note, localization (13 langs), device verification.
5. **v2 (separate):** swap straight-line distance for GTFS route-accurate ETA on
   transit alarms.

## 16. Open questions

- Default lead time and `Vcap` per travel context (walk/bus/train)?
- Expose trigger mode per-alarm on the form, or Settings-global only for v1?
- Min/max bounds for the outer ring; behavior when destination is very close at arm time.
