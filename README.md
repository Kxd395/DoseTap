# DoseTap (org.axxessphila.dosetap)

Tap once for Dose 1, get reminded **inside 2.5–4 hours** when you're most likely to be naturally surfacing, then tap again for Dose 2.
Logs Bathroom/Out-of-Bed. Uses **Apple Health (sleep)** and **WHOOP** history to place the reminder **within** the label window (never outside 150–240 minutes).

> Safety rails: Dose 2 reminders are **always** clamped to **2.5–4 h** post Dose 1. This app provides reminders/logging only. Follow prescriber instructions.

---

## Hardware & Accounts

- **BLE Button (recommended): Flic 2** → maps Single/Double/Hold to URL scheme.
- **Apple Watch** (sleep stages; haptics).
- **Apple Developer Account** (HealthKit + Notifications entitlements).
- **WHOOP Developer App** (OAuth): scopes `read:sleep read:cycles read:recovery`.

## WHOOP Developer Setup

### 1. Create WHOOP Developer Account

Visit [WHOOP Developer Console](https://developer.whoop.com/) and create an account.

### 2. Register OAuth Application

Fill out the application form with these values:

| Field | Value | Notes |
|-------|-------|-------|
| **Name** | DoseTap | App name displayed in OAuth flow |
| **Logo** | [Upload logo] | .jpg or .png, 1:1 aspect ratio |
| **Contacts** | [kevindial@myyahoo.com](mailto:kevindial@myyahoo.com) | Administrative communications |
| **Privacy Policy** | [https://your-privacy-policy.com](https://your-privacy-policy.com) | Link shown in OAuth flow |
| **Redirect URLs** | `dosetap://oauth/callback` | Custom URL scheme for app callback |
| **Scopes** | `read:sleep read:cycles read:recovery` | Required data access permissions |

### 3. Configure App

After registration, you'll receive a **Client ID**. Add it to your `Config.plist`:

```xml
<key>WHOOP_CLIENT_ID</key>
<string>YOUR_ACTUAL_CLIENT_ID_HERE</string>
```

### 4. Webhooks (Optional)

For real-time updates, add webhook URLs (must be HTTPS):

- `https://your-server.com/webhooks/whoop`

## Identifiers (form-ready)

- App name: **DoseTap**
- Bundle ID: **org.axxessphila.dosetap**
- URL Scheme: **dosetap**
  - `dosetap://log?event=dose1|dose2|bathroom|lightsout|wake_final|snooze`
- WHOOP Redirect: **dosetap://oauth/callback**
- Default second-dose target: **165 minutes** (clamped to **150–240**).

## Build (macOS / Xcode)

- **Xcode 15+**, iOS 17+, watchOS 10+
- Enable **HealthKit** and **UserNotifications** capabilities in Targets → Signing & Capabilities.
- Add the provided `DoseTap.entitlements` and `Info.plist` settings.

### Button wiring (Flic 2)

Map gestures in Flic app → *Open URL*:

- Single: `dosetap://log?event=dose1`
- Double: `dosetap://log?event=dose2`
- Hold: `dosetap://log?event=bathroom` (or **snooze** if in-window)

---

## Project Structure

```
DoseTap/
  ios/DoseTap/
    DoseTapApp.swift
    AppDelegate.swift
    ContentView.swift
    ReminderScheduler.swift
    Health.swift
    RecommendationEngine.swift
    Models/Event.swift
    Storage/Store.swift
    Info.plist
    DoseTap.entitlements
  watchos/DoseTapWatch/
    DoseTapWatchApp.swift
    ContentView.swift
  docs/
    DoseTap_Spec.md
    DoseTap_Spec.rtf
    MindMap.txt
  agent/
    agent_brief.md
    tasks_backlog.md
```

---

## Quick Start

1. Open `DoseTap.xcodeproj` (create a new empty SwiftUI iOS project named "DoseTap", then drop these files in).
2. Add URL type **dosetap** in Info and paste the `CFBundleURLTypes` block from our `Info.plist`.
3. Run on iPhone; press the **Dose 1** button in the app or use Flic to fire `dosetap://log?event=dose1`.
4. Confirm notification permission; a **second-dose reminder** is scheduled for **165 minutes** by default.
5. Log **Dose 2** by double-pressing (or the app button) to clear the reminder.

## Health & WHOOP

- **HealthKit Sleep** is read to compute your **time-to-first-wake (TTFW)** baseline (last 14–30 nights).
- **WHOOP** (optional) provides sleep/cycle *history* for personalization (OAuth). Not used for real-time staging.

## Disclaimers

- This is an assistive logging/reminder tool—not medical advice.
- Keep the Flic app running; do **not** force-quit (it maintains the BLE connection).
