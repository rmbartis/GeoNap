# App Store Connect — Phase 2 Detailed Steps (Items 3–7)

Expands `docs/app-store-release-checklist.md` items 3–7 into exact click-by-click steps. Requires Phase 1 (Paid Apps Agreement, tax forms, banking) to be complete first — App Store Connect won't let you save pricing on any of these products until that's done.

App: **GeoNap**, bundle ID `com.rmbartis.GeoNap`. All three products below reference the same feature set already shipping in the app (`EntitlementManager.swift` / `AlarmManager.swift` / `SettingsView.swift` / `AddAlarmView.swift`), so the wording here matches what the app actually does — no guessing needed later about what copy to write.

---

## 3. Create the Subscription Group (Silver + Gold)

1. App Store Connect → **Apps** → **GeoNap** → sidebar → **Monetization** → **Subscriptions**.
2. Click the **+** next to "Subscription Groups." Give it a **Reference Name** — this is internal only, never shown to users. Suggestion: `GeoNap Tiers`.
3. Inside the new group, click **+** to create the first subscription.
   - **Reference Name** (internal): `GeoNap Silver Annual`
   - **Product ID**: `com.rmbartis.GeoNap.silver.annual` — once you save this, it's permanent; even if you delete the product later, this exact ID can never be reused.
   - Click **Create**.
4. Repeat for the second subscription in the *same* group:
   - **Reference Name**: `GeoNap Gold Annual`
   - **Product ID**: `com.rmbartis.GeoNap.gold.annual`
5. Set **Subscription Duration** to **1 Year** for both.
6. This is the step that actually matters for upgrade/downgrade to work: open the group's **Subscription Levels** view and drag to rank them —
   - **Level 1 (top): Gold** — ranked highest because it includes everything Silver does, plus more.
   - **Level 2: Silver**
   
   Apple's proration and "which subscription wins if a user has both" logic is driven entirely by this ranking — a user moving from Level 2 → Level 1 is an *upgrade* (prorated immediately), Level 1 → Level 2 is a *downgrade* (takes effect next renewal). Getting Gold above Silver here is the whole reason this step exists.
