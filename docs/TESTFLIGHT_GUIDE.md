# TestFlight Distribution Guide

TestFlight allows you to install DoseTap on up to 100 devices for 90 days of testing.

## Prerequisites

1. **Apple Developer Account** ($99/year)
   - Sign up at: https://developer.apple.com/programs/

2. **App Store Connect Access**
   - Create your app listing at: https://appstoreconnect.apple.com/

## Steps to Distribute via TestFlight

### 1. Configure Code Signing

```bash
cd /Users/VScode_Projects/projects/DoseTap/ios

# Open Xcode and configure signing
open DoseTap.xcodeproj

# In Xcode:
# - Select the DoseTap project
# - Go to "Signing & Capabilities"
# - Check "Automatically manage signing"
# - Select your Team from dropdown
# - Xcode will create/download the necessary certificates
```

### 2. Archive the App

```bash
# Clean and archive
xcodebuild clean archive \
  -project DoseTap.xcodeproj \
  -scheme DoseTap \
  -archivePath ~/Desktop/DoseTap.xcarchive \
  -destination "generic/platform=iOS" \
  CODE_SIGN_STYLE=Automatic \
  -allowProvisioningUpdates
```

### 3. Export for TestFlight

```bash
# Create export options plist
cat > /tmp/ExportOptions.plist << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>app-store</string>
    <key>uploadSymbols</key>
    <true/>
    <key>uploadBitcode</key>
    <false/>
</dict>
</plist>
EOF

# Export IPA
xcodebuild -exportArchive \
  -archivePath ~/Desktop/DoseTap.xcarchive \
  -exportPath ~/Desktop/DoseTap_Export \
  -exportOptionsPlist /tmp/ExportOptions.plist
```

### 4. Upload to App Store Connect

**Option A: Using Xcode**
```bash
# Open the archive in Xcode
open ~/Desktop/DoseTap.xcarchive

# Then click "Distribute App" > "TestFlight & App Store" > "Upload"
```

**Option B: Using Command Line**
```bash
xcrun altool --upload-app \
  --type ios \
  --file ~/Desktop/DoseTap_Export/DoseTap.ipa \
  --username "your-apple-id@email.com" \
  --password "your-app-specific-password"
```

### 5. Configure TestFlight

1. Go to [App Store Connect](https://appstoreconnect.apple.com/)
2. Select your app
3. Go to "TestFlight" tab
4. Wait for processing (10-30 minutes)
5. Add internal testers (up to 100)
6. Share the TestFlight link

### 6. Install on Test Devices

Testers will:
1. Install TestFlight app from App Store
2. Click the TestFlight invite link
3. Install DoseTap
4. App will auto-update when you upload new builds

## Benefits of TestFlight

- ✅ Install on 100+ devices
- ✅ 90-day testing window per build
- ✅ Automatic updates
- ✅ Crash reports and analytics
- ✅ Beta feedback collection
- ✅ No cable required
- ✅ Works like a "real" App Store app

## Alternative: Ad Hoc Distribution

For <100 devices without TestFlight ($99/year not needed if you already have devices registered):

1. Register device UDIDs in Apple Developer Portal
2. Create Ad Hoc provisioning profile
3. Export IPA with Ad Hoc profile
4. Distribute via direct download or services like Diawi

See: `tools/adhoc_distribution.sh` for automation
