# Orbital Pop - Product Requirements Document

## Overview

Orbital Pop is a hyper-casual reflex game for mobile devices. A cursor orbits around a ring, and the player taps to stop it when it aligns with target "stopper" cylinders. The game features 100 levels with increasing difficulty, a unique flip mechanic, an expansion mechanic that adds outer rings, and inner rings that serve as extra lives.

## Target Platform

- **Primary**: iOS (iPhone portrait mode)
- **Viewport**: 390 x 844 pixels
- **Engine**: Godot 4.5 with Mobile renderer

## Level Progression

### 100 Levels
- Game progresses through 100 levels
- Each level requires `level × 5` hits to complete:
  - Level 1: 5 hits
  - Level 2: 10 hits
  - Level 3: 15 hits
  - ...
  - Level 100: 500 hits
- Progress ring around center sphere shows completion percentage
- Level complete celebration with spinning rings animation
- Player must tap to continue after completing each level

## Core Gameplay

### Ring and Cursor
- A torus ring sits at the center of the screen
- A red chamfer box cursor orbits the ring continuously
- Cursor starts at 6 o'clock position
- Cursor speed increases progressively at score milestones (10, 20, 30)

### Target Stoppers
- Turquoise cylinder stoppers spawn halfway between the center sphere and ring
- Player taps to stop the cursor when it overlaps a stopper
- Successful hit: score increases, cursor reverses direction, new stopper spawns
- Miss: uses extra life if available, otherwise game over

### Flip Targets (Purple)
- 25% chance for a stopper to be a purple "flip" target
- Purple targets are slightly larger (1.2x scale)
- When hit:
  - Dramatic explosion effect with expanding ring burst
  - World rotates 180 degrees on X-axis (coin flip effect)
  - Cursor continues moving in the same direction (no reversal)
  - New stopper spawns 45-90 degrees ahead after flip completes

### Expansion Targets (Orange)
- Orange cylinder appears every 7-8 successful hits (up to 4 rings max)
- Orange targets are larger (1.3x scale)
- When hit:
  - Large explosion effect with expanding ring burst
  - New outer ring is created (radius +0.5)
  - Previous ring shrinks and becomes an inner ring
  - Camera zooms out to show the new ring
  - Cursor expands to fill gap between center sphere and new ring
  - Cursor reverses direction

### Extra Lives (Inner Rings)
- Inner rings created by expansion serve as extra lives
- When player misses with inner rings available:
  - Current outer ring explodes and is removed
  - Outermost inner ring zooms back to become the active ring
  - Camera zooms back in
  - Gameplay continues with grace period
- Inner rings are positioned concentrically around center sphere (0.25 unit spacing)
- Maximum 3 extra lives (from 4 total rings)

### Scoring
- +1 point per successful hit
- Score displayed in white text on the center sphere
- High score saved persistently

## Sound Effects

### Procedurally Generated Audio
All sounds are generated programmatically using AudioStreamWAV (pre-generated at startup for iOS compatibility):

- **Hit sound**: 440Hz tone with 1.3x pitch rise, 80ms duration
- **Miss sound**: 180Hz low tone with 0.5x pitch drop, 200ms duration
- **Flip sound**: Quick sweep from 600Hz to 900Hz, 150ms duration
- **Expand sound**: Slow sweep from 300Hz to 600Hz, 300ms duration
- **Level complete**: 5-note ascending arpeggio (C5→E5→G5→C6→E6)

### Mute Toggle
- White icon button in bottom right corner
- ♪ icon when sound enabled
- ✕ icon when muted
- State persists during session

## Visual Design

### Dynamic Color Theme
- Background and center sphere shift hue as score increases
- Starting hue: teal green (0.45)
- Hue shifts 0.02 per point scored
- Creates a colorful, evolving atmosphere

### Colors
- Cursor: Red (#ff5252)
- Regular stopper: Turquoise (#33d9b2)
- Flip stopper: Purple (#9b59b6)
- Expansion stopper: Orange (#ff9800)
- Score text: White

### Visual Elements
- **Cursor**: Red chamfer box (beveled edges), skinny and elongated
- **Stoppers**: Cylinders with flat faces toward camera
- **Rings**: High-resolution torus meshes (64 rings, 24-32 ring segments)
- **Center sphere**: Semi-transparent with dynamic hue (64 radial segments, 32 rings)
- **Progress ring**: Torus around center sphere showing level completion percentage

### 3D Mesh Resolution
Higher polygon counts for smooth appearance:
- Core sphere: 64 radial segments, 32 rings
- Orbit ring torus: 64 rings, 24 ring segments
- Target cylinder: 32 radial segments
- Progress ring: 64 rings, 16 ring segments

### Effects
- Score pulses on hit
- Particle explosion on stopper hit (12 regular, 24 flip, 30 expansion)
- Expanding ring burst for special targets
- Ring explosion when extra life is used
- Camera shake on game over
- Camera zoom on miss (300% zoom to missed stopper)
- Level complete: All rings spin around central sphere (3 full rotations over 2 seconds)

## Game States

1. **Menu**: "TAP TO START" displayed, high score shown
2. **Playing**: Cursor orbiting, stoppers spawning, score updating
3. **Level Complete**: Celebration animation, progress ring full, "TAP TO CONTINUE"
4. **Game Over**: Fail reason shown ("MISSED!" or "TOO SLOW!"), "TAP TO RETRY"

## Speed Progression

| Score | Speed Multiplier |
|-------|------------------|
| 0-9   | 1x (start speed) |
| 10-19 | 1.5x             |
| 20-29 | 2x               |
| 30+   | 3x (full speed)  |

## Controls

- Touch/tap anywhere to attempt hit
- Touch/tap mute button to toggle sound
- Touch/tap to continue after level complete
- Mouse click supported for desktop testing
- Spacebar supported for desktop testing
