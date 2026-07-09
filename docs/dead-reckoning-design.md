<!-- Copyright © 2026 Robert Bartis. All rights reserved. -->

# Design Doc: Dead Reckoning on Signal Loss (Per-Alarm, Opt-In)

**Status:** Implemented (v1) · **Author:** GeoNap team · **Created:** 2026-07-03 · **Updated:** 2026-07-03
**Target branch:** `dead-reckoning` (cut from `time-based-alarms` at tag `pre-dead-reckoning`)
**Depends on:** `docs/time-based-alarms-design.md` (the hybrid distance/time trigger this feature extends)

## 1. Summary

Add an opt-in, **per-alarm** setting — "Dead Reckoning on Signal Loss" — for
time-based alarms only. When enabled, and continuous GPS updates stop arriving
mid-approach (subway tunnel, dead zone, parking structure), the app extrapolates
the alarm's remaining distance from the last known fix and closing rate for a
short, hard-capped grace period, and keeps evaluating "should this fire?" against
that estimate instead of going dark until the inner-ring geofence backstop
eventually catches it.

This is off by default and scoped to individual alarms so its inherent imprecision
is only accepted by the users who explicitly choose it — typically someone with a
specific, recurring commute where they already know signal drops out shortly
before their stop (e.g., a subway alarm where the last minute of track is
underground).

## 2. Background: what happens on signal loss today

Per the hybrid design (`time-based-alarms-design.md` §5–8), a time-based alarm
runs two layers once armed:

1. A continuous-GPS ETA engine (`AlarmManager.etaEstimators` /
   `handleLocationUpdate`) that fires when estimated time-to-arrival drops to the
   requested lead time.
2. An inner proximity geofence (`NapAlarm.clRegion`) that fires on simple region
   entry, independent of GPS streaming — the same mechanism distance-based
   alarms use exclusively.

When continuous GPS drops out, `handleLocationUpdate` simply stops being called.
Nothing crashes and nothing is silently lost — the alarm still fires, just via
layer 2, at whatever radius was configured, instead of at the requested lead
time. `LocationManager.isLocationUnavailable` already flips true on
`CLError.locationUnknown`/`.network` and drives the existing
`LocationUnavailableBanner`, so the user has *some* visibility that something
degraded, but the ETA engine itself does nothing differently.

This is a safe degradation — the core promise ("you will not sleep through your
stop") holds regardless — but it's a disappointing one for exactly the case that
motivated time-based alarms: a rider naps through a route where the last stretch
before their stop reliably loses signal, and gets little to no early warning that
trip.

## 3. The core problem

- iOS gives no explicit "signal lost" event. We infer it from
  `isLocationUnavailable` (CLError-driven) or, as a supplement, from simply
  noticing no `didUpdateLocations` callback for some window.
- Once a gap starts, there is no fresh ground truth. Any extrapolation is a bet
  on the recent past continuing to hold.
- `CLLocation.course` is frequently invalid (`-1`) at low speed or on many
  devices, so true heading-based projection isn't reliably available — a
  simpler distance-closing-rate model is the realistic option, not full 2-D
  dead reckoning.
- The worst-case moment for this feature to be active is also the moment
  precision matters most: a train decelerating into the very station the alarm
  is for. A constant-rate extrapolation captured just before that deceleration
  will over-project how much ground gets covered, biasing toward an **early**
  fire. This is asymmetric with the failure mode the whole app exists to
  prevent (missing the stop), so it's an acceptable bias, but a real one.

## 4. Goals / Non-goals

**Goals**
- Bridge brief, common signal-loss gaps for a specific alarm the user knows is
  affected, without asking every user to accept the added imprecision.
- Never regress below today's guaranteed floor. Dead reckoning can only ever
  make a time-based alarm fire *earlier* than the existing backstops would —
  it cannot disable, delay, or replace the inner-ring geofence, the
  `isActive` gate, or the `isWithinWindow()` guard.
- Make any dead-reckoning-originated fire distinguishable after the fact
  (debug log tag), so a "this fired too early" report is diagnosable instead
  of a mystery.
- Actively nudge — not just document — users toward a wider margin
  (lead time / radius) when they opt in, since the tradeoff is explicitly
  imprecision for resilience.

**Non-goals (v1)**
- True heading/vector-based dead reckoning. `CLLocation.course` reliability
  doesn't support it; v1 extrapolates a scalar closing rate (distance to
  destination over time), not a 2-D position.
