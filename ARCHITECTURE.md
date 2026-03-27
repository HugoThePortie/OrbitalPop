# Orbital Pop - Technical Architecture

## Project Structure

```
OrbitalPop/
├── project.godot          # Godot 4.5.1 project configuration
├── icon.svg               # App icon
├── export_presets.cfg     # iOS export configuration
├── scenes/
│   └── main.tscn          # Minimal scene (just root node with script)
├── scripts/
│   ├── game_manager.gd    # All game logic (programmatic scene building)
│   ├── admob_manager.gd   # AdMob rewarded ads wrapper
│   ├── iap_manager.gd     # In-app purchase wrapper
│   ├── star_manager.gd    # Star economy system
│   └── test_game_rules.gd # Automated game rules tests (87 tests)
├── fonts/
│   ├── Orbitron-Bold.ttf
│   └── Orbitron-Black.ttf
├── shaders/
│   ├── bottom_glow.gdshader
│   ├── grid_pulse.gdshader
│   ├── radial_glow.gdshader
│   └── scanlines.gdshader    # CRT scanline + flicker overlay (Vectrex theme)
├── assets/
│   └── img/
│       ├── luma-logo.png          # Source logo (1024x512)
│       ├── luma-logo-splash.png   # Boot splash (1170x2532, 2.5x logo centered)
│       ├── splash@2x.png          # iOS launch (750x375)
│       └── splash@3x.png          # iOS launch (1125x563)
├── addons/
│   └── AdmobPlugin/       # godot-admob v5.3 plugin
├── ios/
│   ├── plugins/            # iOS plugin frameworks
│   └── framework/          # AdMob frameworks
├── build/                  # iOS Xcode project output (regenerated on export)
├── PRD.md                  # Product requirements
├── ARCHITECTURE.md         # This file
└── ISSUES.md               # Known issues and resolutions
```

## Design Decision: Programmatic Scene Building

The entire game scene is built programmatically in `game_manager.gd`:

1. **Reliability**: Godot's scene files sometimes strip material properties
2. **Single source of truth**: All game logic and scene structure in one file
3. **Easier iteration**: No sync issues between scene file and code

## Node Hierarchy (Built at Runtime)

```
GameManager (Node3D) - root
├── Camera3D - orthographic, looking at ring from front
├── DirectionalLight3D - soft lighting
├── WorldEnvironment - ambient light settings
├── Background (MeshInstance3D) - QuadMesh with gradient shader
├── CoreSphere (MeshInstance3D) - center sphere (flattens for clamshell during capture)
├── ProgressRing (MeshInstance3D) - TorusMesh showing level progress
├── ScoreLabel (Label3D) - countdown display with rolling odometer animation
├── WorldGroup (Node3D) - rotates on X-axis for flip + 45deg boss tilt
│   ├── OrbitRing (MeshInstance3D) - TorusMesh (active ring)
│   ├── InnerRings[] - Array of shrunk TorusMesh (extra lives)
│   ├── CursorPivot (Node3D) - rotates on Z-axis
│   │   └── Cursor (MeshInstance3D) - red chamfer box
│   ├── GhostPivots[] - Trailing cursor echoes (frenzy mode)
│   └── TargetHolder (Node3D) - rotates on Z-axis
│       └── Target (MeshInstance3D) - cylinder stopper
├── BossInvader (MeshInstance3D) - spawned during boss mode, 3D voxel mesh
├── BossHPBar (bg + fill MeshInstance3D) - follows boss position
├── TractorBeam (Node3D) - gravity well funnel mesh with animated shader
├── AudioPlayers
│   ├── sfx_hit, sfx_miss, sfx_flip, sfx_expand, sfx_level_complete
│   ├── sfx_perfect_hit, sfx_start, sfx_boss_siren, sfx_boss_bullet
│   ├── sfx_tractor_beam, sfx_boss_escape
│   └── bgm_player (ambient/boss loop)
├── ScanlineOverlay (CanvasLayer, layer 90)
└── HUD (CanvasLayer)
    ├── LevelLabel - "LEVEL X" (top-right, turquoise, fixed position)
    ├── ProgressLabel - "X / Y" (centered)
    ├── StarContainer - "X" (top-right, below level)
    ├── FailLabel - "MISSED!" / "LEVEL X COMPLETE!"
    ├── SettingsButton - hamburger menu (top-left)
    └── [Overlay layers: SettingsLayer, TrophyLayer, TrophyInspect, OutOfStarsLayer]
```

## Key Systems

### Boss Mode System

