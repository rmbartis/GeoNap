// HelpView.swift
// Scrollable help guide covering app concept, use cases, and controls.

import SwiftUI

struct HelpView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {

                helpSection(
                    symbol: "lightbulb",
                    color: .yellow,
                    title: "What is GeoAlarm?",
                    body: """
GeoAlarm wakes you up based on where you are, not what time it is. \
Instead of guessing how long your journey will take, you set an alarm at \
a location and let the app notify you when you arrive — or when you leave.

It runs silently in the background so you can nap, read, or zone out without \
worrying about missing your stop.
"""
                )

                helpSection(
                    symbol: "tram",
                    color: .blue,
                    title: "Typical use cases",
                    body: """
• Train or subway commuter — Set an alarm at your station. Doze off and \
get woken up just before you arrive, every morning, automatically.

• Bus rider — Set a departure alarm at your home stop. The alarm fires \
when you leave the area, reminding you to head out.

• Road trip passenger — Set an alarm at a waypoint city. You'll be notified \
when the car gets close, without watching the map the whole trip.

• Traveller in an unfamiliar city — Set alarms at hotel, airport, or \
meeting locations so you always know when you're getting close.
"""
                )

                helpSection(
                    symbol: "plus.circle",
                    color: .green,
                    title: "Creating an alarm",
                    body: """
Tap + in the top-right corner. A menu appears with two options:

• Location Alarm — pin any address or map location (see below).
• Transit Alarm — pick an agency, route, and stop from live schedules \
(see the Transit Alarms section).

For a Location Alarm:

1. Give the alarm a name (e.g. "Penn Station") and an optional note \
that will appear in the notification.
2. In the Location section, use the search bar to find any address, \
station, or place by name. Suggestions appear as you type — tap one \
to drop a pin and centre the map automatically. You can also tap \
directly on the map to place or reposition the pin manually.
3. Choose On Arrival or On Departure as the trigger.
4. Use the Radius slider to set how close you need to be before the \
alarm fires. A larger radius gives you more warning time.
5. In the Sound / Vibrate section, pick a tone or choose Vibrate only \
(see Alarm sound / vibrate below).

The Save button is disabled until both a name has been entered and a \
location has been pinned on the map. A hint appears in the Location \
section if no pin has been placed yet.

iOS allows a maximum of 20 active alarms at once (an iOS system \
limit on background region monitoring). A warning appears in the \
alarm list as you approach this limit, and the + button is disabled \
when you reach it. Disable an existing alarm to free up a slot.
"""
                )

                helpSection(
                    symbol: "arrow.up.left.and.arrow.down.right",
                    color: .teal,
                    title: "Radius",
                    body: """
The radius defines the geofence — the circular boundary around your pin. \
When you cross that boundary (entering or leaving), the alarm fires.

A 200 m radius is good for a single station or building. Use 500–1000 m \
for broader landmarks like a town centre or airport area, giving yourself \
more time to prepare before arrival.

You can switch between metres/kilometres and feet/miles in Settings.
"""
                )

                helpSection(
                    symbol: "repeat",
                    color: .indigo,
                    title: "Repeat",
                    body: """
One-shot alarms fire once and stay triggered until you manually re-enable them. \
This is useful for a single trip or a one-off reminder.

Repeating alarms automatically reset after you leave the region, so they \
fire again on your next trip through the same location. Perfect for daily commuters.
"""
                )

                helpSection(
                    symbol: "clock",
                    color: .purple,
                    title: "Active time window",
                    body: """
A time window limits when an alarm is allowed to fire. For example, a \
window of 07:00–09:00 means the alarm only triggers during your morning \
commute hours — it ignores the location at all other times.

A summary label below the pickers shows exactly how long the window is \
and what it covers, e.g. "Active 2 hrs · 7:00 AM – 9:00 AM". This \
makes it easy to spot accidental settings before saving.

Overnight windows are supported (e.g. 22:00–06:00). When From is later \
than Until, the alarm is active from the From time through midnight and \
into the next morning until Until. The summary label turns orange and \
shows "next day" as a reminder, e.g. "Active 8 hrs · 10:00 PM → 6:00 AM \
next day".

Guard condition: if the time window closes while you are still inside \
the region, the alarm deactivates automatically so it does not fire \
when the window reopens.
"""
                )

                helpSection(
                    symbol: "tram.fill",
                    color: .teal,
                    title: "Transit Alarms",
                    body: """
Transit Alarms connect to public transit schedules so you can set an alarm \
at an exact station stop — without typing GPS coordinates.

Tap + → Transit Alarm to open the wizard:

1. Agency — Choose from the built-in list of transit agencies worldwide \
(Amtrak, BART, MBTA, CTA, GO Transit, and more), or enter any public \
GTFS feed URL from your local authority.

2. Route — Browse or search the routes operated by that agency. Each \
route shows its type (Rail, Subway, Bus, Ferry, etc.) and the line's \
name or number.

3. Stop — All stops on that route are listed and sorted by distance from \
your current location, so your nearest stop appears at the top. Use the \
search bar to filter by name.

4. Confirm — Review the agency, route, and stop, then set a name, radius, \
trigger direction, sound, and whether to repeat. The Create Alarm button \
is disabled until a name has been entered — a hint appears below the name \
field as a reminder.

The app downloads the GTFS feed the first time you select an agency and \
caches it on your device. Subsequent selections use the local copy \
instantly. If schedules change, re-select the agency to refresh.

GTFS (General Transit Feed Specification) is a worldwide open standard \
used by thousands of transit authorities. The built-in list covers \
popular agencies, but any agency that publishes a public GTFS ZIP \
feed URL can be added via "Enter custom GTFS URL".
"""
                )

