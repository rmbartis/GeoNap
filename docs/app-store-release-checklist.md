# GeoNap — Remaining "Release to App Store" Tasks

Reference checklist, in priority order. Each item is marked **You manage** (requires your Apple Developer / App Store Connect account, Xcode signing session, or physical device — I have no access to these), **I execute** (I can do this directly via file edits), or **Split** (part mine, part yours).

**Scope confirmed 2026-08-06: all 4 tiers (Free, Silver $2.99/yr, Gold $6.99/yr, Platinum $12.99 lifetime) are meant to be purchasable.** This is a bigger remaining lift than the previous version of this checklist assumed — that version only tracked configuring the Platinum IAP, because no real purchase code exists yet for *any* tier. `EntitlementManager` (see `GeoAlarm/Services/EntitlementManager.swift`) is currently a simulation only: every real-world user is hardcoded to Platinum until StoreKit is actually wired up. That's the biggest open item below, not a footnote.

Already completed and not repeated here: Crashlytics/Firebase removal, Help text tier/pricing cleanup, the tier rename (Standard→Silver→Gold→Platinum, positionally shifted up one metal level, same prices), and the 4-tier feature-gating simulation (tag `four-tier-feature-set-support`).

---

## Phase 1 — Account setup (blocks everything else)

### 1. Confirm Paid Apps Agreement, tax forms, and banking are on file — **You manage**
Nothing involving money — subscriptions or the one-time purchase — can go live in App Store Connect until this is complete. Do this first; it can take time to process.

- **1a. Sign the Paid Apps Agreement.** As the Account Holder, go to App Store Connect → Business → Agreements, find the "Paid Apps" row, and click "View and Agree to Terms." This is the actual gate — nothing else in this checklist can start until it's signed.
- **1b. Complete your tax forms.** Still on the Agreements page, find the Tax Forms section and click "Add Tax Info" next to the form you need. If you're US-based, this is a W-9. Depending on where your account is registered, Apple may ask for additional forms.
- **1c. Add your banking information.** Only becomes available once the agreement is signed and tax forms are submitted — Apple requires both first before it lets you enter where to send payments.
- **Timing:** once everything above is submitted, the paid contract itself usually activates within about 24 hours — but tax form processing can take up to 90 days in some cases. Since this blocks every Phase 2+ task (creating Silver, Gold, and Platinum), start this as early as possible.

### 2. Decide whether to enroll in Apple's Small Business Program — **You manage**
If your annual proceeds are under $1M, this drops Apple's commission from 30% to 15% on everything. Worth confirming before products go live, since it affects what you actually net per sale.

- Requires step 1a (Paid Apps Agreement signed) to be done first, but does NOT depend on 1b/1c — you can apply in parallel with tax forms/banking rather than waiting.
- Go to developer.apple.com/app-store/small-business-program, click Enroll, and sign in with your Apple Developer account.
- Apple pre-fills your name, email, and Team ID. Review it, answer whether you have any other linked/associated developer accounts, and submit.
- Takes about 5 minutes to fill out, but Apple's review can take over a month — apply now even if you don't need the lower rate immediately, since there's no downside to having it approved early.
- Once approved, your proceeds adjust 15 days after the end of the fiscal calendar month in which the enrollment was approved — not instantly.

---

## Phase 2 — Configure the 3 purchasable products in App Store Connect

### 3. Create a Subscription Group with Silver and Gold as ranked levels — **You manage**
Silver ($2.99/yr) and Gold ($6.99/yr) both need to live in one subscription group, with Gold ranked above Silver. This is what lets a user upgrade from Silver to Gold (or downgrade back) with Apple handling the price proration automatically — without this grouping, switching tiers doesn't work cleanly.

### 4. Add localized listing info for Silver and Gold — **Split**
Each subscription product needs a display name, description, and a review screenshot in App Store Connect. I can draft the English copy; you'll need to add it (and any other languages you want at launch) into ASC directly, since that's account-side.

### 5. Create Platinum as a one-time (non-consumable) purchase — **You manage**
This is a separate product type from Silver/Gold — it sits outside the subscription group since it's a single payment, not a recurring one. Decide whether to allow Family Sharing on it.

### 6. Attach all three products to the next app version for review — **You manage**
The very first time any IAP goes live, it has to be submitted for review attached to an actual app build — none of the three can go live standalone.

### 7. (Optional, can wait until after launch) Set lower pricing for price-sensitive countries — **You manage**
From our earlier pricing discussion: Apple's default pricing tracks currency exchange, not what people can actually afford. Setting custom lower prices for countries like Vietnam, Indonesia, the Philippines, and India (roughly 40% of the US price) captures buyers in the exact markets GeoNap's commuter audience lives in. Not required to launch — can be added later once you see real conversion data.

---

## Phase 3 — Build the actual purchase system (the biggest gap)

### 8. Turn on the In-App Purchase capability in Xcode — **You manage**
A one-time setting in Signing & Capabilities. Needs your Apple ID signed into Xcode.

### 9. Replace the simulated tier system with a real purchase check — **I execute, you test**
Right now, `EntitlementManager` doesn't check any real purchase — it just assumes every release-build user is Platinum. This step swaps that out for Apple's real purchase-checking system (StoreKit), so the app actually knows what a user paid for. Per the existing "single point of control" rule already documented in the code, this change should touch *only* that one property — everything else in the app already reads through it correctly, so nothing else needs to change.

### 10. Build the purchase screen (paywall) — **I execute, you test**
The screen where a user compares Free/Silver/Gold/Platinum and taps to buy. Needs a "Restore Purchases" button (Apple requires this) and links to your Terms of Use and Privacy Policy.

### 11. Add a "Manage Subscription" link in Settings — **I execute**
A simple link that sends Silver/Gold subscribers to Apple's own subscription-management screen to cancel or change plans.

### 12. Create a StoreKit test configuration file — **I execute**
Lets you test purchases directly in the Xcode Simulator without needing a live App Store Connect connection or real money.

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
Across all 4 targets (GeoNap, Watch app, Watch widget, Live Activity extension). Just tell me the numbers.

### 22. Switch archive signing from Development to Distribution — **You manage**
In Signing & Capabilities, for each of the 4 targets.

### 23. Export compliance declaration — **You manage**
Answered at submission time; standard iOS encryption typically qualifies for the usual exemption.

### 24. Submit for App Review — **You manage**
The final step, once everything above is complete.

---

## Deferred (post-release, low priority)
- **Rename `runShortcut.goldRequired` string key** to match the new tier name — purely internal cleanup, no user-facing effect. (Note: this key name is now stale after the Gold→Platinum rename for the lifetime tier — worth folding into whichever pass touches that string next.)
