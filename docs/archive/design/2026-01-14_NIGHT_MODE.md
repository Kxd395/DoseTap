# Night Mode - Circadian-Friendly Theme System

**Added:** 2026-01-03  
**Version:** 2.13.0  
**Status:** ✅ Production Ready

## Overview

Night Mode is a specialized theme that eliminates all blue light wavelengths from the DoseTap interface, designed specifically for users who need to check or take medications during nighttime hours (particularly middle-of-the-night Dose 2 checks at 2-4 AM).

## Medical Rationale

### The Blue Light Problem

- **Blue light wavelengths** (400-500nm) suppress melatonin production by 50%+ even at low intensities
- **Melatonin suppression** delays sleep onset and reduces sleep quality
- **Peak vulnerability**: 2-4 AM (natural melatonin peak)
- **Critical for narcolepsy patients**: Already dealing with fragmented sleep; blue light exposure during Dose 2 checks can further disrupt remaining sleep

### The Red Light Solution

- **Red/amber light** (>600nm) has minimal circadian impact
- **Maintains readability** with high contrast amber-on-black palette
- **Preserves night vision** adaptation
- **Enables safe medication checks** without disrupting sleep cycle

## Architecture

### Component Structure

```text
ThemeManager (singleton, @MainActor)
    ↓
AppTheme enum { Light, Dark, Night }
    ↓
ContentView (global application)
    ↓
All child views inherit theme
```

### Files

| File | Purpose |
|------|---------|
| `ios/DoseTap/Theme/AppTheme.swift` | Theme enum, color definitions, ThemeManager |
| `ios/DoseTap/Views/ThemeSettingsView.swift` | Theme selection UI |
| `ios/DoseTap/ContentView.swift` | Global theme application point |
| `ios/DoseTap/SettingsView.swift` | Settings menu integration |

## Theme Modes

### 1. Light Mode (Default)

- Standard iOS light appearance
- Blue/teal accent colors (`#34D3C7`)
- White backgrounds
- Black text
- **Use case**: Daytime use, full visibility

### 2. Dark Mode

- Standard iOS dark appearance
- Blue/teal accent colors maintained
- Dark backgrounds
- White text
- **Use case**: Evening use, general low-light

### 3. Night Mode (Red Light)

- **ALL blue wavelengths eliminated**
- Red/amber/orange color palette only
- Deep red-black backgrounds
- Warm amber text
- **Use case**: Middle-of-the-night medication checks (2-4 AM)

## Night Mode Color Palette

### Background Colors

```swift
backgroundColor:        rgb(0.08, 0.0, 0.0)  // Very deep red-black
secondaryBackground:    rgb(0.12, 0.02, 0.0) // Slightly lighter
cardBackground:         rgb(0.15, 0.03, 0.0) // Red-tinted cards
```

### Text Colors

```swift
primaryText:            rgb(1.0, 0.6, 0.4)   // Warm amber
secondaryText:          rgb(0.9, 0.5, 0.3)   // Dimmer amber
```

### Action Colors

```swift
accentColor:            rgb(0.8, 0.2, 0.1)   // Deep red
buttonBackground:       rgb(0.6, 0.15, 0.0)  // Dark red
buttonText:             rgb(1.0, 0.7, 0.5)   // Light amber
```

### Status Colors

```swift
successColor:           rgb(0.9, 0.6, 0.0)   // Amber (replaces green)
warningColor:           rgb(1.0, 0.4, 0.0)   // Deep orange
errorColor:             rgb(0.8, 0.2, 0.0)   // Pure red
```

## Implementation

### Global Application

```swift
// In ContentView.swift
@StateObject private var themeManager = ThemeManager.shared

var body: some View {
    TabView(selection: $selectedTab) {
        // ... tab content
    }
    .preferredColorScheme(themeManager.currentTheme == .night ? .dark : colorScheme)
    .accentColor(themeManager.currentTheme.accentColor)
    .applyNightModeFilter(themeManager.currentTheme)  // Red colorMultiply
}
```

### Red Color Filter

