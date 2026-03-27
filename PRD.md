# Orbital Pop - Product Requirements Document

## Overview

Orbital Pop is a hyper-casual reflex game for mobile devices. A cursor (scrubber) orbits around a ring, and the player taps to stop it when it overlaps with target "stopper" cylinders. The game features 100 levels with increasing difficulty, a flip mechanic, an expansion mechanic that adds outer rings, inner rings that serve as extra lives, a boss capture system triggered by perfect hit streaks, and a trophy room for collected alien bosses.

## Target Platform

- **Primary**: iOS (iPhone portrait mode)
- **Viewport**: 390 x 844 pixels
- **Engine**: Godot 4.5.1 with Mobile renderer

## Level Progression

### 100 Levels
- Game progresses through 100 levels
- Each level requires `level x 10` hits to complete (Level 1: 10, Level 100: 1000)
- Hub displays a **countdown** (hits remaining) that decreases to 0 with rolling odometer animation
- Progress ring around center sphere shows completion percentage
- Level complete celebration with spinning rings and slide-up animation
- Input blocked for 1.5 seconds after level complete to prevent accidental skip
- Level counter frozen during boss mode — hits only count toward boss HP

### Level Difficulty Matrix

| Level Range | Base Speed | Flip Chance | Expand Every | Notes |
|-------------|-----------|-------------|-------------|-------|
| 1-5         | 2.5 rad/s | 0%          | 3 hits      | No flips, gentle intro |
| 6-10        | 2.5 rad/s | 15%         | 3 hits      | Flips introduced |
| 11-20       | 3.0 rad/s | 15%         | 3 hits      | Speed tier 2 |
| 21-30       | 3.0 rad/s | 25%         | 5 hits      | More flips, slower expand |
| 31-50       | 3.5 rad/s | 25%         | 5 hits      | Speed tier 3 |
| 51-60       | 3.5 rad/s | 35%         | 7 hits      | High flip chance |
| 61-90       | 4.0 rad/s | 35%         | 7 hits      | Speed tier 4 |
| 91-100      | 4.5 rad/s | 35%         | 7 hits      | Maximum difficulty |

## Core Gameplay

### Ring and Cursor (Scrubber)
- A torus ring sits at the center of the screen
- A red chamfer box cursor orbits the ring continuously
- Cursor starts at 6 o'clock position (bottom)
- Cursor reverses direction after each successful hit (except flips)

### Target Stoppers
- Cylindrical stoppers spawn on the ring
- All stoppers are the same size regardless of type
- Player taps when the scrubber overlaps a stopper
- Miss consumes a ring (extra life) if available, otherwise game over

### Hit Detection
- Pixel-contact threshold computed dynamically
- Same threshold for `attempt_hit` (tap) and `check_too_slow` (cursor passes stopper)
- No latency buffer — strict overlap required

### Grace Period System

| Event | Duration | Effect |
|-------|----------|--------|
| After target spawn | 0.8s | `check_too_slow` blocked |
| After flip | 3.0s | `check_too_slow` blocked |
| After expansion | 2.0s | `check_too_slow` and spawn blocked |
| After extra life | 2.0s | `check_too_slow` and spawn blocked |
| Spawn grace (tap) | Active | Taps that miss are forgiven |
| Level complete | 1.5s | All input blocked |

### Perfect Hits & Frenzy Streak

- Hit within 40% of overlap threshold center = **perfect hit** (2x progress)
- Dev mode: perfect zone doubled to 80% for easier testing
- 3 consecutive perfects activate **Frenzy mode** (gold glow, ghost cursors)
- Multipliers: 1.0x -> 1.5x -> 2.0x -> 3.0x
- 5 consecutive perfects activate **Overdrive** (brief speed slowdown)
- **6 consecutive perfects trigger Boss Mode**

### Star Economy

