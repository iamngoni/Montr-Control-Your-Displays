# Montr — Control Your Displays

## Product Specification v0.2

### Overview

Montr is a macOS menu bar application for managing display brightness and color temperature. It provides quick access to brightness control, Night Shift-style color temperature adjustments, and display profiles—all without navigating through System Preferences.

---

## Product Vision

**Mission:** Give users complete control over their display experience with a beautiful, native-feeling interface.

**Target Users:**
- Casual users who want simple brightness control
- Power users who want granular per-display settings
- Professionals who need precise color temperature management

The UI adapts to user needs—simple by default, powerful when needed.

---

## Target Platform

- **macOS:** 14.0+ (Sonoma and later)
- **Architecture:** Universal (Apple Silicon + Intel)
- **Distribution:** Direct download (required for full DDC/CI hardware access)
- **Price:** Free with optional donation

---

## Core Features

### 1. Menu Bar Integration

The app lives exclusively in the menu bar (no dock icon).

**Behavior:**
- Persistent menu bar icon (minimal/monochrome, fits macOS style)
- Click to reveal popover with display controls
- Right-click for quick actions menu
- Option-click to quit

**Icon States:**
- Default: Monitor icon (monochrome)
- Night Shift active: Warm-tinted icon
- Quick dim active: Dimmed icon
- No external displays: Standard icon (built-in still controllable)

---

### 2. Display Detection & Management

Automatically detect and enumerate all connected displays.

**Supported Displays:**
- Built-in display (MacBook/iMac screen)
- External monitors (HDMI, DisplayPort, USB-C, Thunderbolt)
- Real-time detection of connect/disconnect events

**Display Metadata:**
- Manufacturer name/model
- Custom user-defined name (shown alongside original)
- Resolution (native & current)
- Connection type
- DDC/CI support status (hardware vs software brightness indicator)

**Display Naming:**
- Users can assign custom names (e.g., "Left Monitor", "Main Display")
- UI shows: "Custom Name" with original name in smaller text below
- Names persist across reconnections (matched by display identifier)

---

### 3. Brightness Control

Control brightness for each display independently.

**Features:**
- Per-display slider (0-100%)
- Quick presets: 25%, 50%, 75%, 100%
- Sync brightness across all displays (optional toggle)
- **Quick Dim:** One-click dim all displays to customizable percentage
- Native macOS-style HUD overlay when adjusting

**Technical Implementation:**
- **DDC/CI** (primary): Hardware brightness via I2C for external monitors
- **CoreDisplay API**: Built-in display brightness
- **Gamma fallback**: Software brightness for non-DDC displays (clearly labeled in UI)

**Quick Dim Feature:**
- Configurable target percentage (default: 20%)
- Toggle button in popover header
- Keyboard shortcut support
- Restores previous brightness on second click

---

### 4. Contrast Control (Advanced)

Available in advanced settings for power users.

**Features:**
- Per-display contrast slider (0-100%)
- Only shown for DDC/CI compatible displays
- Hidden by default, enabled in Settings > Advanced

---

### 5. Night Shift / Color Temperature

Control color temperature to reduce blue light. Works alongside (additive to) macOS Night Shift.

**Features:**
- **Color temperature wheel/spectrum** visualization
- Temperature slider with Kelvin readout (2700K - 6500K)
- **Per-display control** (each display can have different temperature)
- Presets:
  - Off (6500K - native daylight)
  - Warm (4000K)
  - Warmer (3400K)
  - Candlelight (2700K)
  - Custom temperature

**Schedule Options:**
- Manual on/off
- Sunset to Sunrise (location-based)
- Custom schedule (start/end times)
- Gradual transition (fade over configurable minutes)

**macOS Night Shift Coexistence:**
- Montr's adjustments are additive to system Night Shift
- UI indicator when system Night Shift is also active
- Tooltip explaining the combined effect

---

### 6. Display Profiles

Save and restore complete display configurations.

**Profile Contents:**
- Brightness level per display
- Contrast level per display (if enabled)
- Color temperature per display
- Quick dim state

**Features:**
- Create named profiles (e.g., "Work", "Movie", "Night", "Presentation")
- Quick switch from popover (profile pills/buttons)
- Import/Export profiles (JSON format)

**Auto-Activation Triggers (Essential Feature):**
- **Connected displays:** Activate profile when specific monitor(s) connected
  - e.g., "Work" profile when Dell monitor detected
- **Time of day:** Schedule-based activation
- **Power source:** Different profiles for battery vs. plugged in

**Profile Matching Logic:**
- Display matching by identifier (survives port changes)
- Graceful handling when profile display not connected

---

### 7. On Quit Behavior

When Montr quits:
- **Restore original settings:** Brightness and gamma return to pre-Montr state
- Ensures no permanent changes if user uninstalls
- Configurable in Settings (default: restore)