```swift
// In Theme/AppTheme.swift
func applyNightModeFilter(_ theme: AppTheme) -> some View {
    Group {
        if theme == .night {
            self.colorMultiply(Color(red: 1.0, green: 0.4, blue: 0.3))
                .background(theme.backgroundColor.ignoresSafeArea())
        } else {
            self
        }
    }
}
```

### Theme-Aware Components

```swift
// Example: Button colors
private var primaryButtonColor: Color {
    let theme = themeManager.currentTheme
    switch core.currentStatus {
    case .noDose1: return theme == .night ? theme.buttonBackground : .blue
    case .active: return theme == .night ? theme.successColor : .green
    // ...
    }
}
```

## User Flow

### Selection

1. User opens DoseTap
2. Navigates to **Settings** tab (far right)
3. Taps **Theme** row in Appearance section
4. Selects **"Night Mode"** from list
5. Immediately see red filter applied across all screens

### Persistence

- Theme choice saved to `UserDefaults` with key `"selectedTheme"`
- Persists across:
  - App restarts
  - Device reboots
  - iOS updates
- No cloud sync (local preference only)

### Visual Validation

After selecting Night Mode, verify across all 4 tabs:

- ✅ **Tonight**: Red dose buttons, amber text, dark red cards
- ✅ **Timeline**: Red-tinted insight cards, amber metrics
- ✅ **History**: Red calendar highlights, warm date text
- ✅ **Settings**: Red icons, amber toggles, dark red cells

**Zero blue elements should be visible anywhere in the app.**

## Technical Details

### Color Multiplier Approach

The `.colorMultiply()` modifier applies a red filter to ALL view content:

```swift
.colorMultiply(Color(red: 1.0, green: 0.4, blue: 0.3))
```

This effectively:

- Reduces blue channel by 70% (0.3 instead of 1.0)
- Reduces green channel by 60% (0.4 instead of 1.0)
- Maintains red channel at 100% (1.0)

Result: White (#FFFFFF) → Warm amber (~#FF9966)

### Base Dark Mode

Night Mode forces `.preferredColorScheme(.dark)` as a base, then applies the red filter on top. This ensures:

- System UI (status bar, keyboard) uses dark appearance
- SwiftUI semantic colors (`.primary`, `.secondary`) start from dark values
- The red filter shifts dark grays → red-blacks, whites → ambers

## SSOT Contract

### Requirements (MUST)

- ✅ **Eliminate ALL blue wavelengths** - No exceptions, no blue UI elements
- ✅ **Apply globally** - All 4 tabs (Tonight, Timeline, History, Settings)
- ✅ **Persist user choice** - Survives app/device restart
- ✅ **Toggle at any time** - Via Settings → Theme
- ✅ **Maintain Light/Dark** - Original blue accents preserved in non-Night modes

### Validation

- **Visual inspection required** - Automated color detection infeasible
- **Test checklist**:
  1. Enable Night Mode in Settings
  2. Visit all 4 tabs
  3. Verify zero blue elements
  4. Force quit app, reopen
  5. Verify Night Mode persisted
  6. Switch to Light mode
  7. Verify blue accents restored

## Future Enhancements

### Automatic Scheduling

```swift
// Potential future feature
if currentHour >= 22 || currentHour < 6 {
    themeManager.applyTheme(.night)
} else {
    themeManager.applyTheme(.light)
}
```

### Intensity Control

```swift
// Allow user to adjust red filter strength
let filterStrength = 0.7  // 70% red filter
.colorMultiply(Color(red: 1.0, green: 0.4 * filterStrength, blue: 0.3 * filterStrength))
```

### Sunrise/Sunset Integration

```swift
// Auto-enable at sunset, disable at sunrise
import CoreLocation
// Calculate sunset/sunrise based on user location
```

## References

- **SSOT Section**: [Theme System & Night Mode](SSOT/README.md#theme-system--night-mode-circadian-friendly-ui)
- **Navigation Guide**: [SSOT Navigation](SSOT/navigation.md)
- **Research**: [Blue Light and Circadian Rhythms](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC6751071/)

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 2.13.0 | 2026-01-03 | Initial Night Mode implementation |
