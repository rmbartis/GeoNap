# GeoNap — Remaining "Release to App Store" Tasks

Reference checklist, in recommended order. Each item is marked **You manage** (requires your Apple Developer / App Store Connect account, Xcode signing session, or physical device — I have no access to these) or **I execute** (I can do this directly via file edits) or **Split** (part mine, part yours).

Already completed and not repeated here: Crashlytics/Firebase removal (verified via archive), Help text tier/pricing cleanup, and the Standard→Silver→Gold→Platinum tier rename.

---

## 1. Bump version and build number — **I execute**
- Update `MARKETING_VERSION` (CFBundleShortVersionString) and `CURRENT_PROJECT_VERSION` (build number) across all 4 targets (GeoNap, NapStopWatch Watch App, NapStopWatchWidgetExtension, GeoAlarmLiveActivityExtension).
- Just tell me the version/build numbers you want and I'll make the edit.

## 2. Switch archive signing from Development to Distribution — **You manage**
- Requires your Apple ID signed into Xcode.
- In Signing & Capabilities, switch each of the 4 targets' Release configuration to a Distribution certificate / App Store provisioning profile (or confirm Automatic Signing picks one up).
- This was flagged because the last archive log showed an Apple Development certificate.

## 3. Run a TestFlight beta pass — **You manage**
- Archive and upload via Xcode Organizer (needs your Apple ID session) — this is the first archive since the Crashlytics removal and tier rename, worth confirming end-to-end.
- Wait for App Store Connect processing, then install via TestFlight on a real device.
- Spot-check: alarm creation/firing, Watch app, widget, Live Activity, and the Run Shortcut / Auto-Notify flows that were just touched by the tier rename.

## 4. Confirm Privacy Policy URL is live and linked — **You manage** (I can verify reachability)
- Host the privacy policy page publicly if not already.
- Enter/confirm the URL in App Store Connect → App Information.
- Share the URL with me and I'll confirm it loads correctly.

## 5. Complete App Privacy questionnaire — **You manage**
- Fill out the data-collection "nutrition label" form in App Store Connect.
- Already reconciled against your privacy policy in an earlier audit, so the answers are ready to enter — just needs your login to submit.

## 6. Configure Platinum tier In-App Purchase — **You manage**
- Create the $12.99 one-time IAP product in App Store Connect.
- Requires the Paid Apps Agreement and banking/tax info on file.
- Attach the product to this version for review.

## 7. Prepare App Store Connect listing assets — **Split**
- **I execute:** draft the app description, keywords, promotional text, and support/marketing URL copy.
- **You manage:** capture screenshots from a real device/simulator (ideally from the TestFlight build in step 3), upload everything into App Store Connect, and set category + age rating.

## 8. Export compliance declaration — **You manage**
- Answer the encryption-use question at upload/submission time.
- Standard iOS encryption only typically qualifies for the usual exemption — I can help you word the answer if you want a second opinion.

## 9. Submit build for App Review — **You manage**
- Final submit in App Store Connect, once everything above is complete.

---

## Deferred (post-release, low priority)
- **Rename `runShortcut.goldRequired` string key** — I execute whenever you're ready. Purely internal naming cleanup across 13 locale files + 2 Swift references; no user-facing effect.
