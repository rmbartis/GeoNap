# Apple Watch Setup — Xcode Steps

These are one-time manual steps in Xcode required to compile and run the Watch app and complication. All Swift source files are already written.

---

## 1. Add the Watch App target

1. In Xcode, go to **File → New → Target…**
2. Select the **watchOS** tab, choose **Watch App**, click **Next**
3. Set:
   - Product Name: `GeoAlarmWatch`
   - Bundle Identifier: `com.rmbartis.GeoAlarm.watchkitapp`
   - Team: your Apple Developer account
   - Organization Identifier: `com.rmbartis`
   - **Uncheck** "Include Notification Scene" (not needed)
4. Click **Finish** — Xcode will ask to activate the scheme; click **Activate**

---

## 2. Add the Watch Widget Extension target

1. **File → New → Target…**
2. Select **watchOS** tab, choose **Widget Extension**, click **Next**
3. Set:
   - Product Name: `GeoAlarmWatchWidget`
   - Bundle Identifier: `com.rmbartis.GeoAlarm.watchkitapp.widget`
   - **Uncheck** "Include Configuration App Intent"
4. Click **Finish**

---

## 3. Add source files to the correct targets

### GeoAlarmWatch target — add these files:
- `GeoAlarmWatch/GeoAlarmWatchApp.swift`
- `GeoAlarmWatch/WatchAlarmStore.swift`
- `GeoAlarmWatch/NearestAlarmView.swift`
- `GeoAlarm/Models/WatchAlarmPayload.swift` ← also add to this target

### GeoAlarmWatchWidget target — add these files:
- `GeoAlarmWatchWidget/GeoAlarmComplication.swift`
- `GeoAlarm/Models/WatchAlarmPayload.swift` ← also add to this target

To add an existing file to a target: select the file in the Project Navigator →
open the File Inspector (right panel) → check the target under **Target Membership**.

### GeoAlarm (iOS) target — already added automatically:
- `GeoAlarm/Services/WatchConnectivityManager.swift`
- `GeoAlarm/Models/WatchAlarmPayload.swift`

---

## 4. Enable App Groups capability (required for data sharing)

The Watch app and the complication extension run in separate processes. They share
alarm data through an App Group container. You must enable this on **all three targets**.

### For each of: GeoAlarm, GeoAlarmWatch, GeoAlarmWatchWidget:
1. Select the target in Xcode → **Signing & Capabilities** tab
2. Click **+ Capability** → add **App Groups**
3. Click **+** and add the group: `group.com.rmbartis.GeoAlarm`
4. Make sure the checkbox next to the group is ticked

> The group name must be identical across all three targets.

---

## 5. Add WatchConnectivity framework to the iOS target

1. Select the **GeoAlarm** iOS target → **General** tab
2. Scroll to **Frameworks, Libraries, and Embedded Content**
3. Click **+** → search for `WatchConnectivity` → click **Add**

The Watch targets automatically link WatchConnectivity and WidgetKit.

---

## 6. Build and test

Since you don't have a physical Apple Watch:

- Use the **watchOS Simulator**: in Xcode, pair a Watch simulator to the iPhone
  simulator via **Window → Devices and Simulators**
- Run the **GeoAlarmWatch** scheme on the Watch simulator
- Use the **Test Fire** button on the iOS sim to trigger an alarm; the Watch
  simulator should receive the applicationContext update within a few seconds
- To preview complications without running: open `GeoAlarmComplication.swift`
  and use the **#Preview** canvas at the bottom of the file

---

## How data flows

```
iPhone AlarmManager
  └─ save() → WatchConnectivityManager.updateWatch()
       └─ WCSession.updateApplicationContext(["watchAlarms": Data])
            └─ Watch WatchAlarmStore.session(_:didReceiveApplicationContext:)
                 ├─ Persists to UserDefaults(suiteName: "group.com.rmbartis.GeoAlarm")
                 ├─ Updates @Published alarms → NearestAlarmView refreshes
                 └─ WidgetCenter.reloadAllTimelines() → Complication refreshes
                      └─ AlarmProvider reads same UserDefaults group
```