| Event | Stars |
|-------|-------|
| Daily grant | 3 stars |
| Game loss | -1 star consumed |
| Level complete | +1 (or +2 during Frenzy) |
| Watch ad | +2 stars (fallback: grants directly if ads unavailable) |
| Max capacity | 10 stars |

## Boss Mode

### Trigger
- 6 consecutive perfect hits activates boss mode
- Level counter freezes — hits during boss mode only count toward boss HP
- Level complete deferred until boss fight concludes

### Boss Activation
1. "BOSS INCOMING" warning text with bounce animation
2. Warning siren sound effect plays
3. Background tints red
4. Music switches to boss track (140 BPM, E minor)
5. World tilts 45 degrees (enforced every frame)
6. Core sphere hidden
7. Random uncaptured boss spawns above the ring (never repeats captured bosses)
8. Shield + HP bar built

### Boss Combat
- Each successful ring hit fires a white bullet sphere at the boss
- Bullet fire sound (ascending zap) plays on launch
- Damage applied when bullet arrives (0.3s travel time)
- Boss flashes white and shakes on impact
- Shield absorbs first 2+ hits (scales with encounters)
- HP bar floats above boss, color shifts green -> yellow -> red
- Boss drifts side-to-side and bobs, drops bombs toward ring
- Misses are free during boss mode (no ring loss)
- **20-second timer** — if boss not defeated, it escapes (swirl flyaway + sad melody)

### Boss Defeat & Capture
1. Gravity well tractor beam appears — parabolic funnel mesh with animated scrolling ring shader (cyan/blue/magenta)
2. Core sphere flattens (clamshell open animation)
3. Boss pulled down through funnel, shrinking and spinning
4. Core sphere closes, ring bursts fire
5. "BOSSNAME CAPTURED!" text displays (every defeat, not just first)
6. Trophy saved to persistent storage
7. Tilt restores, background un-tints, music switches back
8. Frenzy grace: 5 free non-perfect hits before streak breaks
9. Bonus ring awarded if < 4 rings (delayed until after capture)
10. Deferred level complete fires if hits were sufficient

### Boss Escape
- 20-second timer expires
- Boss swirls upward and off screen with tumbling rotation
- "ESCAPED!" text in orange
- Sad 3-note descending melody plays
- No trophy awarded
- Game resumes normally

### Escalating Difficulty

| Encounter | Shield HP | Boss HP | Bomb Interval | Drift Speed |
|-----------|-----------|---------|---------------|-------------|
| 1st       | 2         | 6       | 2.5s          | 0.50        |
| 2nd       | 3         | 8       | 2.08s         | 0.65        |
| 3rd       | 4         | 10      | 1.79s         | 0.80        |
| 4th+      | 5 (cap)   | 14 (cap)| 1.39s+        | 1.10+       |

### Race Condition Guards
- `_boss_defeated` and `_boss_escaped` flags prevent both paths from firing
- `is_boss_mode = false` set immediately at top of both functions
- `trigger_level_complete()` has guard: if boss mode active, defers instead

## Trophy Room

### Access
- Settings menu -> "Trophies [X/24]" button
- Dev mode: all 24 bosses shown as unlocked

### Grid View
- 5-column scrollable grid of 64x64 tiles
- Unlocked: 2D pixel-art icon (ImageTexture, nearest-neighbor filtering)
- Locked: dark panel with "?" text
- Tap unlocked tile to inspect

### Inspect View
- Fullscreen popup with dark backdrop
- 3D boss rendered in isolated SubViewport (400x400, own World3D)
- Boss uses its own vivid registry color with emission (not theme-overridden)
- Material has CULL_DISABLED for solid rendering from all angles
- Drag left/right to spin (Y-axis with inertia)
- Drag up/down to tilt (X-axis, clamped +/-90 degrees)
- Boss name in large colored text
- "CAPTURED" status in green
- Tap anywhere to close