---

## User Interface

### Menu Bar Popover (Detailed Mode)

```
┌───────────────────────────────────────────┐
│  Montr                    [☀︎ Quick Dim] [⚙] │
├───────────────────────────────────────────┤
│                                           │
│  Built-in Retina Display                  │
│  MacBook Pro 14"                          │
│  ☀ ━━━━━━━━━━●━━━━━━━━━━━━ 75%           │
│                                           │
│  Work Monitor                    [DDC/CI] │
│  Dell U2722D                              │
│  ☀ ━━━━━━━━━━━━━━━●━━━━━━━ 85%           │
│                                           │
│  Left Display                   [Software]│
│  LG 27UK850                               │
│  ☀ ━━━━━━━━●━━━━━━━━━━━━━━ 60%           │
│                                           │
├───────────────────────────────────────────┤
│  Night Shift                              │
│  ┌─────────────────────────────────────┐  │
│  │     [Color Temperature Wheel]       │  │
│  │         🔵 ━━━━ 🟡 ━━━━ 🟠          │  │
│  └─────────────────────────────────────┘  │
│  🌡 4000K                    ⏰ Sunset→   │
├───────────────────────────────────────────┤
│  Profiles                                 │
│  [Work] [Movie] [Night] [+]              │
└───────────────────────────────────────────┘
```

**UI Elements:**
- Per-display brightness sliders with percentage
- DDC/CI vs Software badge per display
- Color temperature wheel with warm-cool spectrum
- Profile quick-switch buttons
- Quick dim toggle in header
- Settings gear icon

### Settings Window

**Tabs:**

1. **General**
   - Launch at login
   - Show in menu bar (always on for menu bar app)
   - Check for updates (Sparkle)
   - Restore settings on quit (toggle)
   - Quick dim percentage (slider, default 20%)

2. **Displays**
   - List of known displays
   - Custom naming per display
   - DDC/CI enable/disable per display
   - Software brightness fallback toggle

3. **Night Shift**
   - Schedule configuration
   - Transition duration (minutes)
   - Per-display or all-displays mode
   - Color temperature range limits

4. **Profiles**
   - List/manage saved profiles
   - Auto-activation rules editor
   - Import/Export buttons

5. **Shortcuts**
   - Global keyboard shortcuts (nice to have)
   - Customizable hotkey bindings

6. **Advanced**
   - Enable contrast control
   - DDC/CI retry settings
   - Debug logging toggle
   - Reset all settings

---

## Keyboard Shortcuts (Nice to Have)

| Action | Default Shortcut |
|--------|------------------|
| Open Montr | `⌥⌘M` |
| Toggle Quick Dim | `⌥⌘D` |
| Brightness Up (all) | `⌥⌘↑` |
| Brightness Down (all) | `⌥⌘↓` |
| Toggle Night Shift | `⌥⌘N` |
| Next Profile | `⌥⌘P` |

---

## Technical Architecture

### Frameworks

| Framework | Purpose |
|-----------|---------|
| SwiftUI | UI components, popover content |
| AppKit | Menu bar (NSStatusItem), NSPopover, windows |
| CoreGraphics | Display enumeration, gamma tables |
| IOKit | DDC/CI communication over I2C |
| CoreLocation | Sunrise/sunset calculation |
| Sparkle | Auto-updates |
| Sentry | Crash reporting |

### Architecture Diagram

