# GeoNap — Remaining "Release to App Store" Tasks

Reference checklist, in priority order. Each item is marked **You manage** (requires your Apple Developer / App Store Connect account, Xcode signing session, or physical device — I have no access to these), **I execute** (I can do this directly via file edits), or **Split** (part mine, part yours).

**Scope confirmed 2026-08-06: all 4 tiers (Free, Silver $2.99/yr, Gold $6.99/yr, Platinum $12.99 lifetime) are meant to be purchasable.** This is a bigger remaining lift than the previous version of this checklist assumed — that version only tracked configuring the Platinum IAP, because no real purchase code exists yet for *any* tier. `EntitlementManager` (see `GeoAlarm/Services/EntitlementManager.swift`) is currently a simulation only: every real-world user is hardcoded to Platinum until StoreKit is actually wired up. That's the biggest open item below, not a footnote.

Already completed and not repeated here: Crashlytics/Firebase removal, Help text tier/pricing cleanup, the tier rename (Standard→Silver→Gold→Platinum, positionally shifted up one metal level, same prices), and the 4-tier feature-gating simulation (tag `four-tier-feature-set-support`).

---

## Phase 1 — Account setup (blocks everything else) — ✅ COMPLETE (2026-08-08)

### 1. Confirm Paid Apps Agreement, tax forms, and banking are on file — ✅ **DONE (2026-08-08)**
Nothing involving money — subscriptions or the one-time purchase — can go live in App Store Connect until this is complete. Do this first; it can take time to process.

- **1a. Sign the Paid Apps Agreement.** ✅ Done. As the Account Holder, go to App Store Connect → Business → Agreements, find the "Paid Apps" row, and click "View and Agree to Terms." This is the actual gate — nothing else in this checklist can start until it's signed.
- **1b. Complete your tax forms.** ✅ Done. Still on the Agreements page, find the Tax Forms section and click "Add Tax Info" next to the form you need. If you're US-based, this is a W-9. Depending on where your account is registered, Apple may ask for additional forms.
- **1c. Add your banking information.** ✅ Done. Only becomes available once the agreement is signed and tax forms are submitted — Apple requires both first before it lets you enter where to send payments.
- **Timing:** once everything above is submitted, the paid contract itself usually activates within about 24 hours — but tax form processing can take up to 90 days in some cases. Worth double-checking the Agreements page in a few weeks to confirm tax processing has fully cleared, even though Phase 2 is unblocked now.

### 2. Decide whether to enroll in Apple's Small Business Program — ⏳ **SUBMITTED (2026-08-08) — awaiting Apple approval**
If your annual proceeds are under $1M, this drops Apple's commission from 30% to 15% on everything. Worth confirming before products go live, since it affects what you actually net per sale.

- Requires step 1a (Paid Apps Agreement signed) to be done first, but does NOT depend on 1b/1c — you can apply in parallel with tax forms/banking rather than waiting.
- Go to developer.apple.com/app-store/small-business-program, click Enroll, and sign in with your Apple Developer account.
- Apple pre-fills your name, email, and Team ID. Review it, answer whether you have any other linked/associated developer accounts, and submit.
- Takes about 5 minutes to fill out, but Apple's review can take over a month — application submitted; commission stays at the standard 30% until Apple approves it.
- Once approved, your proceeds adjust 15 days after the end of the fiscal calendar month in which the enrollment was approved — not instantly. **Follow-up needed:** check back on approval status in ~4–6 weeks.

---

## Phase 2 — Configure the 3 purchasable products in App Store Connect — 🟡 METADATA COMPLETE, 6b INTENTIONALLY DEFERRED (2026-08-08)

Phase 1 is complete. Detailed click-by-click steps for all five items are in `docs/app-store-connect-phase2-steps.md`.

Items 3, 4, 5, and 6a are all done — every product (Silver, Gold, Platinum) is fully configured with pricing, localization, and a placeholder review screenshot. **Not marking Phase 2 fully complete yet**, because 6b ("Add for Review") is deliberately held until item 10a swaps in the real paywall screenshot — submitting now with the placeholder risks locking the metadata mid-review. That's the one remaining item, and it's expected to stay open until Phase 3's paywall (item 10) is built. Item 7 (regional pricing) is optional and can wait.

### 3. Create a Subscription Group with Silver and Gold as ranked levels — ✅ **DONE (2026-08-08)**
Silver ($2.99/yr) and Gold ($6.99/yr) both need to live in one subscription group, with Gold ranked above Silver. This is what lets a user upgrade from Silver to Gold (or downgrade back) with Apple handling the price proration automatically — without this grouping, switching tiers doesn't work cleanly.

- ✅ Group "GeoNap Tiers" created, Silver and Gold both created inside it with correct Product IDs and 1-year duration.
- ✅ Ranking fixed and confirmed persisted after reload: Level 1 = Gold, Level 2 = Silver.

### 4. Add localized listing info for Silver and Gold — ✅ **DONE (2026-08-08)**
Each subscription product needs a display name, description, and a review screenshot in App Store Connect.