### 24 Boss Designs
- Pixel-art aliens traced from custom illustrations
- Each boss: 8 rows of mirrored column data, solid-fill with eye cutouts
- Column 0 = single center voxel, columns 1+ = mirrored left/right
- 3D voxel meshes: extruded boxes with TARGET_HEIGHT depth, cells fill 100% (no gaps)
- Each boss has unique vivid color (bright red, yellow, emerald, magenta, cyan, etc.)
- Boss selection: random from uncaptured pool; if all captured, any random

## Background Music

### Procedurally Generated
- **Ambient track**: 25-second loop, 4-chord progression (Am9 -> Fmaj7 -> Cmaj7 -> Em7), layered detuned sine voices, sub-bass drone, high shimmer
- **Boss track**: 25-second loop, 140 BPM, E minor, driving bass, sixteenth-note arpeggios, kick/hi-hat, tension chord pads
- Both loop seamlessly via AudioStreamWAV LOOP_FORWARD
- Music selector in settings (< > arrows)
- Mute toggle stops/resumes BGM

## Sound Effects

All procedurally generated AudioStreamWAV:

| Sound | Description |
|-------|-------------|
| Hit | 440Hz metallic ping, 150ms |
| Miss | 220->110Hz wobble down, 400ms |
| Flip | 350->700Hz phase whoosh, 350ms |
| Expand | 130Hz boom + 520Hz shimmer, 450ms |
| Perfect | 880Hz crystal chime with detune |
| Level Complete | C5-E5-G5-C6 victory arpeggio |
| Boss Siren | 600/900Hz alternating alarm, 1.2s |
| Boss Bullet | 400->1200Hz ascending zap, 100ms |
| Tractor Beam | 800->200Hz descending warble, 2.0s |
| Boss Escape | A4-F#4-Eb4 sad descending melody, 0.8s |

## HUD Layout

### Top Right
- **Level label**: "LEVEL X" — right-aligned, turquoise, 24pt bold (fixed position, not ring-relative)
- **Star count**: "X" — right-aligned, gold, 24pt (below level label)

### Top Left
- **Settings button**: Hamburger icon (hamburger) with themed styling

### Center Hub
- **Countdown number**: Large Label3D on center sphere, rolling odometer animation
- **Streak arcs**: 3 arc segments showing frenzy progress
- **Progress label**: "X / Y" centered, 50% alpha

## Visual Design

### Theme System
- **VECTREX** (Default): CRT vector display, monochrome phosphor, glow/bloom, scanlines, wireframe core
- **ORBITAL**: Synthwave, multi-color, standard shading, solid core
- Boss materials always use their own registry color with emission — never theme-overridden

### Tractor Beam
- Parabolic gravity well mesh (40 segments x 30 rings)
- Profile: `r(t) = well_radius / (1 + 25*t^2)` — hyperbolic, steep walls at bottom, flat at top
- Tilted 25 degrees toward camera for 3D perspective
- Animated shader: scrolling ring bands (cyan/blue/magenta cycling), blend_add, cull_disabled
- Shader uses `TIME * ring_speed` for continuous animation (CubePlanet pulse_ring_shader pattern)
- Three phases: grow from hub, pull boss down, shrink back into hub

## Game States

1. **Menu**: "TAP TO START", level label, star count, settings button
2. **Countdown**: 3-2-1 before gameplay
3. **Playing**: Cursor orbiting, stoppers spawning, countdown updating
4. **Boss Mode**: 45-degree tilt, boss floating above ring, bullets firing, HP bar tracking
5. **Level Complete**: Celebration, spinning rings, "TAP TO CONTINUE"
6. **Game Over**: Fail reason, "TAP TO RETRY"

### Input Blocking
- Game input blocked when any overlay is open (settings, trophy room, inspect, out-of-stars)
- `level_select_layer` checked for `.visible` (it's always in the tree)

## Controls

- Touch/tap anywhere to attempt hit
- Touch/tap to continue/retry
- Mouse click and spacebar for desktop testing
- Drag to rotate boss in trophy inspect view