```
┌──────────────────────────────────────────────────┐
│                    App Layer                      │
├──────────────────────────────────────────────────┤
│  MontrApp (entry point)                          │
│  AppDelegate (NSApplicationDelegate)             │
│  MenuBarController (NSStatusItem + NSPopover)    │
│  SettingsWindowController                        │
└──────────────────────────────────────────────────┘
                        │
┌──────────────────────────────────────────────────┐
│                  View Layer                       │
├──────────────────────────────────────────────────┤
│  PopoverContentView (main UI)                    │
│  DisplayRowView (per-display controls)           │
│  ColorTemperatureWheelView (spectrum picker)     │
│  ProfilesBarView (profile buttons)               │
│  SettingsView (settings tabs)                    │
│  BrightnessHUDView (overlay)                     │
└──────────────────────────────────────────────────┘
                        │
┌──────────────────────────────────────────────────┐
│                 Service Layer                     │
├──────────────────────────────────────────────────┤
│  DisplayManager                                  │
│    - Enumerate displays (CGGetActiveDisplayList) │
│    - Monitor connect/disconnect events           │
│    - Display metadata and capabilities           │
│                                                  │
│  BrightnessController                            │
│    - Coordinate DDC vs gamma brightness          │
│    - Built-in display via CoreDisplay            │
│    - Track original values for restore           │
│                                                  │
│  DDCService                                      │
│    - IOKit I2C communication                     │
│    - VCP code read/write (0x10 brightness, etc.) │
│    - Capability detection                        │
│                                                  │
│  GammaBrightnessService                          │
│    - CGSetDisplayTransferByTable                 │
│    - Software brightness fallback                │
│                                                  │
│  ColorTemperatureController                      │
│    - Gamma table manipulation for color temp     │
│    - Kelvin to RGB conversion                    │
│    - Schedule management                         │
│                                                  │
│  SunriseSunsetService                            │
│    - CoreLocation for coordinates                │
│    - Solar calculation algorithms                │
│                                                  │
│  ProfileManager                                  │
│    - CRUD operations for profiles                │
│    - Auto-activation trigger evaluation          │
│    - Import/export functionality                 │
│                                                  │
│  HotkeyManager                                   │
│    - Global shortcut registration                │
│    - Carbon Events / CGEventTap                  │
│                                                  │
│  SettingsManager                                 │
│    - UserDefaults wrapper                        │
│    - Original values storage for restore         │
└──────────────────────────────────────────────────┘
                        │
┌──────────────────────────────────────────────────┐
│                  Data Layer                       │
├──────────────────────────────────────────────────┤
│  Models:                                         │
│    - Display (id, name, customName, type, caps)  │
│    - DisplaySettings (brightness, contrast, temp)│
│    - Profile (name, displaySettings, triggers)   │
│    - NightShiftSchedule (mode, times)            │
│    - AutoActivationTrigger (type, conditions)    │
│                                                  │
│  Persistence:                                    │
│    - UserDefaults (settings, profiles)           │
│    - Codable for serialization                   │
└──────────────────────────────────────────────────┘
```

### DDC/CI Communication

For hardware brightness control on external monitors:

```swift
// Conceptual flow
1. Get IOFramebuffer service for display
2. Find I2C interface
3. Send DDC command with VCP code
4. Read/write values

// Supported VCP Codes
0x10 - Brightness (primary)
0x12 - Contrast (advanced)
0x14 - Color preset
0xD6 - Power mode
```

**DDC Compatibility:**
- Most Dell, LG, Samsung, ASUS monitors support DDC/CI
- Apple displays (Studio Display, Pro Display XDR) use proprietary protocols
- Some monitors require DDC to be enabled in OSD settings

---

## Localization

**Full localization from v1.0:**

| Language | Priority |
|----------|----------|
| English | Primary |
| Spanish | High |
| French | High |
| German | High |
| Chinese (Simplified) | High |
| Japanese | Medium |
| Korean | Medium |
| Portuguese | Medium |
| Italian | Medium |
| Dutch | Low |
| Russian | Low |

**Localization Approach:**
- All UI strings in Localizable.strings
- Pluralization rules for counts
- RTL support preparation
- Number/date formatting via locale

---

## Analytics & Crash Reporting

**Sentry Integration:**
- Crash reports with stack traces
- Breadcrumbs for user actions leading to crash
- Release tracking
- No PII collection
- User consent on first launch (opt-out available)

**No analytics/telemetry beyond crash reporting.**

---

## Auto-Updates

**Sparkle Framework:**
- Check for updates on launch (configurable)
- Background update checks
- User notification for available updates
- Automatic download, manual install trigger
- Signed updates (EdDSA)
- Appcast XML feed

---

## Permissions & Entitlements

### Required Permissions

| Permission | Purpose | User Prompt |
|------------|---------|-------------|
| Location | Sunrise/sunset calculation | "Montr uses your location to calculate sunrise and sunset times for automatic Night Shift scheduling." |
| Accessibility (optional) | Global keyboard shortcuts | "Montr needs accessibility access to use global keyboard shortcuts." |

### Entitlements (Non-Sandboxed)

```xml
<!-- Direct download, not sandboxed for DDC/CI access -->
<key>com.apple.security.app-sandbox</key>
<false/>

<key>com.apple.security.automation.apple-events</key>
<true/>
```

**Note:** DDC/CI requires non-sandboxed access to IOKit. This is why we chose direct download over Mac App Store.

---

## Data Persistence

### UserDefaults Keys

| Key | Type | Description |
|-----|------|-------------|
| `launchAtLogin` | Bool | Auto-start on login |
| `restoreOnQuit` | Bool | Restore original settings on quit |
| `quickDimPercentage` | Int | Quick dim target (default: 20) |
| `displayCustomNames` | [String: String] | Display ID → custom name |
| `perDisplayBrightness` | [String: Int] | Display ID → brightness |
| `nightShiftEnabled` | Bool | Global Night Shift state |
| `nightShiftTemperature` | Float | Color temp in Kelvin |
| `nightShiftPerDisplay` | [String: Float] | Display ID → temperature |
| `nightShiftSchedule` | Data | Encoded schedule |
| `profiles` | Data | Encoded profile array |
| `activeProfileID` | String? | Current profile UUID |
| `shortcuts` | Data | Keyboard shortcut config |
| `contrastEnabled` | Bool | Show contrast controls |
| `originalDisplaySettings` | Data | Pre-Montr values for restore |
| `sentryEnabled` | Bool | Crash reporting consent |

