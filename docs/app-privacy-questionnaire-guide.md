<!-- Copyright © 2026 Robert Bartis. All rights reserved. -->

# App Store Connect — App Privacy Questionnaire Guide

Reference for filling out App Store Connect's App Privacy ("Privacy Nutrition Label") questionnaire — App Information → App Privacy. Based on exactly what GeoNap's code does, cross-checked against `docs/privacy.html`. Not legal advice — Apple's own definitions of "collect" and "linked to you" can shift between guideline versions, so treat this as a strong starting point to verify against the current questionnaire wording, not a substitute for reading it yourself.

**The short version: GeoNap does not transmit any personal data to a server you (the developer) operate.** Everything either stays on-device, or goes only to Apple's own infrastructure (iCloud/CloudKit under the user's own Apple ID, or Apple's geocoding service) as part of a feature the user explicitly turned on.

---

## Question 1: Does this app collect data?

**Answer: Yes.** Even though nothing goes to your own server, Apple's definition of "collect" includes data transmitted off the device at all — including to Apple's own iCloud on the user's behalf. Answering "No" here would be inaccurate given iCloud sync and the geocoding lookups below.

---

## Data types to declare

### Location → Precise Location
- **Used for:** App Functionality (the entire point of the app — geofence monitoring)
- **Linked to you:** **No** — there's no account or login; location isn't tied to an identifiable user profile anywhere off-device.
- **Used for tracking:** **No**

### Contact Info → Name, Phone Number
- Collected only if the user enables Auto-Notify and picks contacts via Apple's system contact picker.
- **Used for:** App Functionality (addressing the automatic "I've arrived" message)
- **Linked to you:** **No** — same reasoning as location; no account system, and this data only ever syncs to the *user's own* private iCloud container if they have iCloud sync on, never to a server you operate.
- **Used for tracking:** **No**

### Contact Info → Email Address
- **Do NOT declare this.** `NotifyContactsIntent.swift` explicitly filters out email contacts (`guard !contact.isEmail else { return }`) — Auto-Notify is phone/SMS only, no email is ever stored.

### Identifiers → not applicable
GeoNap has no user accounts, no advertising identifier usage, no device fingerprinting. Nothing to declare here.

### Usage Data / Diagnostics → not applicable
No analytics SDK, no crash reporter that phones home (`CrashReporter` per `privacy.body.analytics` logs locally only), no third-party tracking of any kind.

### Purchases
Apple's own guidance is that in-app purchase history handled entirely through StoreKit (no third-party payment processor, which GeoNap doesn't use) generally does **not** need to be declared here — Apple already discloses this on your behalf as the platform processing the transaction. Leave this undeclared unless Apple's current questionnaire explicitly asks about StoreKit purchases; if it does, the same "Not Linked to You / App Functionality" answers apply.

---

## What NOT to declare
No Health & Fitness data, no Financial Info, no Browsing History, no Search History, no Sensitive Info, no User Content beyond what's covered above, no Diagnostics.

---

## One nuance worth double-checking yourself in ASC's current wording

Apple's exact phrasing for "linked to you" has shifted across guideline revisions — as of this writing, data that only ever syncs to the *user's own* iCloud account (never a server the developer controls) is broadly treated as not linked to an identity the developer can associate with the user. If ASC's current questionnaire language reads differently when you're filling this out, trust what's in front of you over this doc and adjust accordingly — this guide reflects GeoNap's actual behavior, not a frozen snapshot of Apple's rules.