- Any UI or behavior for distance-based alarms. The concept doesn't apply —
  they never run a continuous ETA layer to begin with (see the earlier
  conversation thread: this whole feature is scoped to `triggerMode == .time`).
- Cross-alarm learning of a user's "usual" dead zones. Plausible future work,
  not v1.
- Any change to the straight-line-vs-route-distance limitation already
  documented in `time-based-alarms-design.md` §10 — orthogonal problem,
  separate (GTFS-based) fix.

## 5. Design: guarded, bounded closing-rate extrapolation

1. **Per-alarm opt-in.** `NapAlarm.deadReckoningEnabled: Bool` (default
   `false`). Only meaningful, and only surfaced in the UI, when
   `triggerMode == .time`.
2. **Detect the gap.** While an alarm is being tracked
   (`etaEstimators[alarm.id] != nil`) and `deadReckoningEnabled == true`,
   treat `LocationManager.isLocationUnavailable` flipping `true` as the start
   of a gap. (Open question §14: whether a supplemental no-fix-for-N-seconds
   watchdog is also needed for cases where iOS delivers a stale fix rather
   than throwing an error.)
3. **Snapshot at gap start.** Record: last known distance to destination, a
   closing rate (slope of distance-to-destination over the last couple of
   accepted samples — can be negative if the user was moving away), and the
   last known average speed. No heading is captured or used.
4. **Extrapolate on a timer**, not on real fixes (there are none). Every few
   seconds while the gap is open:
   `virtualDistance = max(0, lastDistance − closingRate × elapsedSinceGapStart)`.
   If `lastSpeed >= minSpeed`, compute `virtualETA = virtualDistance / lastSpeed`
   and fire (tagged as dead-reckoning-sourced) if `virtualETA <= leadTimeMinutes × 60`
   — through the exact same `isActive` / `isWithinWindow()` gates real fires use.
5. **Hard-capped grace period, scaled to lead time.** Resolved (§14): rather
   than one fixed ceiling for every alarm, `NapAlarm.deadReckoningGracePeriod(
   leadTimeMinutes:fraction:minSeconds:maxSeconds:)` returns
   `clamp(leadTimeMinutes × 60 × 0.25, 30, 180)` — a 5-minute-lead alarm gets a
   75 s bridge, a 1-minute-lead alarm floors at 30 s, and anything above a
   12-minute lead ceilings at 180 s. This is the load-bearing safety
   mechanism, not a tuning knob exposed to users — past it, stop projecting
   entirely and fall back to geofence-only behavior, identical to the alarm
   having the flag off.
6. **Resume on real data.** The instant a real fix arrives (or
   `isLocationUnavailable` clears), discard all dead-reckoning state
   immediately and resume normal `handleLocationUpdate` tracking. Dead
   reckoning never competes with real fixes — it only fills the silence.

```
   real fixes ──●──●──●──╳ ─ ─ ─ ─ ─ (gap: DR projecting) ─ ─ ─ ─●──●── real fixes
                            │                                    │
                     gap detected                          fix resumes →
                  (isLocationUnavailable)                 DR state discarded,
                            │                              normal tracking
                    grace period (30–180s cap,
                     scaled to lead time)
                            │
                 if still no fix at cap → stop projecting,
                 revert to inner-ring geofence backstop only
```

## 6. Data model changes (`NapAlarm`)

```swift
/// Opt-in per alarm; only meaningful when triggerMode == .time. Additive,
/// migration-safe — existing alarms deserialize as false (today's behavior).
var deadReckoningEnabled: Bool = false
```

SwiftData migration: additive/defaulted, same pattern used for `triggerMode`
and `leadTimeMinutes`.

## 7. AlarmManager / LocationManager changes