---

## Edge Cases & Error Handling

### Display Disconnect
- Gracefully remove from UI immediately
- Preserve settings for reconnection (matched by ID)
- Profile auto-activation re-evaluated
- Optional notification (configurable)

### DDC/CI Failure
- Detect unsupported displays on first attempt
- Cache capability per display
- Fall back to software brightness automatically
- Show "Software" badge in UI
- Retry DDC periodically (display firmware can be slow)

### Multiple Identical Displays
- Differentiate by connection port/position
- Allow user-defined names to distinguish
- Stable ordering in UI

### System Night Shift Conflict
- Detect when macOS Night Shift is active
- Show indicator in UI
- Effects are additive (both applied)
- Tooltip explains combined behavior

### App Crash Recovery
- Sentry captures crash with context
- On next launch, offer to restore previous settings
- Log rotation to prevent disk fill

### Sleep/Wake
- Re-enumerate displays on wake
- Restore DDC connection (may require delay)
- Re-apply settings if "restore on quit" is off

---

## Success Metrics

| Metric | Target |
|--------|--------|
| App launch time | < 500ms |
| Brightness adjustment latency | < 100ms |
| DDC command round-trip | < 200ms |
| Memory usage at idle | < 50MB |
| CPU usage at idle | < 1% |
| Battery impact | Negligible |
| Crash-free sessions | > 99.5% |

---

## File Structure

```
Montr/
├── Sources/
│   ├── App/
│   │   ├── MontrApp.swift
│   │   ├── AppDelegate.swift
│   │   └── MenuBarController.swift
│   ├── Models/
│   │   ├── Display.swift
│   │   ├── DisplaySettings.swift
│   │   ├── Profile.swift
│   │   ├── NightShiftSchedule.swift
│   │   └── AutoActivationTrigger.swift
│   ├── Services/
│   │   ├── DisplayManager.swift
│   │   ├── BrightnessController.swift
│   │   ├── DDCService.swift
│   │   ├── GammaBrightnessService.swift
│   │   ├── ColorTemperatureController.swift
│   │   ├── SunriseSunsetService.swift
│   │   ├── ProfileManager.swift
│   │   ├── HotkeyManager.swift
│   │   └── SettingsManager.swift
│   ├── Views/
│   │   ├── PopoverContentView.swift
│   │   ├── DisplayRowView.swift
│   │   ├── ColorTemperatureWheelView.swift
│   │   ├── ProfilesBarView.swift
│   │   ├── BrightnessHUDView.swift
│   │   ├── SettingsView.swift
│   │   └── Components/
│   │       ├── BrightnessSlider.swift
│   │       ├── ProfilePill.swift
│   │       └── DisplayBadge.swift
│   └── Utilities/
│       ├── KelvinToRGB.swift
│       ├── SolarCalculations.swift
│       └── Localization.swift
├── Resources/
│   ├── Assets.xcassets/
│   ├── Localizable.strings
│   └── InfoPlist.strings
├── Tests/
│   ├── DisplayManagerTests.swift
│   ├── BrightnessControllerTests.swift
│   └── ProfileManagerTests.swift
└── docs/
    └── SPEC.md
```

---

## Dependencies

| Dependency | Version | Purpose |
|------------|---------|---------|
| Sparkle | 2.x | Auto-updates |
| Sentry | 8.x | Crash reporting |

**Philosophy:** Minimal dependencies. Core functionality uses only Apple frameworks.

---

## Future Considerations (v2.0+)

- Display arrangement UI
- Resolution quick-switch
- Refresh rate control
- HDR settings
- Display rotation
- PIP (Picture-in-Picture) management
- Sidecar integration
- Widgets for Control Center
- Shortcuts app integration
- Apple Display (Studio Display/Pro Display XDR) native support

---

## References

- [DDC/CI Standard (VESA)](https://en.wikipedia.org/wiki/Display_Data_Channel)
- [Apple Display Services](https://developer.apple.com/documentation/coregraphics/quartz_display_services)
- [IOKit Framework](https://developer.apple.com/documentation/iokit)
- [Sparkle Framework](https://sparkle-project.org)
- [Sentry for Apple](https://docs.sentry.io/platforms/apple/)
- Similar apps: Lunar, MonitorControl, f.lux

---

## Version History

| Version | Date | Notes |
|---------|------|-------|
| 0.1 | 2026-01-15 | Initial draft |
| 0.2 | 2026-01-15 | Comprehensive requirements after Q&A |