7. Set the price for each:
   - Silver → **Price Schedule** → set base price **$2.99 USD**. ASC auto-generates equivalent prices in every other territory's currency — you don't need to set them individually (that's item 7, only for the handful of countries where you want to override the auto-generated price).
   - Gold → **$6.99 USD**, same process.

---

## 4. Localized listing info for Silver and Gold

Each subscription needs, at minimum, an English (U.S.) localization before it can go to review. Below is drafted copy, already fitted to Apple's hard limits (Display Name ≤ 30 characters, Description ≤ 45 characters — ASC will simply refuse to save longer text).

### Silver

| Field | Text | Length |
|---|---|---|
| Display Name | `GeoNap Silver` | 13 / 30 |
| Description | `Unlimited alarms, Auto-Notify & custom sounds` | 45 / 45 |

What's actually in it, so the copy stays accurate if the feature set changes: unlimited active alarms (Free is capped at 1), Auto-Notify contacts (tap-to-send SMS when an alarm fires, with your approval), the full custom/premium sound library instead of system sounds only, and the "active time window" scheduling option.

### Gold

| Field | Text | Length |
|---|---|---|
| Display Name | `GeoNap Gold` | 11 / 30 |
| Description | `Transit alarms, hands-free SMS & repeat mode` | 44 / 45 |

Includes everything in Silver, plus: Transit Alarms (GTFS-based transit-stop alarms, fully locked below Gold), the "time before arrival" trigger mode, Repeat/hysteresis mode, hands-free Auto-SMS via a Shortcuts automation (no per-message approval), and custom GTFS cache duration.

### Entering it

1. On each subscription's detail page, scroll to **App Store Information** → click **+** next to **Localizations** (or select the pre-populated "English (U.S.)" row if one already exists).
2. Paste the **Display Name** and **Description** from the tables above.
3. **Review Screenshot** (required before submission, reviewer-only — never shown to customers): a screenshot of your paywall/upgrade screen, **exactly 640 × 920 px**, PNG or JPEG, no transparency/alpha channel. Since the real paywall doesn't exist yet (Phase 3, item 10), placeholder this with a screenshot of the Settings screen showing the locked Gold/Silver features. **Tracked as item 10a in the main checklist** — swapping in the real paywall screenshot only becomes possible once item 10 is built, and has to happen before item 24 (Submit for App Review), so it's logged there as its own follow-up rather than left as a mental note here.
4. Repeat for any additional language you want at launch (optional for initial submission — English-only is fine to start, but every localization you *do* add needs both fields filled in before you can move on).

---

## 5. Create Platinum as a one-time purchase

This is a **separate product type** — created outside the subscription group entirely, since it's a single non-recurring payment.

1. Sidebar → **Monetization** → **In-App Purchases** → click **+**.
2. Select **Non-Consumable**.
3. **Reference Name** (internal): `GeoNap Platinum`
4. **Product ID**: `com.rmbartis.GeoNap.platinum` — same permanence warning as above.
5. Click **Create**, then fill in:
   - **Price Schedule**: **$12.99 USD** (one-time, not a schedule of recurring charges — the name is just ASC's generic term for the pricing screen).
   - **Display Name**: `GeoNap Platinum` (15/30 chars)
   - **Description**: `Run Shortcuts, Live Activity & Calendar scan` (44/45 chars)
   - **Review Screenshot**: same 640 × 920 px spec as above.
6. **Family Sharing** toggle: appears on the non-consumable's detail page. Decide this now —
   - **On**: up to five family members share one Platinum purchase for free. Standard for a one-time "unlock everything" purchase; likely the better default for a $12.99 purchase, since it's a strong goodwill/word-of-mouth feature and Apple explicitly designed non-consumables for this.
   - **Off**: every user pays individually. Only makes sense if you're trying to maximize per-seat revenue over adoption — probably not the right call at this price point, but it's your decision.
   
   Platinum unlocks: Run Shortcut on Alarm (fire any Shortcuts automation when an alarm triggers), Live Activity / Dynamic Island support, Calendar Scanning (auto-detect upcoming trips from the calendar and suggest alarms), and Dead Reckoning on Signal Loss (for the Gold-tier time-before-arrival trigger).

---

## 6. Attach all three products to the next app version

None of the three can go live standalone — the first time any IAP/subscription goes live, it has to ride along with an actual app build through review.

1. Sidebar → **App Store** (formerly "General") → select the version you're preparing for submission (create one now if you haven't — **+ Version or Platform**).
2. Scroll to **In-App Purchases and Subscriptions** on that version's page → click **+**.
3. Check all three: `GeoNap Silver Annual`, `GeoNap Gold Annual`, `GeoNap Platinum`.
4. As of Apple's June 2026 App Store Connect update, all three can now be submitted together as part of the *same* review package as the app binary — you no longer have to submit each IAP as a separate review request. One submission covers the build and all three products.
5. This step doesn't have to happen today — it just has to happen before you hit Submit for Review (Phase 6, item 24). But the products must be in at least "Ready to Submit" status by then, which means items 3–5 above need to be fully filled out (pricing + localization + screenshot), not just created.

---

## 7. (Optional) Lower pricing for price-sensitive countries

Skippable for launch — revisit once you have real conversion data.

1. On each product's page → **Availability and Pricing** → **Price Schedule** → **Manage** (or **Edit Prices**, depending on ASC's current label).
2. Instead of letting Apple auto-generate the local price from the $2.99/$6.99/$12.99 USD base via currency conversion, click into the specific territory (Vietnam, Indonesia, Philippines, India) and manually select a lower USD-equivalent price point — roughly 40% of the US price, per the earlier pricing discussion. Concretely, that's about:
   - Silver: ~$1.19 equivalent
   - Gold: ~$2.79 equivalent
   - Platinum: ~$5.19 equivalent
3. Apple's price list is a fixed set of points, not a free-text field, so you're picking the closest available point at or near that 40% target, not typing an exact number.
4. Save. This only affects those specific territories — every other country keeps the standard currency-converted price.

---

## After this: Phase 3

Items 3–7 only get the products *configured* — nothing is purchasable yet because `EntitlementManager` doesn't check real purchases (see the file's header comment). That's Phase 3 (items 8–12) in the main checklist, and is not blocked on you completing item 7 — items 8+ can start as soon as items 3–6 are done.
