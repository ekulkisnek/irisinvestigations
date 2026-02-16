# Plan: ScreenWarmth with and without Night Shift (no visible on/off)

## Goal
- **Without Night Shift**: Our gamma stays applied. Apply only on Enable, slider change, display reconfig, wake. No polling. ✅ Already works.
- **With Night Shift**: Something overwrites our gamma every ~10s. We must restore our settings **without the user ever seeing the display "turn on or off"** (no flicker, no visible transition).

## Why visible reapply fails
- **Instant reapply**: One `CGSetDisplayTransferByTable` → visible flash.
- **Short fade (0.3–0.5s)**: User still perceives "something turned on/off".
- **Faster poll + cooldown**: Doesn’t remove the visibility of each reapply.

## Approaches to test and investigate

### 1. No reapply when overwritten (current “no poll” behavior)
- **What**: Never poll. Only apply on Enable, slider, reconfig, wake.
- **With Night Shift**: Our gamma gets overwritten ~every 10s and stays overwritten until user action or wake. No flicker.
- **Verdict**: Works for “no visible on/off”; user loses our effect until they interact or wake. Acceptable if user turns Night Shift off.

### 2. Imperceptible slow drift (chosen implementation)
- **What**: When we detect overwrite (poll every 2s, 2 consecutive diffs), reapply over **25–30 seconds** in **many small steps** (e.g. 80 steps ≈ 0.3s apart). Each step moves gamma 1/80 toward target.
- **Why**: Per-frame delta is below typical perceptual threshold; transition is invisible.
- **Parameters**: Poll 2s, 2 consecutive diffs, drift 25s, 80 steps, cooldown 15s after drift so we don’t stack.
- **With Night Shift**: Our settings come back gradually and imperceptibly; no “turn on/off” moment.
- **Test**: Run with Night Shift on for 2+ minutes; confirm no visible step and that warmth/brightness return.

### 3. Very long fade (e.g. 60–120s)
- **What**: Same as slow drift but 60–120s total duration.
- **Pro**: Even less chance of visibility.
- **Con**: User waits a long time for full correction; if Night Shift overwrites again during fade, logic gets messy.

### 4. Sub-perceptual step size (research-driven)
- **What**: Find a gamma delta below perception (e.g. via literature or A/B tests), then reapply in steps at or below that delta until we reach target.
- **Pro**: Theoretically invisible.
- **Con**: Requires research and tuning; step count and duration variable.

### 5. “Sync” with Night Shift (advanced)
- **What**: Detect or predict when Night Shift applies and apply our gamma in the same or next frame so only our result is visible.
- **Con**: Depends on private behavior; fragile and complex. Not recommended.

### 6. Different API / composition
- **What**: Use an API that composes with system color (e.g. “user gamma” layer).
- **Reality**: macOS exposes one gamma table; no public “composed” API. Not viable.

## Test matrix

| Scenario              | Night Shift | Expected behavior |
|----------------------|------------|-------------------|
| Enable, no NS        | Off        | Our gamma applied once, stays. No flicker. |
| Enable, NS on        | On         | Our gamma applied; when NS overwrites, slow drift restores it invisibly. No visible on/off. |
| Slider change        | Either     | Instant apply (user expects change). No poll-driven flicker. |
| Wake                 | Either     | Instant apply on wake. OK. |
| Plug/unplug display  | Either     | Reconfig callback applies once. OK. |
| Quit / Disable       | Either     | Restore originals once. OK. |

## Implementation choice
- **Default**: Implement **2. Imperceptible slow drift** so it works with Night Shift and without any visible on/off.
- **Fallback**: If user disables “correct when overwritten”, behave like **1** (no poll); recommend turning Night Shift off.

## Verification
1. **Without Night Shift**: Enable app, change sliders, wake, replug display; confirm single applies and no flicker.
2. **With Night Shift**: Enable app and Night Shift; wait 2+ minutes; confirm no visible transition and that warmth/brightness return (e.g. by comparing to a photo or second display).
3. **Log (optional)**: Log drift start/end to `~/screenwarmth_gamma_changes.log` for debugging; no log on every poll.
