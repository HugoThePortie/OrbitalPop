# Orbital Pop - Technical Architecture

## Project Structure

```
OrbitalPop/
├── project.godot          # Godot project configuration
├── icon.svg               # App icon
├── export_presets.cfg     # iOS export configuration
├── scenes/
│   └── main.tscn          # Minimal scene (just root node with script)
├── scripts/
│   └── game_manager.gd    # All game logic (programmatic scene building)
├── build/                 # iOS Xcode project output
│   └── OrbitalPop.xcodeproj/
├── PRD.md                 # Product requirements
└── ARCHITECTURE.md        # This file
```

## Design Decision: Programmatic Scene Building

The entire game scene is built programmatically in `game_manager.gd` rather than using Godot's scene editor. This approach was chosen because:

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
├── CoreSphere (MeshInstance3D) - center sphere with dynamic color
├── ProgressRing (MeshInstance3D) - TorusMesh showing level progress
├── ScoreLabel (Label3D) - white text, z=1.0, no_depth_test
├── LevelLabel (Label3D) - current level display
├── WorldGroup (Node3D) - rotates on X-axis for flip
│   ├── OrbitRing (MeshInstance3D) - TorusMesh (active ring)
│   ├── InnerRings[] - Array of shrunk TorusMesh (extra lives)
│   ├── CursorPivot (Node3D) - rotates on Z-axis
│   │   └── Cursor (MeshInstance3D) - red chamfer box
│   └── TargetHolder (Node3D) - rotates on Z-axis
│       └── Target (MeshInstance3D) - cylinder stopper
├── AudioPlayers (AudioStreamPlayer nodes)
│   ├── sfx_hit
│   ├── sfx_miss
│   ├── sfx_flip
│   ├── sfx_expand
│   └── sfx_level_complete
└── HUD (CanvasLayer)
    ├── HighScoreLabel
    ├── InstructionLabel
    ├── FailLabel
    └── MuteButton
```

## Key Systems

### Level Progression System
- 100 levels with scaling difficulty
- Hits required per level: `level × 5`
- Progress tracked via `current_hits` and `hits_required`
- Progress ring visual shows completion percentage

```gdscript
var level: int = 1
var current_hits: int = 0
var hits_required: int = 5  # level * 5

func start_level(new_level: int) -> void:
    level = new_level
    current_hits = 0
    hits_required = level * 5
    update_progress_ring()
```

### Progress Ring
- TorusMesh around center sphere
- Updates arc length based on completion percentage
- Full circle (TAU) when level complete

```gdscript
func update_progress_ring() -> void:
    var progress = float(current_hits) / float(hits_required)
    var arc_angle = progress * TAU
    # Rebuild torus mesh with partial arc
```

### Audio System
Pre-generated WAV audio for iOS compatibility (AudioStreamGenerator doesn't work on iOS):

```gdscript
var sample_rate: float = 22050.0
var sound_muted: bool = false

func build_audio() -> void:
    sfx_hit = AudioStreamPlayer.new()
    sfx_hit.stream = generate_tone_wav(440.0, 0.08, 1.3, 0.4)
    sfx_hit.volume_db = -6
    add_child(sfx_hit)
    # Similar for other sound effects...

func generate_tone_wav(freq: float, duration: float, pitch_mult: float, volume: float) -> AudioStreamWAV:
    var samples = int(sample_rate * duration)
    var data = PackedByteArray()
    data.resize(samples * 2)  # 16-bit = 2 bytes per sample

    for i in range(samples):
        var t = float(i) / sample_rate
        var progress = float(i) / float(samples)
        var current_freq = freq * lerp(1.0, pitch_mult, progress)
        var envelope = 1.0 - progress  # Linear fade out
        var sample_value = sin(t * current_freq * TAU) * envelope * volume
        var sample_int = int(clamp(sample_value * 32767.0, -32768.0, 32767.0))
        data[i * 2] = sample_int & 0xFF
        data[i * 2 + 1] = (sample_int >> 8) & 0xFF

    var wav = AudioStreamWAV.new()
    wav.format = AudioStreamWAV.FORMAT_16_BITS
    wav.mix_rate = int(sample_rate)
    wav.stereo = false
    wav.data = data
    return wav

func play_hit_sound() -> void:
    if not sound_muted and sfx_hit:
        sfx_hit.play()
