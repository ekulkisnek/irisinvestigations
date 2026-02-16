# ScreenWarmth

Menu bar app that applies gamma-based brightness and warmth to all connected displays (no flicker, same mechanism as Iris).

## Build

1. Open `ScreenWarmth.xcodeproj` in Xcode (double-click or File → Open).
2. Press **Cmd+B** to build, or **Cmd+R** to run.

The app will appear in the menu bar (sun icon). Click it to open the popover: adjust **Brightness** and **Warmth** sliders, check **Enable** to apply, and use **Quit** or the app menu to exit (display is restored on quit).

## Requirements

- macOS 13.0+
- Xcode 15+

## Behavior

- **Menu bar only** (no dock icon; `LSUIElement` in Info.plist).
- **All displays**: Same brightness and warmth applied to every connected monitor.
- **Enable/Disable**: When you turn on, original gamma is saved per display; when you turn off or quit, all displays are restored.
- **Display changes**: Reconfiguration callback reapplies gamma when you plug/unplug a monitor.
- **Wake**: After sleep, gamma is reapplied if enabled.
- **No auto reapply**: The app never polls or “corrects” gamma in the background. It only applies when you turn Enable on, change a slider, plug/unplug a display, or wake from sleep. So the display never auto flicks on/off.
- **Tip**: If you use Night Shift (or similar), turn it off in System Settings so it doesn’t overwrite our gamma. Otherwise our settings may be replaced by Night Shift after a short while and stay that way until you change a slider or wake.

## Files

- `ScreenWarmth/AppDelegate.swift` – Status item, popover, main menu, lifecycle.
- `ScreenWarmth/GammaController.swift` – Display enumeration, gamma tables, apply/restore, reconfiguration and wake.
- `ScreenWarmth/PopoverContentViewController.swift` – Brightness and warmth sliders, Enable toggle, Quit.
- `ScreenWarmth/Info.plist` – `LSUIElement`, bundle ID, etc.