- **LocationManager:** `isLocationUnavailable` already existed and already
  fired on the relevant `CLError` cases, so no new detection mechanism was
  needed — but it had no way to *notify* AlarmManager of a transition, only a
  `@Published` property a SwiftUI view could observe. Added a small closure,
  `var onLocationUnavailableChanged: ((Bool) -> Void)?`, fired via a guarded
  `didSet` on `isLocationUnavailable` (`oldValue != isLocationUnavailable`, so
  redundant identical CLError events don't re-fire it). A supplemental
  staleness watchdog (Timer checking time since the last accepted fix) was
  considered and deliberately deferred — not built in v1 (see §14).
- **AlarmManager:** new private state, populated only for alarms with the
  flag on:
  ```swift
  private struct DeadReckoningSnapshot {
      let gapStartedAt: Date
      let lastDistance: CLLocationDistance
      let closingRate: Double        // m/s; may be negative
      let lastSpeed: CLLocationSpeed
      let minSpeed: CLLocationSpeed
      let graceCap: TimeInterval      // NapAlarm.deadReckoningGracePeriod(leadTimeMinutes:)
  }
  private var deadReckoning: [UUID: DeadReckoningSnapshot] = [:]
  private var deadReckoningTimers: [UUID: Timer] = [:]
  ```
  On gap start (`handleLocationAvailabilityChanged(true)`): snapshot every
  tracked, DR-enabled alarm and start a repeating 5 s timer per alarm. Each
  tick calls `evaluateDeadReckoning(for:now:)` — internal (not private), with
  an injectable `now: Date = Date()`, mirroring the `AddAlarmView.freshLocation`
  testability pattern — which extrapolates and evaluates exactly as in §5
  step 4, reusing `fireTimeBased` (extended with a `TimeBasedFireSource` enum:
  `.liveGPS` vs `.deadReckoning`). On real-fix resume
  (`handleLocationAvailabilityChanged(false)`) or grace-period expiry:
  invalidate the timer and clear the snapshot for that alarm only — other
  concurrently tracked alarms (DR-enabled or not) are unaffected, since state
  is keyed per-alarm-id, matching the existing `etaEstimators` pattern.
  `stopETATracking(_:)` also unconditionally clears any dead-reckoning
  bookkeeping for an alarm id as a safety net, so a fire, deletion, or edit
  can never leave a stray timer running.

## 8. Extrapolation logic (pseudocode)

```
onGapDetected(alarm) where alarm.deadReckoningEnabled:
    guard etaEstimators[alarm.id] != nil else return   // not even tracking yet — nothing to extrapolate from
    snapshot = DeadReckoningSnapshot(
        gapStartedAt: now,
        lastDistance: distance(lastKnownFix, alarm.coordinate),
        closingRate: (distance(sample[-2], alarm.coordinate) - distance(sample[-1], alarm.coordinate))
                     / (t[-1] - t[-2]),                  // m/s; negative = moving away
        lastSpeed: etaEstimators[alarm.id].averageSpeed
    )
    startTimer(every: 5s)

onTick(alarm, snapshot):
    elapsed = now - snapshot.gapStartedAt
    if elapsed >= graceCap (90s):
        log("DR grace period expired for '\(alarm.name)' — reverting to geofence backstop")
        stopTimer(alarm); deadReckoning[alarm.id] = nil
        return
    virtualDistance = max(0, snapshot.lastDistance - snapshot.closingRate * elapsed)
    guard snapshot.lastSpeed >= minSpeed else { return }   // stopped at gap start → never fire on DR alone
    virtualETA = virtualDistance / snapshot.lastSpeed
    guard alarm.isActive, alarm.isWithinWindow() else { return }
    if virtualETA <= alarm.leadTimeMinutes * 60:
        fireTimeBased(alarm, eta: virtualETA, source: .deadReckoning)
        stopTimer(alarm); deadReckoning[alarm.id] = nil

onRealFixResumed(alarm):
    stopTimer(alarm); deadReckoning[alarm.id] = nil   // real data always wins
```

Note the `closingRate` can be negative — if the user was moving away from the
destination right as the gap started, `virtualDistance` grows over time and
correctly never satisfies the fire condition, rather than assuming motion
resumes toward the destination.

## 9. Known accuracy limitations (be explicit with users)

- **Scalar closing rate, not a real position estimate.** No heading is
  modeled. A curve or reversal inside the gap isn't visible to this math.
- **Deceleration near the stop is the worst case.** The rate captured just
  before a vehicle slows for its own destination will over-project distance
  covered — the single most likely source of an early fire, and it happens
  precisely when this feature is most likely to be active.
- **Confidence isn't modeled as a curve, only a cliff.** v1 trusts the
  snapshot fully until the grace-period cap, then stops abruptly, rather than
  probabilistically discounting the further inputs get from the gap start.
  Simpler to reason about and test; a smoother decay is a plausible v2
  refinement if the hard cutoff proves too coarse in practice.
- **Bias is always early, never late.** Because dead reckoning only ever
  triggers `fireTimeBased` earlier than the geofence backstop would have
  fired anyway, the worst outcome is a premature wake-up, not a missed stop.
  The app's core guarantee is unaffected either way — this is the safety
  argument for shipping something intentionally imprecise.

## 10. Settings / UX

- **No global toggle.** Per-alarm only, per the decision to keep the "blast
  radius" scoped to the specific route a user knows is affected.
- **AddAlarmView:** "Dead Reckoning on Signal Loss" toggle, shown only when
  `triggerMode == .time` (hidden entirely in distance mode, matching how the
  lead-time stepper is already conditionally shown), with a one-line subtitle
  ("Bridges brief GPS gaps by estimating your progress").
- **Info icon, not a hard floor (§14 resolved).** Rather than enforcing or
  suggesting a wider lead time/radius via a separate nudge mechanism, the
  toggle carries a small ⓘ button that opens a popover
  (`DeadReckoningInfoSheet`) explaining in place what the feature does, when
  to use it (a route with a known, reliable dead zone right before the stop),
  and why it's off by default (it's a straight-line guess, not a real fix, and
  can only ever fire early — never late — since the geofence backstop still
  applies). This is the resolution of the "hard floor vs. dismissible
  suggestion" open question: a dismissible, on-demand explanation was judged
  sufficient and more consistent with how the rest of the app treats other
  judgment-based settings (e.g. `SettingInfoLabel` in SettingsView), rather
  than adding a new enforced-minimum mechanism.