```

### Sound Effect Specifications
| Sound | Base Freq | Duration | Pitch Mult | Description |
|-------|-----------|----------|------------|-------------|
| Hit | 440Hz | 80ms | 1.3x rise | Quick positive tone |
| Miss | 180Hz | 200ms | 0.5x drop | Low negative tone |
| Flip | 600→900Hz | 150ms | sweep | Quick ascending sweep |
| Expand | 300→600Hz | 300ms | sweep | Slow ascending sweep |
| Level Complete | Arpeggio | 500ms | - | C5-E5-G5-C6-E6 |

### Orbit System
- Cursor orbits via Z-axis rotation of `CursorPivot`
- `cursor_angle` tracks position in radians
- `cursor_direction`: +1 = counter-clockwise (angle increases), -1 = clockwise
- Updated each frame: `cursor_angle += cursor_direction * cursor_speed * delta`

### Target Spawning
- Target positioned by rotating `TargetHolder` on Z-axis
- Target placed halfway between center sphere and active ring
- Spawn distance: 72-144 degrees ahead (regular), 45-90 degrees (after flip)
- Target types: regular (turquoise), flip (purple), expand (orange)

### Flip Mechanic
The flip is one of the special target mechanics:

1. **Animation**: `world_group.rotation.x` tweens by PI (180 degrees)
2. **Cursor behavior**: Cursor does NOT reverse direction - just keeps orbiting
3. **Visual effect**: World flips around the cursor like a coin
4. **Post-flip spawn**: Uses opposite spawn direction to account for flipped perspective
5. **Grace period**: 3 seconds before "too slow" detection activates

```gdscript
# Flip only rotates world - cursor continues unchanged
tween.tween_property(world_group, "rotation:x", target_rotation, FLIP_DURATION)
```

### Expansion System
Creates new outer rings, up to 4 total:

1. **Trigger**: Orange target appears every 7-8 hits (if < 4 rings)
2. **Animation**:
   - Current ring shrinks and joins inner_rings array
   - New outer ring created at radius + 0.5
   - Camera zooms out to show new ring
   - Cursor resizes to fill new gap
3. **Inner ring positioning**: Fixed 0.25 unit spacing from center sphere
4. **Grace period**: 2 seconds after expansion completes

```gdscript
# Inner rings positioned concentrically
var target_radius = core_radius + ring_spacing * (i + 1)  # 0.25 spacing
var target_scale = target_radius / DEFAULT_ORBIT_RADIUS
```

### Extra Lives System
Inner rings serve as extra lives:

1. **Trigger**: Player misses while inner_rings.size() > 0
2. **Animation**:
   - Current ring explodes with particles
   - Outermost inner ring zooms to full size
   - Camera zooms back in
   - Remaining inner rings reposition
3. **Cursor**: Resizes for restored radius
4. **Grace period**: 2 seconds after life used

```gdscript
func use_extra_life() -> void:
    var restored_ring = inner_rings.pop_back()
    orbit_ring = restored_ring
    active_radius = DEFAULT_ORBIT_RADIUS
    # Animate restoration...
```

### Level Complete Celebration
When level is completed, all rings spin around the central sphere:

```gdscript
func trigger_level_complete() -> void:
    var spin_tween = create_tween()
    spin_tween.set_parallel(true)

    if orbit_ring:
        var start_rot = orbit_ring.rotation.z
        spin_tween.tween_property(orbit_ring, "rotation:z", start_rot + TAU * 3, 2.0)

    for ring in inner_rings:
        var ring_start = ring.rotation.z
        spin_tween.tween_property(ring, "rotation:z", ring_start + TAU * 3, 2.0)

    play_level_complete_sound()
    # Wait for tap to continue...
```

### Hit Detection
- Compares `cursor_angle` to `target_angle`
- Uses `HIT_THRESHOLD` (0.25 radians, ~14 degrees)
- Handles angle wraparound at TAU boundary

### Too Slow Detection
- Checks if cursor has passed target without hitting
- Compares expected vs actual angle sign based on `cursor_direction`
- Disabled during grace periods (flip, expand, extra life)

## 3D Mesh Resolution

Higher polygon counts for smooth appearance on mobile:

```gdscript
# Core Sphere
core_mesh.radial_segments = 64
core_mesh.rings = 32

# Orbit Ring Torus
ring_mesh.rings = 64
ring_mesh.ring_segments = 24

# Target Cylinder
target_cylinder.radial_segments = 32

