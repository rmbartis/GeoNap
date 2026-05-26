# iCloud Sync Setup — Xcode Steps

All code changes are complete. These are the one-time manual steps required in Xcode and the Apple Developer portal.

---

## 1. Add iCloud capability

1. Select the **GeoAlarm** target → **Signing & Capabilities** tab
2. Click **+ Capability** → add **iCloud**
3. Under Services, tick **CloudKit**
4. Under Containers, click **+** and add: `iCloud.com.rmbartis.GeoAlarm`
5. Make sure the checkbox next to the container is ticked

---

## 2. Add Push Notifications capability

CloudKit sync is delivered via silent push notifications. Without this, sync only
happens when the app is foregrounded.

1. Still on **Signing & Capabilities**
2. Click **+ Capability** → add **Push Notifications**

No configuration needed — just adding the capability is sufficient.

---

## 3. Verify entitlements

Xcode automatically creates/updates `GeoAlarm.entitlements`. It should contain:

```xml
<key>com.apple.developer.icloud-container-identifiers</key>
<array>
    <string>iCloud.com.rmbartis.GeoAlarm</string>
</array>
<key>com.apple.developer.icloud-services</key>
<array>
    <string>CloudKit</string>
</array>
<key>com.apple.developer.ubiquity-kvstore-identifier</key>
<string>$(TeamIdentifierPrefix)com.rmbartis.GeoAlarm</string>
```

---

## 4. Deploy the CloudKit schema (before TestFlight)

The first time you run the app on a real device, SwiftData automatically creates
the CloudKit schema in the **Development** environment. Before sending a TestFlight
build to anyone else, you must promote the schema to **Production**:

1. Open [CloudKit Console](https://icloud.developer.apple.com/dashboard)
2. Select your container `iCloud.com.rmbartis.GeoAlarm`
3. Go to **Schema** → **Deploy Schema to Production**
4. Confirm the deployment

> If you skip this step, TestFlight users will get a CloudKit error and sync won't work.

---

## How sync works

- Alarms created on any device sync to iCloud automatically in the background.
- When another device receives a change, `AlarmManager` reloads and re-registers
  all active regions within seconds.
- If the user is not signed into iCloud or has iCloud disabled, the app falls back
  to local-only storage silently — no error shown to the user.
- The 20-region iOS limit applies per device; each device independently registers
  its own geofences after syncing.

---

## Testing in the simulator

CloudKit sync does not work in the simulator unless you sign in with an Apple ID
in **Settings → Apple ID** inside the simulator. Even then, sync can be slow.
Real devices with the same iCloud account are the reliable way to test.
