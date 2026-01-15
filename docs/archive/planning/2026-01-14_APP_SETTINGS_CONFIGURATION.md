# DoseTap App Settings Configuration

## Overview
This document describes all the app metadata and settings configured in the Xcode project.

**Last Updated**: January 4, 2026

---

## Core App Identity

### Bundle Information
- **Bundle Identifier**: `com.dosetap.ios`
- **Display Name**: `DoseTap`
- **Product Name**: `DoseTap`
- **Bundle URL Scheme**: `dosetap://`

### Version Information
- **Marketing Version**: `2.0.0`
- **Build Version**: `1`
- **Copyright**: `Copyright © 2026 DoseTap. All rights reserved.`

---

## App Store Metadata

### Category
- **Primary Category**: `Medical` (`public.app-category.medical`)
  - This categorizes the app in the App Store's Medical section
  - Appropriate for XYWAV medication timing and sleep health tracking

### Device Support
- **Target Device Family**: iPhone & iPad (`1,2`)
- **Minimum iOS Version**: iOS 16.0
- **Requires Full Screen**: No (supports multitasking on iPad)

---

## Interface Configuration

### Supported Orientations

#### iPhone
- Portrait (default)
- Landscape Left
- Landscape Right

#### iPad
- Portrait
- Portrait Upside Down
- Landscape Left
- Landscape Right

### UI Appearance
- **Status Bar Style**: Default (light text on dark, dark text on light)
- **Launch Screen**: Auto-generated
- **Scene Manifest**: SwiftUI-based lifecycle

---

## Privacy & Permissions

### Health Data (HealthKit)
**Read Permission** (`NSHealthShareUsageDescription`):
> "DoseTap reads your sleep, heart rate, respiratory rate, oxygen saturation, and HRV to optimize a label-compliant second-dose reminder."

**Write Permission** (`NSHealthUpdateUsageDescription`):
> "DoseTap may write simple log markers if you enable it."

### Bluetooth
**Always Usage** (`NSBluetoothAlwaysUsageDescription`):
> "DoseTap can use Bluetooth if you connect a button directly."

**Peripheral Usage** (`NSBluetoothPeripheralUsageDescription`):
> "DoseTap can use Bluetooth if you connect a button directly."

---

## Security Configuration

### Encryption Export Compliance
- **Uses Non-Exempt Encryption**: `false`
  - App uses standard iOS encryption only
  - No custom cryptography requiring special export compliance
  - Simplifies App Store submission process

### Code Signing
- **Style**: Automatic
- **Development Team**: PJ487S8PS6
- **Entitlements File**: `DoseTap/DoseTap.entitlements`

---

## Build Settings

### Compilation
- **Swift Version**: 5.0
- **SDK**: iOS Simulator / iOS Device
- **Deployment Target**: iOS 16.0
- **Asset Catalog**: AppIcon + AccentColor
- **SwiftUI Previews**: Enabled

### Optimization
- **Debug**: Standard optimization for debugging
- **Release**: Whole module optimization (`-O`)
- **Asset Compilation**: App icons and global accent color

### Framework Dependencies
- **DoseCore**: Local Swift Package (linked)
- **HealthKit**: Apple framework
- **SwiftUI**: Apple framework

---

## URL Schemes

### Deep Linking
The app supports custom URL scheme for deep linking:

```
dosetap://tonight        → Open Tonight tab
dosetap://timeline       → Open Timeline tab
dosetap://insights       → Open Insights tab
dosetap://settings       → Open Settings
```

**Configuration**:
- URL Type Name: `com.dosetap.ios`
- URL Scheme: `dosetap`

---

## App Capabilities

### Enabled Features
✅ HealthKit integration
✅ Background execution (for notifications)
✅ Push notifications (local critical alerts)
✅ Bluetooth peripheral support (optional Flic buttons)
✅ File system access (diagnostics export)
✅ SwiftUI scene-based lifecycle

### Disabled/Not Required
❌ Remote push notifications
❌ iCloud sync (local-only data)
❌ In-app purchases
❌ Game Center
❌ Apple Pay

---

## App Store Submission Checklist

### Required for Submission
- [x] App category set to Medical
- [x] Display name configured
- [x] Version numbers set
- [x] Copyright notice included
- [x] Privacy descriptions for all permissions
- [x] Encryption export compliance declared
- [x] Bundle identifier registered
- [x] Supported devices specified
- [x] Minimum iOS version declared

### Recommended Before Submission
- [ ] App icon assets (all sizes)
- [ ] App Store screenshots (iPhone & iPad)
- [ ] App description and keywords
- [ ] Privacy policy URL
- [ ] Support URL
- [ ] Marketing materials

---

## Settings Screen Display

The app's Settings → About section displays:

```
Version: 2.0.0
Build: 1
```

This information is automatically read from:
- `CFBundleShortVersionString` (Marketing Version)
- `CFBundleVersion` (Current Project Version)

---

## Notes for Developers

### Updating Version Numbers
To update the version:

1. **Marketing Version** (user-facing): Update in Xcode project settings or `MARKETING_VERSION` in `project.pbxproj`
2. **Build Number**: Increment `CURRENT_PROJECT_VERSION` before each TestFlight/App Store submission
3. **Info.plist**: Automatically synced from Xcode project settings

### Bundle Identifier
The bundle ID `com.dosetap.ios` must be registered in your Apple Developer account before submission.

### Development Team
Update `DEVELOPMENT_TEAM` to your own Team ID if building under a different Apple Developer account.

---

## Related Documentation
- [Privacy Policy](../PRIVACY_POLICY.md)
- [Release Checklist](./RELEASE_CHECKLIST.md)
- [TestFlight Guide](./TESTFLIGHT_GUIDE.md)
