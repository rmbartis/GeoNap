# GeoNap — CI Coverage & Help Review

**Date:** 2026-06-29 · **Branch:** `time-based-alarms` · **Mode:** review + low-risk edits (no Xcode/iOS SDK available here)

> ⚠️ **All code/test changes below require an Xcode build + iOS-26 simulator/device run to verify.**
> Nothing here has been compiled or executed in the authoring environment. The repo `.git` was
> writable (working tree only modified `BuildTimestamp.swift` before this run); changes are left
> staged in the working tree.

---

## TASK 1 — CI Coverage Review

### What CI does today
`.github/workflows/gtfs-tests.yml` is the only workflow. It builds the `GeoNap` scheme on
`macos-15` / Xcode 16.3 against the iPhone 16 simulator and runs three jobs:

| Job | Trigger | Tests |
|-----|---------|-------|
| `unit-tests` | every push + PR | core unit tests (no network) |
| `url-checks` | every push + PR | `GTFSFeedURLTests` (HEAD/range checks, 29 feeds) |
| `parse-tests` | push to `main` / manual | `GTFSParserTests` (full download+parse) |

So **CI does build and run tests**, signing disabled, JUnit artifacts uploaded. Good baseline.

### The headline gap (now fixed)
The `unit-tests` job used a **hand-maintained per-class allow-list**:

```
-only-testing:NapStopTests/NapAlarmModelTests
-only-testing:NapStopTests/AlarmViewModelTests
-only-testing:NapStopTests/AlarmManagerTests
-only-testing:NapStopTests/SoundRegressionTests
-only-testing:NapStopTests/AutoNotifyTests
```

That allow-list only names 5 classes. The `NapStopTests` target actually contains **22 test
classes**. Everything not on the list was **silently excluded from CI** — including the two
suites that cover the most recent work:

- ❌ `ETAEstimatorTests` — the entire time-based / ETA engine + new `NapAlarm` trigger fields
- ❌ `LocalizationTests` — localization integrity across all 13 languages
- ❌ also excluded: `AlarmSchedulingTests` (TimeWindow/ActiveDays/CLRegion/edge-case), `AlarmAudioTests`, `AlarmViewModelFieldTests`, `DebugLoggerTests`/`AlarmManagerDebugLogTests`, `GTFSParserUnitTests`/`CuratedFeedsIntegrityTests`, `NotifyContactTests`, `ShareAndAutoNotifyTests`.

The job's own header comment *claimed* "Executes all NapStopTests EXCEPT the GTFS network tests" —
the implementation never matched that intent, and any newly-added class drops out of CI by default.

**Fix applied** (`gtfs-tests.yml`, `unit-tests` job): run the whole target and skip only the two
network suites, so new classes are picked up automatically:

```
-only-testing:NapStopTests
-skip-testing:NapStopTests/GTFSFeedURLTests
-skip-testing:NapStopTests/GTFSParserTests
```

Verified the now-included suites are network-free: `GTFSParserUnitTests` parses inline fixtures,
`CuratedFeedsIntegrityTests` only validates feed-URL **syntax**, `ShareAndAutoNotifyTests`
constructs an Apple Maps URL **string** (no request). `AlarmAudioTests` runs against the host app
bundle (BUNDLE_LOADER) — fine in the simulator.

> **Expected side-effect:** the first CI run on this change may surface latent failures in
> classes that were never gated before. That is the point — but reviewers should expect possible
> red on first run and triage rather than assume the workflow edit is wrong.

### Coverage of recent changes — assessment

| Recent change | Covered? | By |
|---|---|---|
| `TriggerMode` / `leadTimeMinutes` defaults + round-trip | ✅ | `ETAEstimatorTests` (now in CI) |
| `outerRingRadius(warmupMinutes:)` incl. clamps | ✅ | `ETAEstimatorTests.test_outerRingRadius_includesWarmupAndClamps` |
| `ETAEstimator` (accuracy gate, rolling avg, ETA, shouldFire, derived speed) | ✅ | `ETAEstimatorTests` (6 tests) |
| Vibrate-only → silent-tone mapping (`alarmKitSoundName`) | ✅ | `SoundRegressionTests` (already in CI) |
| Localization integrity (13 langs, tokens, escapes) | ✅ | `LocalizationTests` (now in CI) |
| **AlarmManager hybrid arm/fire** (outer/inner rings, ETA fire) | ⚠️ **partial** | only the warm-up-ring no-fire path is now tested; see below |
| **Auto-SMS freshness guard** (`NotifyContactsIntent`) | ⚠️ **was untested** | now tested (see below) |
| Auto-SMS suppression toggle (`autoSMSAutomationEnabled`) | ⚠️ gap | recommended below |
| Waiting-for-GPS-lock indicator | ❌ gap (UI state) | recommended below |
| In-app language-switch `.id` fix | ❌ gap (SwiftUI identity) | recommended below |