- **Help screen:** new "Dead Reckoning on Signal Loss" section alongside the
  existing "Trigger: distance or time" entry, covering the same ground as the
  in-context popover at greater length — what it does, how to turn it on, why
  it's off by default, and what to do if it fires too early on a specific
  route. Localized across all 13 languages, same as every other Help addition
  in this project.
- **DebugLogger:** every fire logs its source (`liveGPS` vs `deadReckoning`)
  so a support conversation about an early alarm is diagnosable from a
  debug-log export rather than guesswork.

## 11. Edge cases

- Gap detected before the alarm has entered its warm-up ring
  (`etaEstimators[alarm.id] == nil`) → no-op; nothing to extrapolate from yet.
- Multiple concurrently tracked time-based alarms, only some with the flag on
  → state is keyed per-alarm-id; an alarm without the flag behaves exactly as
  it does today during the same gap, regardless of a sibling alarm's state.
- Real fix resumes mid-grace-period → immediately discard DR state, resume
  normal tracking from the fresh fix (§5 step 6).
- App killed/relaunched during a DR-bridged gap → DR state is in-memory only,
  never persisted. A relaunch always starts clean and re-arms exactly per the
  existing relaunch behavior in `time-based-alarms-design.md` §13 — no stale
  extrapolation can survive a restart.
- `closingRate` negative (moving away at gap start) → handled explicitly in
  §8; virtual distance grows, suppressing a fire rather than assuming
  progress.