- ✅ Display Name entered for both (`GeoNap Silver`, `GeoNap Gold`).
- ✅ Description confirmed filled in for both: Silver = "Unlimited alarms, Auto-Notify & custom sounds"; Gold = "Transit agency alarms, hands-free SMS & repeat mode."
- ✅ Review Screenshot uploaded to Review Information → Screenshot for both (placeholder: Settings screen showing the Gold-locked Alarm Trigger and Silver-locked Auto-Notify Defaults rows, cropped/resized to exactly 640×920px, no alpha).

### 5. Create Platinum as a one-time (non-consumable) purchase — ✅ **DONE (2026-08-08)**
This is a separate product type from Silver/Gold — it sits outside the subscription group since it's a single payment, not a recurring one. **Decided 2026-08-08: Family Sharing ON** (adoption/goodwill value on a pre-launch $12.99 one-time purchase outweighs the small per-seat revenue at stake, and doesn't touch the real recurring revenue engine of Silver/Gold).

- ✅ Availability, Price Schedule ($12.99 USD), Display Name, Description all done.
- ✅ Review Screenshot uploaded to Review Information → Screenshot (same placeholder image as Silver/Gold, 640×920px).
- ✅ Family Sharing confirmed On ("This in-app purchase can be shared by everyone in a family group").
- Skippable/not required: the "App Store Promotion" image (optional, only needed if featuring Platinum editorially), Review Notes (optional), Tax Category (default "Match to parent app" is fine as-is).

### 6. Finish Silver/Gold/Platinum metadata and attach all three to the next app version for review — **You manage**
The very first time any IAP goes live, it has to be submitted for review attached to an actual app build — none of the three can go live standalone. Two parts:

- **6a. Finish each product's metadata.** ✅ **DONE (2026-08-08)** — Silver, Gold, and Platinum all fully complete (pricing, localization, screenshot). Subscription Group's own localization (group display name `GeoNap`) also confirmed saved.
- **6b. Click "Add for Review"** on the subscription group page (covers Silver + Gold together) and on the Platinum IAP page, to attach all three to the next app version. **Hold off on this until item 10a's real screenshot is in place** — submitting now with the placeholder screenshot risks locking that metadata while Apple reviews it, meaning you'd have to wait it out (or pull the submission) before swapping in the real one later. Not started — blocked on 6a first, then waits for 10a regardless.

### 7. (Optional, can wait until after launch) Set lower pricing for price-sensitive countries — **You manage**
From our earlier pricing discussion: Apple's default pricing tracks currency exchange, not what people can actually afford. Setting custom lower prices for countries like Vietnam, Indonesia, the Philippines, and India (roughly 40% of the US price) captures buyers in the exact markets GeoNap's commuter audience lives in. Not required to launch — can be added later once you see real conversion data.

---

## Phase 3 — Build the actual purchase system (the biggest gap)

### 8. Turn on the In-App Purchase capability in Xcode — ✅ **DONE (2026-08-08)**
Added to the GeoNap target's Signing & Capabilities (not the Watch app/widget/Live Activity extension — only the main app calls StoreKit). Clean build confirmed successful.

### 9. Replace the simulated tier system with a real purchase check — ✅ **DONE (2026-08-08)**
Added `PurchaseManager.swift` (StoreKit 2) as the sole file that talks to StoreKit directly — loads the three products, resolves the highest owned tier from `Transaction.currentEntitlements`, listens for renewals/Family Sharing/Ask to Buy via `Transaction.updates`, and exposes `purchase(_:)`/`restorePurchases()` for the paywall (item 10) to call. `EntitlementManager.verifiedTier` is the new real entitlement, and RELEASE's `currentTier` now reads it instead of hardcoded `.platinum`; DEBUG is unchanged (`testOverride ?? .platinum`), per the existing documented policy. Per the "single point of control" rule, no other file was touched — every gated feature still reads through `EntitlementManager.isEntitled(to:)` exactly as before. Clean build, no warnings, tagged checkpoint before this landed: `pre-app-store-entitlement-changes`.

Nothing purchasable yet — that's item 10 (the paywall UI), which is what will actually call `purchase(_:)`.