# Progress Ring
progress_mesh.rings = 64
progress_mesh.ring_segments = 16
```

## Procedural Mesh Generation

### Chamfer Box (Cursor)
The cursor uses a procedurally generated chamfer box mesh:

```gdscript
func create_chamfer_box(width, height, depth, chamfer) -> ArrayMesh:
    # Creates box with 8 beveled corner edges
    # Front/back faces are octagons
    # 4 flat side faces + 4 chamfer strip faces
```

## State Variables

| Variable | Type | Purpose |
|----------|------|---------|
| `current_state` | GameState | MENU, PLAYING, LEVEL_COMPLETE, GAME_OVER |
| `level` | int | Current level (1-100) |
| `current_hits` | int | Hits in current level |
| `hits_required` | int | Hits needed (level × 5) |
| `cursor_angle` | float | Current position in radians |
| `cursor_direction` | int | +1 or -1 |
| `target_angle` | float | Stopper position in radians |
| `is_flip_target` | bool | Current target is purple |
| `is_expand_target` | bool | Current target is orange |
| `is_flipping` | bool | Flip animation in progress |
| `is_expanding` | bool | Expansion animation in progress |
| `is_using_extra_life` | bool | Extra life transition in progress |
| `world_flipped` | bool | Accumulated flip state (toggles each flip) |
| `spawn_grace_period` | bool | Disables too_slow check |
| `ring_count` | int | Current number of rings (1-4) |
| `active_radius` | float | Current playable ring radius |
| `inner_rings` | Array[MeshInstance3D] | Stored inner ring meshes |
| `inner_ring_materials` | Array[StandardMaterial3D] | Materials for fading |
| `hits_since_last_special` | int | Counter for expansion spawning |
| `sound_muted` | bool | Whether audio is muted |

## Constants

```gdscript
const DEFAULT_ORBIT_RADIUS: float = 2.0
const BASE_SPEED: float = 3.75        # Full speed (radians/sec)
const START_SPEED: float = 1.25       # BASE_SPEED / 3
const HIT_THRESHOLD: float = 0.25     # ~14 degrees
const FLIP_CHANCE: float = 0.25       # 25% purple targets
const FLIP_DURATION: float = 1.5      # Seconds
const HUE_SHIFT_PER_POINT: float = 0.02
const MAX_LEVEL: int = 100
```

## Rendering

- **Renderer**: Mobile (GLES3)
- **Materials**: Mix of shaded and unshaded for depth
- **Camera**: Orthographic projection, size 6.0 (scales with ring expansion)
- **Label3D**: `no_depth_test = true` ensures score always visible
- **Background**: Shader-based gradient (light top, dark bottom)
- **Starting hue**: 0.45 (teal green)

## Persistence

High score saved using `ConfigFile`:
```gdscript
# Save
config.set_value("game", "high_score", high_score)
config.save("user://save.cfg")

# Load
high_score = config.get_value("game", "high_score", 0)
```

## Input Handling

All input types supported:
- `InputEventScreenTouch` - mobile touch
- `InputEventMouseButton` - desktop mouse
- `InputEventKey` (spacebar) - desktop keyboard

Brief input blocking (0.15s) prevents accidental double-taps on state transitions.

## Grace Periods

Multiple grace periods prevent unfair game overs:

| Event | Duration | Blocks |
|-------|----------|--------|
| After flip | 3.0s | too_slow check |
| After expansion | 2.0s | too_slow check |
| After extra life | 2.0s | too_slow check |
| After spawn | 0.8s | too_slow check |
| State transition | 0.15s | all input |

## iOS Export Notes

### Xcode Project Configuration
After exporting from Godot, the Xcode project may need manual fixes:

1. **Device Family**: TARGETED_DEVICE_FAMILY must be "1" for iPhone (Godot may set "2" for iPad)
   ```bash
   sed -i '' 's/TARGETED_DEVICE_FAMILY = "2"/TARGETED_DEVICE_FAMILY = "1"/g' build/OrbitalPop.xcodeproj/project.pbxproj
   ```

2. **Audio**: Uses pre-generated AudioStreamWAV instead of AudioStreamGenerator for iOS compatibility

### Export Settings (export_presets.cfg)
- Bundle ID: `com.werkzenog.orbitalpop`
- Team ID: `XMZZY2J65R`
- Min iOS Version: 14.0
- Target Device: iPhone only (targeted_device_family=1)