- Repeating time-based alarms: the existing, separately-tracked limitation
  that `fireTimeBased` tears down both rings (so a repeating time alarm
  doesn't currently re-arm) is unchanged and unworsened by this feature —
  orthogonal, already flagged in prior review, not addressed here.

## 12. Testing — implemented

- **Pure logic (no CLLocationManager):** `ETAEstimatorTests.swift` covers
  `closingRate(to:)` (positive/negative rates, fewer-than-two-samples nil,
  and a regression guard proving it ignores `CLLocation.course`).
  `NapAlarmModelTests.swift` covers `deadReckoningEnabled` default/round-trip
  and `deadReckoningGracePeriod` boundaries (scaling, floor, ceiling, custom
  bounds). `AlarmViewModelFieldTests.swift` covers the field's round-trip
  through `buildAlarm()`/`load()`/`reset()`, including the existing-alarm
  edit path.
- **AlarmManager integration:** `AlarmManagerDeadReckoningTests.swift`,
  mirroring `AlarmManagerETAFireTests.swift`'s seam pattern (`handleLocation
  AvailabilityChanged` and `evaluateDeadReckoning(for:now:)` are internal, not
  private, and `evaluateDeadReckoning`'s injectable `now:` avoids real
  wall-clock waits in tests). Covers: firing within the grace period, not
  firing before the extrapolated ETA qualifies, grace-period expiry without
  firing (and staying expired on a later evaluation), never firing from a
  standing start (speed below `minSpeed`), a resumed real fix clearing the
  bridge, DR never starting without an active ETA-tracking session, the time
  window guard still applying, and a fire fully tearing down tracking so a
  later evaluation can't double-fire.
- **Critical regression test:** `test_deadReckoning_flagOff_neverBridges` —
  an alarm with `deadReckoningEnabled == false` must never fire from a
  signal-loss extrapolation, even when a tick lands squarely inside a window
  that would fire if the flag were on. This is the single most important test
  in this feature — it's what keeps the opt-in "blast radius" claim actually
  true.
- Localization additions are covered automatically by the existing
  `LocalizationConsistencyTests.swift` key-parity machinery — no new test
  category needed there.

## 13. Phased plan

1. **Scaffolding — done.** `deadReckoningEnabled` field + migration-safe
   `NapAlarm` init parameter, `AlarmViewModel` wiring, AddAlarmView toggle
   (time-mode only).
2. **Core DR engine — done.** `ETAEstimator.closingRate(to:)`,
   `LocationManager.onLocationUnavailableChanged`, AlarmManager's
   `DeadReckoningSnapshot`/`handleLocationAvailabilityChanged`/
   `evaluateDeadReckoning(for:now:)`, source-tagged `fireTimeBased` — unit and
   integration tested, including the critical flag-off regression test.
3. **Guardrail polish — done.** Info-icon popover (in place of a lead-time/
   radius nudge, per the resolved §14 decision), Help screen section, full
   13-language localization pass across the toggle, popover, and Help text.
4. **Device verification — not yet done.** A real transit run through a known
   dead zone with the flag on vs. off on two otherwise-identical alarms,
   confirming the timing difference and confirming the flag-off alarm is
   unaffected. Requires Xcode + a physical device — outside what this
   environment can execute; the next real-world step before considering this
   feature fully validated.

## 14. Open questions — resolved for v1

- **Grace-period length: resolved — scales with lead time.** Implemented as
  `NapAlarm.deadReckoningGracePeriod(leadTimeMinutes:fraction:minSeconds:
  maxSeconds:)`, returning `clamp(leadTimeMinutes × 60 × 0.25, 30, 180)` (see
  §5 step 5, §7). A 20-minute-lead alarm gets the full 180 s ceiling; a
  1-minute-lead alarm floors at 30 s.
- **Staleness watchdog: resolved — not built in v1.** The existing
  `CLError`-driven `isLocationUnavailable` flag (surfaced to AlarmManager via
  the new `onLocationUnavailableChanged` closure, §7) is the only gap-detection
  mechanism shipped. A supplemental no-fix-for-N-seconds watchdog was judged
  speculative without device evidence that iOS actually goes quiet without
  ever throwing a `CLError` — building it now would be guessing at a problem
  that may not occur in practice. Revisit if device/field testing (§13 phase
  4) surfaces gaps that `isLocationUnavailable` misses.
- **Lead-time/radius nudge: resolved — dismissible info icon, not a hard
  floor.** See §10. An enforced minimum was rejected as inconsistent with how
  the rest of the app treats judgment-based settings; the ⓘ popover puts the
  same guidance in the user's hands without gating the toggle behind it.
- Any value in lightweight telemetry on how often DR actually gets exercised
  per alarm, to inform whether a smarter v2 (e.g., per-route learning,
  smoother confidence decay per §9) is worth the investment later? —
  **Still open**, not addressed in v1.
