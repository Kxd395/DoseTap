# App Icon Troubleshooting Guide

## Problem: App Shows Default/Grid Icon Instead of Logo

If you see a white grid placeholder icon instead of the DoseTap logo on your device/simulator, follow these steps:

---

## ✅ Quick Fix (Most Common Solution)

### Step 1: Clean Build Folder
In Xcode:
- Press **Cmd + Shift + K** (Product → Clean Build Folder)
- Wait for completion

### Step 2: Delete App from Device/Simulator
- Long-press the DoseTap app icon
- Tap "Remove App" → "Delete App"
- This clears the cached icon

### Step 3: Rebuild and Install
- Press **Cmd + R** to build and run
- The app should now show the correct icon

---

## 🔍 Why This Happens

iOS aggressively caches app icons for performance. When you:
1. Install an app without icons initially
2. Later add icon assets
3. Rebuild without cleaning

iOS continues showing the cached placeholder icon even though the asset catalog now has proper icons.

**Solution**: Force iOS to re-register the app icon by deleting and reinstalling.

---

## 🎨 Regenerating Icons from Source

If the icon assets are missing or corrupted, regenerate them from the SVG source:

### Prerequisites
```bash
# Install required tools
brew install librsvg imagemagick
```

### Run Icon Generator
```bash
cd /path/to/DoseTap
./tools/regenerate_app_icons.sh
```

This will:
1. Read the SVG layers from `docs/icon/dosetap-liquid-glass-window/`
2. Composite them into PNGs
3. Generate all 15 required icon sizes
4. Place them in `ios/DoseTap/Assets.xcassets/AppIcon.appiconset/`

---

## 📱 Verification Checklist

After fixing, verify:

- [ ] Icon files exist: `ios/DoseTap/Assets.xcassets/AppIcon.appiconset/*.png`
- [ ] All 15 sizes present (20px → 1024px)
- [ ] Contents.json is valid
- [ ] Build succeeded without asset catalog errors
- [ ] App deleted from device/simulator
- [ ] Fresh install shows correct icon

---

## 🔧 Advanced: Check Asset Catalog

### Verify Icon Files
```bash
ls -lh ios/DoseTap/Assets.xcassets/AppIcon.appiconset/
```

Expected output:
```
icon-1024.png       (81K)  ← App Store icon
icon-20@2x.png      (2K)   ← iPhone notification
icon-20@3x.png      (3K)
icon-29@2x.png      (3K)   ← Settings
icon-29@3x.png      (5K)
icon-40@2x.png      (5K)   ← Spotlight
icon-40@3x.png      (7K)
icon-60@2x.png      (11K)  ← App icon (iPhone)
icon-60@3x.png      (17K)  ← App icon (iPhone Plus/Pro Max)
... (iPad sizes)
```

### Check Contents.json
```bash
cat ios/DoseTap/Assets.xcassets/AppIcon.appiconset/Contents.json
```

Should reference all 15 PNG files correctly.

### Verify Xcode Project Settings
In Xcode → Target → General → App Icons and Launch Screen:
- **App Icon Source**: AppIcon

In Xcode → Build Settings → Search "Asset Catalog":
- **Asset Catalog Compiler - Options**
  - **Asset Catalog App Icon Set Name**: `AppIcon`

---

## 🐛 Still Not Working?

### Reset Simulator Completely
```bash
# Erase all simulators
xcrun simctl erase all

# Or erase specific device
xcrun simctl erase "iPhone 15 Pro"
```

### Clean Derived Data
```bash
rm -rf ~/Library/Developer/Xcode/DerivedData/DoseTap-*
```

### Restart Xcode
Sometimes Xcode needs a restart to recognize asset catalog changes.

### Check Build Logs
In Xcode → Report Navigator (Cmd+9) → Latest Build:
- Look for "Asset Catalog Compiler" step
- Check for warnings/errors about AppIcon.appiconset

---

## 📝 Icon Design Layers

The DoseTap icon uses a **liquid glass** design with 3 SVG layers:

1. **Background** (`-bg.svg`): Solid base layer with gradient
2. **Foreground 2** (`-fg2.svg`): Middle translucent layer (window arc)
3. **Foreground 1** (`-fg1.svg`): Top translucent layer (time indicators)

These are composited together to create the final icon with depth and glass effect.

**Design concept**: A time ring showing the valid XYWAV dose window (150-240 min).

---

## 🎯 Prevention

To avoid this issue in the future:

1. **Always clean build** after modifying asset catalogs
2. **Delete and reinstall** the app after icon changes
3. **Use script** to regenerate icons consistently
4. **Commit icons** to git so team members have them

---

## 📚 Related Files

- Icon source SVGs: `docs/icon/dosetap-liquid-glass-window/`
- Icon assets: `ios/DoseTap/Assets.xcassets/AppIcon.appiconset/`
- Regeneration script: `tools/regenerate_app_icons.sh`
- Design notes: `docs/icon/dosetap-liquid-glass-window/dosetap-liquid-glass-window-notes.md`

---

## 📞 Need Help?

If the icon still doesn't appear after following all steps:

1. Check that icon files are not corrupted: `file icon-60@3x.png`
2. Verify file permissions: `ls -l AppIcon.appiconset/`
3. Try building on a different simulator/device
4. Check Xcode version compatibility (requires Xcode 14+)
