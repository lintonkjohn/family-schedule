# Family Schedule (iOS, SwiftUI)

Dashboard + alerts + "Next Up" widget. Runs on your own iPhone with a free Apple ID.

## Run it

```bash
brew install xcodegen          # one time
cd ~/familySchedule
xcodegen                       # creates FamilySchedule.xcodeproj
open FamilySchedule.xcodeproj
```

In Xcode:
1. Select the **FamilySchedule** target → Signing & Capabilities → Team: *your Apple ID (Personal Team)*.
2. Do the same for **NextUpWidgetExtension**.
3. Plug in your iPhone, pick it as the run destination, press **Run** (⌘R).
4. First time on the phone: Settings → Privacy & Security → **Developer Mode** → On (restart), then
   Settings → General → VPN & Device Management → trust your developer certificate.
5. Allow notifications when the app asks. Alerts tab → **Send test alert** to confirm.
6. Long-press Home Screen → **+** → Family Schedule → add the *Next Up* widget (also works on the Lock Screen).

Free Apple ID: the app expires after 7 days — plug in and press Run again (data is kept).

If the bundle ID or App Group is reported as unavailable, change `com.linton.familyschedule`
and `group.com.linton.familyschedule` in `project.yml` and `SharedStore.swift`, then run `xcodegen` again.

## Files

| File | Target | Purpose |
|---|---|---|
| `FamilySchedule/Shared/Models.swift` | App + Widget | Member, Activity, AlertRule (SwiftData) |
| `FamilySchedule/Shared/Planner.swift` | App + Widget | Recurrence expansion, conflicts, alert planning |
| `FamilySchedule/Shared/SharedStore.swift` | App + Widget | App Group store, per-alert mutes, hex colors |
| `FamilySchedule/SeedData.swift` | App | Levin's schedule (edit here) |
| `FamilySchedule/NotificationScheduler.swift` | App | Schedules next 14 days of local alerts (max 60) |
| `FamilySchedule/DashboardView.swift` | App | Next up, leave-by, conflicts, 7-day list |
| `FamilySchedule/AlertsView.swift` | App | Upcoming alerts (mute per occurrence), rules, test |
| `NextUpWidget/*` | Widget | Home/Lock Screen widget |

## Changing the schedule
Edit `SeedData.swift`, delete the app from the phone, Run again. (An edit screen is the next iteration.)

Notes: Piano is stored in `Asia/Kolkata`, so it shows Thursday evening in California and shifts
correctly when daylight saving ends. Drive times (Robolabs 20 min, others 15) are placeholders.
