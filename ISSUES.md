# Orbital Pop - Known Issues and Resolutions

## Resolved Issues (2026-03-20)

### Issue 1: Early Tap Without Rings Silently Ignored
**Symptoms**: Tapping early with no banked rings did nothing — player waited for `check_too_slow()` instead of getting immediate feedback.

**Root Cause**: `attempt_hit()` only called `end_game()` on early tap if `inner_rings.size() > 0`. Early tap on ring 1 was silently ignored.

**Fix**: Removed the `inner_rings.size() > 0` guard. Any early/bad tap now calls `end_game()`, which internally checks for rings and either consumes one or triggers game over.

---

### Issue 2: App Crash on Launch (GADApplicationIdentifier)
**Symptoms**: App crashed immediately with `GADInvalidInitializationException` — "The Google Mobile Ads SDK was initialized without an application ID."

**Root Cause**: Godot's iOS export regenerates the Xcode project and resets `GADApplicationIdentifier` to an empty string in Info.plist.

**Fix**: After every Godot export, run:
```bash
/usr/libexec/PlistBuddy -c "Set :GADApplicationIdentifier ca-app-pub-4474484017776291~8538825055" \
  build/OrbitalPop/OrbitalPop-Info.plist
```

**Prevention**: This must be done after EVERY export. The Xcode project also needs Swift/framework fixes reapplied each time.

---

### Issue 3: Linker Errors (Swift Compatibility + JavaScriptCore)
**Symptoms**: `xcodebuild` failed with undefined symbols for `_OBJC_CLASS_$_JSContext`, `__swift_FORCE_LOAD_$_swiftCompatibility50`, etc.

**Root Cause**: Godot export doesn't configure Swift runtime settings or link system frameworks required by GoogleMobileAds.

**Fix**: Ruby script to fix Xcode project after each export:
- Set `SWIFT_VERSION = 5.0`
- Set `ALWAYS_EMBED_SWIFT_STANDARD_LIBRARIES = $(inherited)`
- Add Swift library search paths
- Link frameworks: JavaScriptCore, AdServices, AdSupport, CoreTelephony, StoreKit, SystemConfiguration, WebKit

---

### Issue 4: Taps During Grace Period Evaluated Against New Target
**Symptoms**: After hitting a stopper, the next tap immediately ended the game with `diff=2.43` (cursor was far from the NEW target).

**Root Cause**: After a successful hit, `on_target_hit()` spawns a new target far ahead. The spawn grace period blocked `check_too_slow()` but NOT `attempt_hit()`. A quick follow-up tap was evaluated against the distant new target — guaranteed miss.

**Fix**: In `attempt_hit()`, if `spawn_grace_period` is active and the tap doesn't hit the target, the miss is silently forgiven instead of calling `end_game()`:
```gdscript
if diff < threshold:
    on_target_hit()
elif spawn_grace_period:
    pass  # Forgive miss during grace
else:
    end_game("MISSED!", "Tapped too early")
```

---

### Issue 5: Inner Rings Cleared on Level Advance
**Symptoms**: Player collected rings via orange stoppers, completed the level, but rings were gone in the next level. `ir=0 rc=1` on game over debug.

**Root Cause**: `advance_to_next_level()` called `start_game()`, which unconditionally cleared `inner_rings` and reset `ring_count = 1`.

**Fix**: Added `_preserve_rings_on_start` flag. `advance_to_next_level()` sets it before calling `start_game()`. When the flag is set, `start_game()` keeps the rings and recalculates `ring_count` and `active_radius`. The flag is cleared on game over/retry paths.

---

### Issue 6: Level Complete Screen Skipped (Phantom Reset)
**Symptoms**: Game appeared to "reset" after hitting the final stopper — score went to zero, positions reset, no "LEVEL COMPLETE" screen shown.

**Root Cause**: The tap that hit the final stopper triggered `trigger_level_complete()` which set state to `LEVEL_COMPLETE`. But no input blocking was applied. On the next tap (or the same multi-touch event), `handle_tap()` saw `LEVEL_COMPLETE` state and immediately called `advance_to_next_level()` → `start_game()` — all in the same interaction.

**Fix**: Added 1.5-second input block in `trigger_level_complete()`:
```gdscript
input_blocked = true
input_block_end_time = Time.get_ticks_msec() / 1000.0 + 1.5
get_tree().create_timer(1.5).timeout.connect(func(): input_blocked = false)
```