### 10. Build the purchase screen (paywall) — ✅ **DONE (2026-08-09)**
Added `PaywallView.swift`: compares Free/Silver/Gold/Platinum with live StoreKit pricing, Subscribe/Buy actions per tier, a required "Restore Purchases" button, and links to Privacy Policy (in-app, `PrivacyView`) and Terms of Use (Apple's Standard EULA as an interim stand-in until item 14 lands — swap then). Entry points: tapping any `.tierGated` lock badge now opens it, and Settings has a new "Plan" section with a "See Plans" row. Clean build, no warnings.

English-only strings for now — the other 12 languages are item 18's separate scope, not part of this item.

### 10a. Replace the placeholder review screenshots with real paywall screenshots — **You manage**
⚠️ **Follow-up, blocked until item 10 is done.** Silver, Gold, and Platinum were each set up in Phase 2 with a placeholder review screenshot (a Settings screen showing the locked features), since the real paywall didn't exist yet. Once this item's paywall is built and running in Simulator/on a device, take a real screenshot of it — exactly 640 × 920 px, PNG or JPEG, no alpha channel — and upload it to each of the three products' App Store Connect pages (Subscriptions → [Silver/Gold] → Localization → English (U.S.) → Review Screenshot; In-App Purchases → Platinum → same field), replacing the placeholder. **This is what item 6b was waiting on** — once the real screenshot is in for all three, go back and click "Add for Review" on the subscription group and on Platinum.

### 11. Add a "Manage Subscription" link in Settings — ✅ **DONE (2026-08-09)**
Added a "Manage Subscription" row to the Plan section (right below "See Plans"), backed by StoreKit's native `.manageSubscriptionsSheet` SwiftUI modifier — no custom UI needed, Apple provides the whole sheet. Shown unconditionally rather than gated on current ownership. Clean build.

### 12. Create a StoreKit test configuration file — ✅ **DONE (2026-08-09)**
Added `GeoNap.storekit` (inside the synchronized `GeoAlarm/` folder), matching live ASC pricing/ranking: Silver $2.99/yr, Gold $6.99/yr (Level 1), Platinum $12.99 one-time. Selected in Product → Scheme → Edit Scheme → Run → Options.

**End-to-end confirmed working (2026-08-09)** on a Release-configured Simulator build (DEBUG intentionally ignores real StoreKit results — see item 9): started on Free, all three lock badges present; purchased Silver → Gold/Platinum badges remained, Silver's cleared and Plan showed Silver; repeated through Gold and Platinum, each unlocking correctly. Confirms items 9, 10, and 12 all work together correctly.

---

## Phase 4 — Content and compliance updates

### 13. Rewrite the App Store description to disclose pricing — **I execute**
The current draft (`docs/appstore-copy.md`) reads like a fully free app — no mention of tiers or pricing anywhere. Apple requires subscription pricing and terms to be disclosed in the app's description or metadata; this needs a rewrite.

### 14. Write (or adopt Apple's standard) Terms of Use — **I execute, you review**
Needs to be linked both in App Store Connect and on the in-app paywall.

### 15. Confirm the Privacy Policy link still works — **You manage, I can verify**
The privacy policy file was renamed recently (`privacy-policy.html` → `privacy.html`). If your App Store Connect listing or in-app link still points to the old filename, it's now a dead link — worth checking before submission.

### 16. Complete the App Privacy questionnaire in App Store Connect — **You manage**
The data-collection disclosure form. Should already be straightforward since it was reconciled against the privacy policy in an earlier pass — just needs your login to submit.

### 17. Update App Review notes to explain the purchase flow — **I execute**
Apple's reviewer needs to know how to test all 4 tiers. The in-app DEBUG-only tier simulator won't exist in the release build, so the notes need to point reviewers to a Sandbox test account instead.

### 18. Localize the new paywall and purchase-related text — **I execute**
Same 13-language treatment as the rest of the app.

---

## Phase 5 — Testing

### 19. Test all three purchases in Sandbox — **You manage**
Using a Sandbox tester Apple ID and the StoreKit test config from step 12: confirm buying, upgrading Silver→Gold, downgrading, and Restore Purchases all work correctly.

### 20. Run a TestFlight beta pass on the real purchase flow — **You manage**
Distinct from any earlier TestFlight pass — this one specifically needs to exercise real purchases (via Sandbox), not the old DEBUG-only tier simulator.

---

## Phase 6 — Final release mechanics

### 21. Bump version and build numbers — **I execute**
Across all 4 targets (GeoNap, Watch app, Watch widget, Live Activity extension). **Decided 2026-08-08: marketing version `1.0`** — set on the App Store Connect "iOS App Version 1.0" record (App Store tab, `Prepare for Submission` status), which is this app's first-ever public release.

⚠️ **Not yet applied in Xcode.** The project is currently `MARKETING_VERSION = 1.61`, `CURRENT_PROJECT_VERSION = 62` (project.pbxproj) — left as-is deliberately, since Phase 3–5 still need several more TestFlight builds first and TestFlight isn't tied to the ASC version record. Don't change it yet. Right before the real archive for item 24, this needs to become `MARKETING_VERSION = 1.0` (matching the ASC record exactly, or the build won't be selectable for it) with `CURRENT_PROJECT_VERSION` bumped forward from wherever TestFlight testing left off (build numbers must keep increasing — don't reset to 1). Tell me when you're ready for this and I'll make the change across all 4 targets.

### 22. Switch archive signing from Development to Distribution — **You manage**
In Signing & Capabilities, for each of the 4 targets.

### 23. Export compliance declaration — **You manage**
Answered at submission time; standard iOS encryption typically qualifies for the usual exemption.

### 24. Submit for App Review — **You manage**
The final step, once everything above is complete.

---

## Deferred (post-release, low priority)
- **Rename `runShortcut.goldRequired` string key** to match the new tier name — purely internal cleanup, no user-facing effect. (Note: this key name is now stale after the Gold→Platinum rename for the lifetime tier — worth folding into whichever pass touches that string next.)