### Tests added this run (`NapStopTests/AutoSMSFreshnessTests.swift`, new file)
The target uses `PBXFileSystemSynchronizedRootGroup`, so the new file is auto-included — no
`.pbxproj` edit needed.

- `NotifyContactsFreshnessTests` — exercises the Auto-SMS **freshness guard**, which previously
  had **no test at all**. To make it unit-testable, the freshness decision in
  `NotifyContactsIntent.perform()` was extracted into a pure, behaviour-preserving helper
  `NotifyContactsIntent.isFresh(firedAt:now:window:)`. Tests cover: fresh body sent, stale body
  rejected, never-fired (`firedAt == 0`) rejected, the inclusive window boundary, and that
  `AutoNotifyDefaultsKey.freshnessWindow` matches the 15-min literal `perform()` uses (drift guard).
- `TimeBasedWarmupRingTests` — regression that **entering the outer warm-up ring must not fire**
  the alarm (state stays `.active`, `triggerCount` stays 0) and that the warm-up region identifier
  is the `:warmup`-suffixed UUID with `notifyOnEntry` only (distinct from the inner proximity ring).
  Uses the existing `simulateRegionEntered` test seam.

> These are **written but not run** — they need an Xcode build to confirm they pass.

### Recommended further tests / CI steps (not added — need new seams or are higher-risk)
1. **AlarmManager ETA fire path.** `handleLocationUpdate` / `beginETATracking` are `private`, so the
   full "feed fixes → fire at lead time" path can't be driven from tests. Add a `simulateLocationUpdate(_:)`
   test seam (mirroring `simulateRegionEntered`) and assert: a time alarm inside the warm-up ring fires
   `.triggered` only once ETA ≤ lead time; respects `isWithinWindow`; and that the "already inside the
   outer ring at arm time" branch in `startMonitoring` begins tracking immediately.
2. **Auto-SMS suppression toggle.** Add a test around `queueAutoNotify`: with
   `autoSMSAutomationEnabled = true`, `pendingContactMessage` must stay `nil` (in-app sheet suppressed)
   while `pendingBody`/`pendingBodyTimestamp` are still written; with it `false`, the compose sheet is queued.
   (Use a non-`.standard` `UserDefaults` suite to avoid CI state bleed.)
3. **GPS-lock indicator** — add a small ViewModel/state unit test for the waiting-for-fix flag transitions.
4. **Language-switch `.id` fix** — hard to unit-test (SwiftUI identity); add a UI smoke test in
   `NapStopUITests` (currently **not run by any CI job** — consider a nightly `ui-tests` job) or at minimum
   document it as a manual release-check item.
5. **Coverage reporting** — add `-enableCodeCoverage YES` to the `unit-tests` job and upload the `.xcresult`,
   so future silent-exclusion gaps are visible as coverage drops rather than going unnoticed.

---

## TASK 2 — Help Review (`HelpView.swift` + `help.body.*`)

### Verdict
Content is thorough and mostly well-written for a non-technical traveler. The Auto-Notify and
Siri sections are **already current** — they correctly use the **"When GeoNap Is Opened"**
automation and explicitly state iOS has no notification trigger (no stale "Receives a Notification"
language anywhere). The **time-based help section already exists and is localized in all 13
languages** (`help.body.timeBased`, "Trigger: distance or time"), so nothing needs to be added there.

Two **stale claims remain**, both removed by the AlarmKit migration and confirmed against source:

1. **CarPlay audio/repeat** — appears twice in every language file:
   - `help.body.whatIsNapAlarm`: "*CarPlay — alarms appear on the car screen; stop or snooze from your phone.*"
   - `help.body.notifications`: "*CarPlay — the alarm appears on screen, but its sound is not played through the car…*"

   `GeoAlarmScheduler.swift`'s migration note states the legacy engine's "CarPlay repeat notifications"
   and "CarPlay-only audio-repeat workarounds" were **removed** under AlarmKit. These bullets should go.

