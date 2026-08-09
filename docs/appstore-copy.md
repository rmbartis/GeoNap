<!-- Copyright © 2026 Robert Bartis. All rights reserved. -->

# GeoNap — App Store Connect Copy

## App Name
GeoNap

## Subtitle (30 characters max)
Wake Up at the Right Stop

## Description (4,000 characters max)

Never miss your stop again.

GeoNap lets you set alarms based on location — not time. Whether you're napping on a train, dozing on a bus, or just need to wake up when you reach a destination, GeoNap monitors your position in the background and alerts you the moment you arrive.

**How it works**
Set an alarm by dropping a pin on the map or entering coordinates manually. Choose an alarm radius — from a few hundred metres to several kilometres — and GeoNap will notify you as soon as you enter that zone, even if your phone is locked or the app is closed.

**Built for travelers**
- Works on trains, buses, subways, ferries, and road trips
- Background location monitoring keeps working while you sleep
- No need to watch a map or stay awake until your stop

**Transit schedule integration**
Browse curated GTFS transit feeds for major rail and bus networks worldwide, or enter any public GTFS feed URL for an agency of your choosing. Import stop locations directly from schedules to set alarms with precision.

**Plans & Pricing**
GeoNap is free to download and use, with optional paid tiers that unlock more:

- **Free** — 1 active alarm, distance-based triggers, and system alert sounds.
- **Silver ($2.99/year)** — Unlimited active alarms, Auto-Notify contacts by text when you arrive, a full library of custom alarm sounds, and scheduling within a set active time window.
- **Gold ($6.99/year)** — Everything in Silver, plus Transit Alarms with live agency/route/stop schedules, a "time before arrival" trigger mode, repeating alarms with hysteresis, and hands-free Auto-SMS automation.
- **Platinum ($12.99, one-time purchase)** — Everything in Gold, plus running a Shortcuts automation when an alarm fires, Live Activity / Dynamic Island support, Calendar Scanning to automatically suggest alarms for upcoming trips, and Dead Reckoning to keep time-based alarms accurate through brief GPS gaps.

Silver and Gold are auto-renewing annual subscriptions billed to your Apple ID; manage or cancel anytime in your device's Subscription settings. Platinum is a one-time purchase with Family Sharing included. Prices shown in USD and may vary by region. See Terms of Use and Privacy Policy for full details.

**Fully localized**
GeoNap is available in 13 languages: English, Spanish, French, German, Italian, Portuguese, Arabic, Hindi, Japanese, Simplified Chinese, Russian, Thai, and Vietnamese — with an in-app language switcher independent of your system settings.

**Customizable**
- Choose metric or imperial distance units
- Display coordinates in Decimal Degrees (DD), Degrees Minutes Seconds (DMS), or Degrees Decimal Minutes (DDM)
- Pick from multiple alarm sounds including Train Horn, Airport Chime, Boat Horn, and more
- 12-hour or 24-hour clock display
- Optional critical alerts that sound even in Silent mode

**Privacy first**
Your location never leaves your device. GeoNap processes everything locally — no account required, no location data sent to servers, no advertising.

---

## Keywords (100 characters max, comma-separated)
alarm,location,travel,train,bus,transit,stop,nap,sleep,commute,GTFS,arrival,reminder,navigator

---

## Support URL
https://mba-labs.com/products/geonap/#pv-sec-support

## Privacy Policy URL
https://mba-labs.com/products/geonap/#pv-sec-privacy

## Copyright
© 2026 Robert Bartis

---

## TestFlight Beta App Description (shown to testers in TestFlight app)

GeoNap is a location-based alarm app for travelers. Set an alarm for any map location and the app will alert you when you arrive — ideal for napping on trains, buses, or during road trips.

This beta includes: map-based alarm creation, manual coordinate entry, transit feed browsing (GTFS), 13-language support with in-app language switching, multiple alarm sounds, and Apple Watch support.

Please test: setting alarms in different location formats (DD/DMS/DDM), switching languages, and triggering alarms by walking or driving toward a set location.

---

## App Review Notes (for the production submission reviewer — distinct from the Beta Review Notes below, which are for TestFlight)

GeoNap offers 4 tiers — Free, Silver ($2.99/year), Gold ($6.99/year), and Platinum ($12.99 one-time). No login or account is required; every tier is reachable immediately from a fresh install.

**To review a paid tier's features:** open the app → tap the gear icon (Settings) → See Plans, or tap the lock badge next to any greyed-out feature — both open the in-app paywall. Select a plan and complete the purchase with your Sandbox tester account. Silver and Gold are auto-renewable annual subscriptions; Platinum is a one-time non-consumable purchase. The corresponding feature unlocks immediately after the purchase completes — no relaunch needed. A "Restore Purchases" button is on the paywall, and "Manage Subscription" is in Settings, per Guideline 3.1.2.

Locked features stay visible rather than hidden, disabled with a lock badge naming the tier required (e.g. "Gold") — tapping the badge itself also opens the paywall directly.

**What each tier unlocks**, for reference while testing:
- **Free** — 1 active alarm, distance-radius trigger only, system alert sounds.
- **Silver** — Unlimited active alarms, Auto-Notify (SMS to saved contacts on arrival), the full custom sound library, active time-window scheduling.
- **Gold** — Everything in Silver, plus Transit Alarms (GTFS agency/route/stop), time-before-arrival trigger mode, Repeat mode with hysteresis, hands-free Auto-SMS automation, custom transit feed cache duration.
- **Platinum** — Everything in Gold, plus Run Shortcut on Alarm, Live Activity/Dynamic Island, Calendar Scanning, and Dead Reckoning on signal loss.

**Permissions required:** Location (Always) for background region monitoring, Notifications for alarm delivery. Calendar and Contacts access are both optional and only requested if the reviewer turns on Calendar Scanning (Settings) or picks a contact for Auto-Notify — neither is required to evaluate the core app.

---

## Beta Review Notes (for Apple's TestFlight reviewer)

GeoNap is a location-based alarm app. Core function: user sets a geographic alarm by dropping a map pin or entering coordinates; app sends a local notification when the user enters the alarm radius.

**To test the main feature:**
1. Launch the app and tap + to create a new alarm
2. Drop a pin on the map or enter coordinates manually
3. Set a radius and save
4. Adjust all options associated with alarm creation and alarms using a variety of settings.

**Permissions required:**
- Location (Always) — needed for background region monitoring
- Notifications — needed for alarm delivery

No login or account is required. All features are accessible immediately on launch.

**Transit feed feature:** Tapping the globe icon browses public GTFS feeds and requires network access. No authentication needed.