                helpSection(
                    symbol: "bell.badge.waveform",
                    color: .pink,
                    title: "Alarm sound / vibrate",
                    body: """
Each alarm has its own sound and vibration setting, chosen in the \
Sound / Vibrate section when creating or editing the alarm.

System options (no extra files required):
• Vibrate only — no audio; the device vibrates silently. Ideal for \
quiet environments. Vibration must be enabled in Settings → Sounds & Haptics.
• Default — the standard iOS notification sound.
• Critical — plays at full volume and bypasses silent mode and \
Do Not Disturb. Use when you cannot afford to miss the alarm.

Travel-themed sounds bundled with the app:
• Boat horn — deep, resonant foghorn. Great for ferry and harbour alarms.
• Cable car bell — the sharp metallic clang of an SF cable car.
• Steam train — a classic three-note steam locomotive whistle chord.
• Sailboat bell — a mellow resonant ship's bell. Good for marina alarms.
• Airplane landing — engine whine descending to a touchdown thud.
• Airport chime — the familiar three-note descending pre-announcement tone.

Each setting is stored with its alarm and plays every time it fires, \
including snooze re-fires. You can change it at any time by editing \
the alarm.

Note: iOS restricts third-party apps to sounds bundled inside the app — \
the full ringtone library in Settings → Sounds & Haptics is only \
available to Apple's own Clock app via a private system entitlement.
"""
                )

                helpSection(
                    symbol: "mic",
                    color: .indigo,
                    title: "Siri & Shortcuts",
                    body: """
GeoAlarm supports Siri and the Shortcuts app — no setup required. \
Once the app is installed, these phrases work out of the box:

• "Create a GeoAlarm" — Siri will ask for a name, location, and \
whether to trigger on arrival or departure. It geocodes the address \
automatically and saves the alarm in the background.

• "Enable my GeoAlarm" — Siri shows a list of your saved alarms. \
Pick one and it is re-enabled immediately.

• "Disable my GeoAlarm" — Same as above, but deactivates the alarm.

You can also find and customise these shortcuts in the iOS Shortcuts \
app under the GeoAlarm section. They can be added to your Home Screen, \
used in Automations, or chained with other actions.
"""
                )

                helpSection(
                    symbol: "gear",
                    color: .gray,
                    title: "Settings",
                    body: """
Open Settings from the gear icon in the top-left corner of the alarm list.

• Distance — switch between metric (metres / kilometres) and imperial \
(feet / miles). Affects how radius is displayed and entered throughout \
the app.
• Clock — switch between 12-hour and 24-hour time. Affects time window \
pickers and labels.
• Help & User Guide — this guide.
• Privacy & Location Sharing — full in-app disclosure of how location \
data, transit feeds, and iCloud sync are handled.
• Build — shows the build timestamp in YYYYMMDD-HHMMSS format (GMT, \
24-hour clock). Useful when reporting a bug or confirming you are \
running the latest version.
"""
                )

                helpSection(
                    symbol: "hand.point.left",
                    color: .cyan,
                    title: "Managing alarms",
                    body: """
Swipe right on any alarm in the list to quickly enable or disable it \
without opening the detail view.

Swipe left to delete an alarm. Deleted alarms are removed immediately \
and their geofence stops being monitored.

To edit an alarm, tap it to open the detail view, then tap Edit Alarm.

To share an alarm location, open the detail view and tap Share location \
in the Actions section. This sends an Apple Maps link to the exact \
coordinates, which the recipient can open in Maps or any navigation app.
"""
                )

                helpSection(
                    symbol: "location.fill",
                    color: .orange,
                    title: "Always On location",
                    body: """
GeoAlarm needs Always On location access to monitor regions in the \
background — even when your screen is locked or the app is closed.

If you chose Not now during setup, you can grant access later in the \
iOS Settings app under Privacy & Security → Location Services → GeoAlarm. \
Set it to Always.

Without Always On access, alarms will only fire while the app is open.
"""
                )

                helpSection(
                    symbol: "bell.badge",
                    color: .red,
                    title: "Notifications",
                    body: """
When an alarm fires you will receive a notification with the alarm name \
and your note (if set). From the notification you can:

• Snooze 10 min — suppresses the alarm for 10 minutes, then re-arms it.
• Dismiss — clears the notification. For repeating alarms, the alarm \
resets once you leave the region.

Make sure notifications are enabled for GeoAlarm in iOS Settings → \
Notifications → GeoAlarm.
"""
                )
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .navigationTitle("Help")
        .navigationBarTitleDisplayMode(.large)
    }

    // MARK: - Section builder

    @ViewBuilder
    private func helpSection(symbol: String, color: Color, title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.title3.bold())
                    .foregroundStyle(color)
                    .frame(width: 28)
                Text(title)
                    .font(.headline)
            }
            Text(body)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview {
    NavigationStack {
        HelpView()
    }
}
