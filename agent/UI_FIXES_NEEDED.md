# UI Fixes Needed - January 20, 2026

## Issues Reported

### 1. Settings Not Persisting ("app setting does not change now")
**Symptoms**: User changes settings but they don't save
**Possible causes**:
- UserSettingsManager bindings not working
- Settings wrapped in NavigationView might be losing state
- @AppStorage not syncing properly

### 2. Missing On-Screen Element ("the on screen is missing")
**Needs clarification**: What specific element is missing?

### 3. Bottom Tab Bar Blocks Sheet Content
**Symptom**: "the bottom fixed nav messes up the side slide because it does not show the bottom of the page slide"
**Location**: `ios/DoseTap/ContentView.swift:439` - `CustomTabBar`
**Issue**: Fixed bottom tab bar overlays sheets/slides, hiding bottom content

## Current Code Structure

```swift
// ContentView.swift line 350-374
ZStack(alignment: .bottom) {
    TabView(selection: $urlRouter.selectedTab) {
        // Tab pages...
    }
    .tabViewStyle(.page(indexDisplayMode: .never))
    .ignoresSafeArea(.container, edges: .bottom)
    
    CustomTabBar(selectedTab: $urlRouter.selectedTab)  // Overlays everything
}
```

## Recommended Fixes

### Fix 1: Move Tab Bar Inside SafeArea for Sheets

**Problem**: Tab bar uses `.ignoresSafeArea()` which makes it overlay sheets
**Solution**: Remove `ignoresSafeArea` from tab bar background, add proper safe area padding

```swift
// CustomTabBar (line 439)
var body: some View {
    HStack(spacing: 0) {
        // ...tabs...
    }
    .padding(.vertical, 8)
    .padding(.bottom)  // Use system safe area inset
    .background(
        Color(.systemBackground)
            .shadow(color: .black.opacity(0.1), radius: 8, y: -4)
            // REMOVE: .ignoresSafeArea()
    )
}
```

### Fix 2: Add Bottom Padding to ScrollViews in Sheets

For any sheet/slide content (like SettingsView), add bottom padding:

```swift
// SettingsView.swift
List {
    // ...sections...
}
.listStyle(.insetGrouped)
.safeAreaInset(edge: .bottom) {
    Color.clear.frame(height: 60)  // Tab bar height
}
```

### Fix 3: Verify UserSettingsManager Bindings

Check that settings are using proper @AppStorage wrappers:

```swift
// UserSettingsManager.swift - verify these patterns
@AppStorage("targetInterval") var targetInterval: Int = 165
@AppStorage("notificationsEnabled") var notificationsEnabled: Bool = true
```

If using custom getters/setters, ensure they call `objectWillChange.send()`:

```swift
var targetInterval: Int {
    get { UserDefaults.standard.integer(forKey: "targetInterval") }
    set { 
        objectWillChange.send()
        UserDefaults.standard.set(newValue, forKey: "targetInterval")
    }
}
```

## Testing Checklist

After fixes:
- [ ] Open Settings tab
- [ ] Change target interval → verify it persists after closing/reopening
- [ ] Change notification toggle → verify it persists
- [ ] Scroll to bottom of Settings list → verify all content visible (not hidden by tab bar)
- [ ] Open Weekly Planner sheet → verify bottom button visible
- [ ] Test on physical iPhone 15 Pro Max (notch device)

## Files to Modify

1. `ios/DoseTap/ContentView.swift` - CustomTabBar (line 439-478)
2. `ios/DoseTap/SettingsView.swift` - Add bottom safe area inset
3. `ios/DoseTap/UserSettingsManager.swift` - Verify bindings (if needed)

## Priority

- **P0**: Tab bar overlay fix (blocks usability)
- **P1**: Settings persistence (data loss)
- **P2**: Missing element (need clarification)