2. **"Critical" sound option** — `help.body.soundVibrate` lists "*Critical — plays at full volume,
   bypassing silent mode and Do Not Disturb.*" But `NotificationSound.all` is `[.vibrate, .default] +
   bundled` — **Critical is no longer offered** (Apple denied the Critical Alerts entitlement, June 2026),
   and AlarmKit already cuts through silent mode/Focus without it. The bullet is misleading; remove it.

Minor accuracy nit (optional): `help.body.soundVibrate` calls Default "*the standard iOS notification
sound*"; under AlarmKit "Default" loops the bundled `_DefaultAlarm.wav`. Consider "a looping alarm tone."

### Recommended section ordering (use-case driven)
Goal: lead with the **primary** use case (nap on a train/bus and get woken before the stop), then the
**secondary** one (arrival/departure reminders + notifying contacts). Two moves vs. today: **Transit
Alarms** up next to Radius (it's core to the commute path), and **Auto-Notify** down below
Notifications/Sound (it's the secondary "tell others" feature). **Applied** — both the `sections` array
and the view body in `HelpView.swift` are reordered consistently:

| # | Section |
|---|---------|
| 1 | What is GeoNap? |
| 2 | Typical use cases |
| 3 | Creating an alarm |
| 4 | **Trigger: distance or time** ← the "wake me X min before my stop" feature, kept early |
| 5 | Radius |
| 6 | **Transit Alarms** (moved up — pick your exact commute stop) |
| 7 | Repeat (daily commuter) |
| 8 | Active time window (commute hours) |
| 9 | **Notifications** (moved up — the wake-up payoff: Stop/Snooze) |
| 10 | Alarm sound / vibrate |
| 11 | **Auto-Notify** (moved down — secondary: notify contacts) |
| 12 | Siri & Shortcuts |
| 13 | Apple Home Automation |
| 14 | Managing alarms |
| 15 | Alarm list icons |
| 16 | Settings |
| 17 | Always On location |
| 18 | Minimum Requirements |
| 19 | Feature Summary |
| 20 | Reporting a problem |

### String wording fixes — recommended, **not yet applied** (to keep all 13 languages in sync)
I deliberately **did not** edit `Localizable.strings` for the two stale claims. Doing the removals
by hand across Arabic/Thai/Hindi/Japanese/etc. without a build or native-speaker check risks
corrupting `.strings` escaping or leaving English diverged from the other 12. None of these keys are
token-checked by `LocalizationTests`, so the safe path is a single coordinated translation pass +
a CI run (`LocalizationTests` is now gated, so it will catch escaping regressions). Concrete edits:

- **`help.body.soundVibrate`** — delete the "Critical" bullet (the `• Critical — …\n` line) in all 13 files.
- **`help.body.whatIsNapAlarm`** — delete the "CarPlay — …" bullet in all 13 files.
- **`help.body.notifications`** — delete the trailing "CarPlay — …" paragraph in all 13 files.

After the pass, run the full unit job (which now includes `LocalizationTests`) to confirm escapes/tokens.

### Things checked and found OK (no change needed)
- No "Receives a Notification" trigger language anywhere (already corrected to "When GeoNap Is Opened").
- Time-based section present + localized in all 13 languages.
- Auto-Notify and Siri sections accurately describe the foreground-open + freshness-window behavior.
- `LocalizationTests` tokens for `help.body.autoNotify` / `help.body.siri` and the AlarmFiringView keys
  (`Snooze 10 min`, `Slide to dismiss`) were **left untouched** — the reorder and recommendations
  preserve every token the tests assert.

---

## Files changed in this run
- `.github/workflows/gtfs-tests.yml` — `unit-tests` job now runs the whole `NapStopTests` target minus the two network suites; header comment updated.
- `GeoAlarm/Intents/NotifyContactsIntent.swift` — extracted behaviour-preserving `isFresh(firedAt:now:window:)`; `perform()` now calls it.
- `NapStopTests/AutoSMSFreshnessTests.swift` — **new**: freshness-guard tests + warm-up-ring no-fire regression.
- `GeoAlarm/Views/HelpView.swift` — section reorder (array + body), use-case driven.

**Not changed (recommended follow-ups):** `Localizable.strings` CarPlay/Critical removals (×13), AlarmManager ETA-fire test seam, suppression-toggle test, GPS-lock + language-switch tests, code-coverage reporting, optional `ui-tests` CI job.