**State Variables:**
```
is_boss_mode: bool              # Active flag
_boss_defeated: bool            # Prevents escape after defeat
_boss_escaped: bool             # Prevents defeat after escape
_boss_tilt_target: float        # Enforced 45-degree tilt angle
_level_complete_deferred: bool  # Level complete waiting for boss to finish
boss_hp, boss_max_hp_current, boss_shield_hp
boss_timer: float               # 20-second countdown
boss_encounters: int            # Escalation counter (persists across levels)
boss_drift_time, boss_drift_speed
boss_bombs: Array               # Active bomb projectiles
```

**Boss Registry:** 24 entries, each with key, name, icon, color, and row data for voxel mesh generation. Bosses selected randomly from uncaptured pool.

**Trigger Chain:** Perfect hits -> frenzy_streak >= 6 -> `_activate_boss_mode()`

**Level Complete Deferral:**
- `trigger_level_complete()` has guard: if `is_boss_mode`, sets `_level_complete_deferred` and returns
- Level hits don't increment during boss mode
- `_apply_bonus_hits()` returns immediately during boss mode
- After boss defeat/escape, deferred level complete fires if hits >= required

### Boss Mesh Builder

```gdscript
func _build_invader_mesh_from_rows(rows: Array, cell: float = 0.12) -> ArrayMesh:
    # Column 0 = single center cell, columns 1+ = mirrored left/right
    # Each cell: 6 faces x 2 triangles = extruded 3D box
    # Cell size: 0.5 (full fill, no gaps between adjacent cells)
    # Depth: TARGET_HEIGHT (0.08)
```

**Material Requirements (enforced by tests):**
- `cull_mode = CULL_DISABLED` — all faces visible from any angle
- `emission_enabled = true` with boss's own registry color
- Never overridden by theme colors

### Trophy Persistence

```gdscript
# Saved to user://save.cfg under [trophies] section
trophies_unlocked: Dictionary  # {"mawface": true, "grinner": false, ...}
# Loaded dynamically from BOSS_REGISTRY keys
# Dev mode: all trophies shown as unlocked
```

### Trophy Room 3D Rendering

**Grid thumbnails:** `_make_boss_icon_texture()` renders pixel art to Image -> ImageTexture (no SubViewport)

**Inspect view:** Isolated SubViewport with own World3D:
- Camera: orthographic, size 1.8
- Two-point lighting
- Boss mesh with CULL_DISABLED + emission
- UPDATE_ALWAYS for continuous rotation
- Touch drag: Y-axis spin with inertia + X-axis pitch (clamped +/-90 degrees)

### Tractor Beam (Gravity Well)

**Mesh:** Procedural paraboloid, 40 segments x 30 rings
```
r(t) = well_radius / (1 + 25 * t^2) + stem_radius  # Hyperbolic profile
y(t) = well_depth * (1 - t^2)                        # Quadratic height
```

**Shader** (inline, spatial, blend_add, unshaded, cull_disabled):
```glsl
float scroll = UV.y + TIME * ring_speed;
float ring = abs(fract(scroll / ring_spacing) - 0.5) * 2.0;
float ring_mask = smoothstep(...) * edge_fade;
// 3 colors cycling: cyan, blue, magenta
```

Inspired by CubePlanet `pulse_ring_shader` pattern.

### Hit Detection System

```gdscript
func get_overlap_threshold() -> float:
    var midpoint = (CORE_RADIUS + active_radius) / 2.0
    var stopper_half_angle = TARGET_RADIUS / midpoint
    var cursor_half_angle = (CURSOR_WIDTH / 2.0) / midpoint
    return stopper_half_angle + cursor_half_angle
```

Perfect hit: `diff < threshold * PERFECT_HIT_RATIO` (0.4, or 0.8 in dev mode)

### Audio System

All sounds pre-generated as AudioStreamWAV at 22050Hz sample rate for iOS compatibility. Background music loops via `loop_mode = LOOP_FORWARD`.

| Sound | Generator | Key Parameters |
|-------|-----------|---------------|
| Hit | `_gen_harmonic_ping` | 587Hz, inharmonic partials |
| Miss | `_gen_wobble_down` | 220->110Hz, vibrato |
| Flip | `_gen_phase_whoosh` | 350->700Hz, phase cancellation |
| Perfect | `_gen_crystal_chime` | 880Hz, detuned shimmer |
| Boss Siren | `_gen_boss_siren` | 600/900Hz alternating square |
| Boss Bullet | `_gen_bullet_zap` | 400->1200Hz ascending, 100ms |
| Tractor Beam | `_gen_tractor_beam` | 800->200Hz warble, 2.0s |
| Boss Escape | `_gen_boss_escape` | A4-F#4-Eb4 minor descent |
| Ambient BGM | `_gen_ambient_loop` | 25s, Am9->Fmaj7->Cmaj7->Em7 |
| Boss BGM | `_gen_boss_loop` | 25s, 140BPM, E minor |

## State Variables