**Debug discovery**: Used on-screen debug overlay (`s=COUNT sc=0 lh=0/10 ir=0 rc=1 lvl=2`) to identify that the game was in COUNTDOWN state with score=0 at level 2 — confirming level advance happened without the player seeing the celebration screen.

---

### Issue 7: use_extra_life() Tween Callback Not Firing
**Symptoms**: After ring consumption, the game appeared to freeze in COUNTDOWN state — cursor stopped, no new target spawned.

**Root Cause**: The `restore_tween.tween_callback()` in `use_extra_life()` could fail silently if the tween was interrupted or if the restored ring was invalid.

**Fix**:
1. Added `is_instance_valid()` checks on restored ring
2. Extracted `_resume_after_extra_life()` as a named function
3. Added 2-second safety fallback timer that resumes gameplay if the tween callback doesn't fire
4. Added `COUNTDOWN` state guard in `end_game()` to prevent re-entry during extra life transition

---

### Issue 8: Expansion Threshold Unreachable in Early Levels
**Symptoms**: Orange stopper never appeared in level 1. Extra life system was untestable.

**Root Cause**: `expansion_hit_threshold` was set to 7, but level 1 only required 5 hits (`level × 5`). The orange stopper could never spawn because the level completed first.

**Fix**: Lowered thresholds: 3 hits (levels 1-20), 5 hits (levels 21-50), 7 hits (levels 51+). Also changed hits formula to `level × 10` which further ensures expansion is reachable.

---

### Issue 9: Stale Xcode Project Artifacts
**Symptoms**: Multiple `.xcodeproj` files in the project directory causing confusion. Xcode showing "workspace has disappeared" dialogs.

**Root Cause**: Old build artifacts from a previous "Orbital Pop" (with space) export were left in the project root alongside the current `build/` directory.

**Fix**: Removed all stale artifacts from project root:
- `Orbital Pop/`, `Orbital Pop.ipa`, `Orbital Pop.pck`
- `Orbital Pop.xcarchive/`, `Orbital Pop.xcframework/`, `Orbital Pop.xcodeproj/`
- `MoltenVK.xcframework/`, `PrivacyInfo.xcprivacy`
- `DistributionSummary.plist`, `ExportOptions.plist`, `Packaging.log`

**Prevention**: Only `build/OrbitalPop.xcodeproj` should exist. Close Xcode when building from command line.

---

### Issue 10: Countdown Not Showing "0" on Final Hit
**Symptoms**: Hub countdown jumped from "1" directly to level complete screen without displaying "0".

**Root Cause**: `score_label.text` was only updated in `update_ui()`, which wasn't called between the final hit increment and `trigger_level_complete()`.

**Fix**: Added immediate `score_label.text = str(score)` update in `on_target_hit()` right after computing the new countdown value, before the level complete check.

---

## Debugging Techniques Used

### On-Screen Debug Overlay
When investigating state issues, a persistent debug label was added to `_process()`:
```gdscript
_debug_label.text = "s=%s sc=%d lh=%d/%d ir=%d rc=%d lvl=%d" % [
    state_name, score, level_hits, hits_required, inner_rings.size(), ring_count, current_level]
```
This was critical for identifying Issue 5 (rings cleared on level advance) and Issue 6 (phantom level reset).

### Debug Info in Game Over Title
Appending `ir=X rc=Y` to the fail label title confirmed ring counts at the moment of game over, distinguishing between "rings exist but aren't consumed" vs "rings are empty."

### Tagged End-Game Paths
Adding `"TAP ir=X"` vs `"SLOW ir=X"` prefixes to `end_game()` calls distinguished whether game overs came from `attempt_hit()` (player tapped) or `check_too_slow()` (cursor passed target).

### devicectl Console Output
`xcrun devicectl device process launch --console` was used to capture runtime output. Note: Godot's `print()` statements do NOT appear in `devicectl --console` output on iOS — only NSLog/os_log appears. On-screen debug is more reliable for iOS debugging.

## Testing Strategy

### Automated Tests (`test_game_rules.gd`)
- 44 tests covering hit detection, grace periods, ring system, level progression
- Run headless: `Godot --headless -s scripts/test_game_rules.gd`
- Tests reproduce game_manager logic using copied constants (not full scene)
- Exit code 0 = all pass, exit code 1 = failures

### Manual Testing Protocol
1. Build and deploy to physical iPhone (simulator unreliable)
2. Test each game mechanic in isolation
3. Use debug overlay to verify state during edge cases
4. Screenshot debug output for issue diagnosis
5. Remove all debug UI before production builds