| Variable | Type | Purpose |
|----------|------|---------|
| `current_state` | GameState | MENU, LEVEL_SELECT, COUNTDOWN, PLAYING, LEVEL_COMPLETE, GAME_OVER |
| `current_level` | int | Current level (1-100) |
| `level_hits` | int | Hits in current level (frozen during boss mode) |
| `hits_required` | int | Hits needed (level x 10) |
| `is_boss_mode` | bool | Boss fight active |
| `_boss_defeated` / `_boss_escaped` | bool | Prevents race conditions |
| `boss_encounters` | int | Escalation counter |
| `boss_timer` | float | 20-second escape countdown |
| `frenzy_streak` | int | Consecutive perfect hits (triggers boss at 6) |
| `trophies_unlocked` | Dictionary | Persistent boss capture state |
| `current_ui_theme` | String | "vectrex" or "orbital" |
| `current_bgm` | String | "ambient" or "boss" |
| `dev_mode_enabled` | bool | Wider perfect zone, all trophies visible |

## Constants

```gdscript
const BOSS_TRIGGER_STREAK: int = 6
const BOSS_MAX_HP: int = 6
const BOSS_TILT_ANGLE: float = deg_to_rad(45)
const BOSS_INVADER_HEIGHT: float = 3.5
const BOSS_BOMB_INTERVAL: float = 2.5
const BOSS_BOMB_SPEED: float = 1.5
const BOSS_TIME_LIMIT: float = 20.0
const PERFECT_HIT_RATIO: float = 0.4
const FRENZY_THRESHOLD: int = 3
const OVERDRIVE_THRESHOLD: int = 5
```

## iOS Build & Deploy

### Full Deploy Procedure

```bash
# 1. Export from Godot
cd /Users/jeffkinelly/Documents/Projects/OrbitalPop
/Applications/Godot.app/Contents/MacOS/Godot --headless --export-debug "iOS" build/OrbitalPop.pck

# 2. Fix AdMob App ID
/usr/libexec/PlistBuddy -c "Set :GADApplicationIdentifier ca-app-pub-4474484017776291~8538825055" \
  build/OrbitalPop/OrbitalPop-Info.plist

# 3. Fix Xcode project (Swift + framework linking)
cd build && ruby -e '...'  # See ISSUES.md for full script

# 4. Build for device
xcodebuild -project OrbitalPop.xcodeproj -scheme OrbitalPop \
  -destination 'id=00008110-001A292C3E0A401E' -allowProvisioningUpdates

# 5. Install on phone
xcrun devicectl device install app \
  --device C46A4F35-8EBD-571F-BE6F-820B3E53A04C \
  ~/Library/Developer/Xcode/DerivedData/OrbitalPop-gqfoohiignziaiglzjupnskpqvqr/Build/Products/Debug-iphoneos/OrbitalPop.app
```

## Testing

### Automated Tests (87 tests)

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless -s scripts/test_game_rules.gd`

| Category | Tests | What's Verified |
|----------|-------|-----------------|
| Overlap threshold | 3 | Threshold geometry, scales with radius |
| Hit detection | 2 | Exact overlap = hit |
| Miss detection | 2 | Opposite side = miss |
| Grace period | 2 | Miss forgiven, hit registers |
| Extra life | 3 | Rings prevent game over |
| Expansion threshold | 20 | Orange stopper reachable per level |
| Too-slow detection | 2 | Cursor past target logic |
| Ring consumption | 3 | Ring count, inner rings consumed |
| Target scaling | 4 | All targets same size |
| Perfect/frenzy | 5 | Streak builds, breaks, multiplier caps |
| Daily seed | 2 | Deterministic RNG |
| **Boss material** | **2** | **CULL_DISABLED, emission enabled** |
| **Boss color** | **2** | **Registry color preserved, not theme-overridden** |
| **Viewport material** | **2** | **CULL_DISABLED + emission in trophy room** |
| **Mesh format** | **3** | **PRIMITIVE_TRIANGLES (not LINES), has vertices** |

### Manual Test Checklist

1. Ring 1, hit stopper -> continues
2. Ring 1, early tap -> game over
3. Hit orange expand -> ring added
4. Ring 2+, miss -> consume ring
5. Complete level with rings -> persist
6. Game over -> rings cleared
7. Final hit shows "0" -> level complete
8. 6 consecutive perfects -> boss mode triggers
9. Boss mode: level counter frozen
10. Boss defeat -> tractor beam capture -> "CAPTURED!" text
11. Boss escape (20s timeout) -> swirl flyaway -> "ESCAPED!"
12. Trophy room: all bosses visible in dev mode
13. Trophy inspect: drag to rotate, tap to close
14. Bosses render as solid colored shapes (not wireframe/black faces)
15. Settings menu pauses game, no taps leak through
