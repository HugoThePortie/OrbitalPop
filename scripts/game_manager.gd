extends Node3D

# Signals
signal score_changed(new_score: int)
signal game_over(reason: String)

# Game state
enum GameState { MENU, LEVEL_SELECT, COUNTDOWN, PLAYING, LEVEL_COMPLETE, GAME_OVER }
var current_state: GameState = GameState.MENU

# Colors - dynamic theme
const COLOR_CURSOR = Color("#ff5252")
const COLOR_TARGET = Color("#33d9b2")
const COLOR_TARGET_FLIP = Color("#9b59b6")
const COLOR_TARGET_EXPAND = Color("#ff9800")  # Orange
const HUE_SHIFT_PER_POINT: float = 0.02  # How much hue shifts per point
const COLOR_ELECTRIC_CYAN = Color("#00E5E5")
const COLOR_HOT_MAGENTA = Color("#FF0066")
const COLOR_FLOPPY_YELLOW = Color("#FFD93D")

# Dynamic color state
var current_hue: float = 0.45  # Start at teal green
var bg_material: ShaderMaterial
var core_material: StandardMaterial3D
var ring_material: StandardMaterial3D

# Gameplay settings
const DEFAULT_ORBIT_RADIUS: float = 2.0  # Reference for reset
const BASE_SPEED: float = 3.75  # radians per second
const START_SPEED: float = 1.75  # Starting speed
const FLIP_CHANCE: float = 0.25
const FLIP_DURATION: float = 1.5

# Speed milestones
const SPEED_MILESTONE_1: int = 10
const SPEED_MILESTONE_2: int = 20
const SPEED_MILESTONE_3: int = 30

# Perfect hit detection
const PERFECT_HIT_RATIO: float = 0.4  # 40% of overlap threshold = "perfect" zone

# Frenzy system
const FRENZY_THRESHOLD: int = 3
const FRENZY_MULTIPLIERS: Array = [1.0, 1.5, 2.0, 3.0, 3.0]

# Geometry constants
const CORE_RADIUS: float = 0.8
const RING_THICKNESS: float = 0.08
const RING_SPACING: float = 0.25
const MAX_RINGS: int = 4

# Cursor dimensions
const CURSOR_WIDTH: float = 0.175
const CURSOR_DEPTH: float = 0.5
const CURSOR_CHAMFER: float = 0.04
const CURSOR_LENGTH_RATIO: float = 0.75

# Target dimensions
const TARGET_RADIUS: float = 0.29
const TARGET_HEIGHT: float = 0.08

# Animation durations
const EXPAND_DURATION: float = 0.8
const RESTORE_DURATION: float = 0.6
const GROW_DURATION: float = 0.2

# Grace periods
const GRACE_AFTER_FLIP: float = 3.0
const GRACE_AFTER_EXPAND: float = 2.0
const GRACE_AFTER_SPAWN: float = 0.8
const INPUT_BLOCK_DURATION: float = 0.5

# Coyote time (post-threshold late-tap buffer)
const COYOTE_WINDOW: float = 0.05  # 50ms (~3 frames at 60fps)

# State
var score: int = 0
var high_score: int = 0
var cursor_speed: float = START_SPEED
var cursor_direction: int = 1  # 1 = counter-clockwise, -1 = clockwise
var cursor_angle: float = 0.0
var target_angle: float = 0.0
var is_flip_target: bool = false
var is_flipping: bool = false
var input_blocked: bool = false
var spawn_grace_period: bool = false
var world_flipped: bool = false  # Tracks if we're in a flipped visual state

# Expansion state
var is_expand_target: bool = false
var is_expanding: bool = false
var is_using_extra_life: bool = false  # Grace period during extra life transition
var _preserve_rings_on_start: bool = false  # Set by advance_to_next_level to keep rings

# Timeout safeguards (in case timer callbacks don't fire on mobile)
var grace_end_time: float = 0.0
var flip_end_time: float = 0.0
var expand_end_time: float = 0.0
var input_block_end_time: float = 0.0
var extra_life_end_time: float = 0.0
var ring_count: int = 1  # Current number of rings (max 4)
var hits_since_last_special: int = 0
var last_hit_was_perfect: bool = false
var level_perfect_hits: int = 0  # Count of perfect hits this level

# Frenzy state
var frenzy_streak: int = 0
var frenzy_multiplier: float = 1.0
var is_frenzy_active: bool = false

# Coyote time state
var _coyote_timer: float = 0.0
var _coyote_title: String = ""
var _coyote_detail: String = ""

# Overdrive state
var _overdrive_active: bool = false
var _overdrive_tween: Tween = null
const OVERDRIVE_THRESHOLD: int = 5
const OVERDRIVE_SLOW_FACTOR: float = 0.9
const OVERDRIVE_SLOW_DURATION: float = 0.5
const OVERDRIVE_RAMP_DURATION: float = 0.3

# Boss mode state
var is_boss_mode: bool = false
var _level_complete_deferred: bool = false
var _boss_tilt_target: float = 0.0
var _boss_defeated: bool = false
var _boss_escaped: bool = false
var boss_hp: int = 0
var boss_max_hp_current: int = 6
var boss_mesh: MeshInstance3D = null
var boss_material: StandardMaterial3D = null
var boss_encounters: int = 0
var boss_frenzy_grace: int = 0
var boss_drift_time: float = 0.0
var boss_anim_timer: float = 0.0
var boss_anim_frame: int = 0
var boss_anim_frames: Array = []
var boss_drift_speed: float = 0.5
var boss_bombs: Array = []
var boss_bomb_timer: float = 0.0
var boss_shield_hp: int = 0
var boss_shield_mesh: MeshInstance3D = null
var boss_shield_material: StandardMaterial3D = null
var boss_hp_segments: Array = []
var boss_hp_segment_materials: Array = []
var boss_original_bg_top: Vector3
var boss_original_bg_bottom: Vector3
var boss_timer: float = 0.0
const BOSS_TIME_LIMIT: float = 20.0
var sfx_boss_siren: AudioStreamPlayer
var sfx_tractor_beam: AudioStreamPlayer
var sfx_boss_escape: AudioStreamPlayer
var sfx_boss_bullet: AudioStreamPlayer
const BOSS_TRIGGER_STREAK: int = 6
const BOSS_MAX_HP: int = 6
const BOSS_TILT_ANGLE: float = deg_to_rad(45)
const BOSS_INVADER_HEIGHT: float = 3.5
const BOSS_BOMB_INTERVAL: float = 2.5
const BOSS_BOMB_SPEED: float = 1.5

# Ghost multiplier (trailing cursor echoes)
var ghost_pivots: Array[Node3D] = []
var ghost_meshes: Array[MeshInstance3D] = []
var ghost_materials: Array[StandardMaterial3D] = []
const GHOST_COUNT: int = 3
const GHOST_ALPHAS: Array = [0.35, 0.2, 0.1]


# Daily challenge state
var is_daily_challenge: bool = false
var daily_rng: RandomNumberGenerator = null
var active_radius: float = DEFAULT_ORBIT_RADIUS  # Changes after expansion
var inner_rings: Array[MeshInstance3D] = []  # All inner rings (decorative)
var inner_ring_materials: Array[StandardMaterial3D] = []  # Materials for inner rings

# Level progression state
var current_level: int = 1
var max_unlocked_level: int = 1
var level_hits: int = 0  # Hits in current level attempt
var hits_required: int = 10  # Level * 10

# Level difficulty config (computed from current_level)
var level_base_speed: float = 2.5
var level_flip_chance: float = 0.0
var level_target_scale: float = 1.0
var expansion_hit_threshold: int = 7  # Hits between expansion targets

# Level select UI references
var level_select_layer: CanvasLayer
var level_buttons: Array[Button] = []
var current_page: int = 0

# Progress ring
var progress_ring: MeshInstance3D
var progress_ring_material: ShaderMaterial

# Node references - will be created in _ready
var world_group: Node3D
var cursor_pivot: Node3D
var cursor_mesh: MeshInstance3D
var target_holder: Node3D
var target_mesh: MeshInstance3D
var core_sphere: MeshInstance3D
var orbit_ring: MeshInstance3D
var camera: Camera3D
var score_label: Label3D
var high_score_label: Label
var instruction_label: Label
var fail_label: Label
var level_label: Label
var progress_label: Label
var streak_arcs: Array[MeshInstance3D] = []
var streak_arc_materials: Array[StandardMaterial3D] = []
var levels_button: Button

# Fonts
var font_bold: Font = null
var font_black: Font = null

# Title
var title_label: Label = null
var title_shader: Shader = null
var title_material: ShaderMaterial = null

# Curved text
var curved_text_node: Node3D = null


# Audio
var sample_rate: float = 22050.0
var sound_muted: bool = false
var mute_button: Button
var sfx_start: AudioStreamPlayer
var sfx_hit: AudioStreamPlayer
var sfx_miss: AudioStreamPlayer
var sfx_flip: AudioStreamPlayer
var sfx_expand: AudioStreamPlayer
var sfx_level_complete: AudioStreamPlayer
var sfx_perfect_hit: AudioStreamPlayer
var bgm_player: AudioStreamPlayer
var bgm_ambient: AudioStreamWAV
var bgm_boss: AudioStreamWAV
var current_bgm: String = "ambient"
const BGM_TRACKS: Array[String] = ["ambient", "boss"]
var _streak_chimes: Array = []

# Floor & background effects
var floor_grid_material: ShaderMaterial
var grid_pulse_material: ShaderMaterial
var radial_glow_material: ShaderMaterial
var floating_particles: GPUParticles2D
var bg_effects_layer: CanvasLayer

# AdMob, Stars & IAP
var admob_manager: Node = null
var star_manager: Node = null
var iap_manager: Node = null
var star_label: Label = null
var out_of_stars_layer: CanvasLayer = null

# UI Themes
var current_ui_theme: String = "vectrex"
const UI_THEMES: Array[String] = ["orbital", "vectrex"]

# Theme color palettes — each returns colors for a given hue
# Vectrex: monochrome green phosphor vector display, no hue shifting
func _theme_colors(theme: String, hue: float) -> Dictionary:
	match theme:
		"vectrex":
			# Monochrome phosphor CRT — single hue, shifts as score increases
			var bright = Color.from_hsv(hue, 0.9, 1.0)    # Full phosphor glow
			var mid = Color.from_hsv(hue, 0.85, 0.75)      # Medium intensity
			var dim = Color.from_hsv(hue, 0.8, 0.5)        # Dim trace
			var faint = Color.from_hsv(hue, 0.7, 0.25)     # Barely visible
			return {
				"bg_top": Color.from_hsv(hue, 0.6, 0.04),
				"bg_bottom": Color(0.0, 0.0, 0.0),
				"core": Color(mid.r, mid.g, mid.b, 0.15),
				"ring": Color(mid.r, mid.g, mid.b, 0.8),
				"inner_ring": Color(dim.r, dim.g, dim.b, 0.25),
				"grid_near": mid,
				"grid_far": dim,
				"grid_glow": Color.from_hsv(hue, 0.75, 0.6),
				"accent": bright,
				"cursor": Color(0.9, 0.9, 0.9),
				"target": bright,
				"target_flip": Color.from_hsv(fmod(hue + 0.15, 1.0), 0.7, 0.85),
				"target_expand": Color.from_hsv(fmod(hue + 0.08, 1.0), 0.8, 0.9),
				"score_color": bright,
				"label_color": Color(bright.r, bright.g, bright.b, 0.9),
				"hue_shift": true,
			}
		_:  # "orbital" — default dynamic hue-shifting theme
			return {
				"bg_top": Color.from_hsv(hue, 0.35, 0.45),
				"bg_bottom": Color.from_hsv(hue, 0.5, 0.08),
				"core": Color(Color.from_hsv(hue, 0.4, 0.85).r, Color.from_hsv(hue, 0.4, 0.85).g, Color.from_hsv(hue, 0.4, 0.85).b, 0.85),
				"ring": Color(Color.from_hsv(hue, 0.35, 0.55).r, Color.from_hsv(hue, 0.35, 0.55).g, Color.from_hsv(hue, 0.35, 0.55).b, 0.8),
				"inner_ring": Color(Color.from_hsv(hue, 0.25, 0.45).r, Color.from_hsv(hue, 0.25, 0.45).g, Color.from_hsv(hue, 0.25, 0.45).b, 0.3),
				"grid_near": Color.from_hsv(hue, 0.8, 1.0),
				"grid_far": Color.from_hsv(fmod(hue + 0.3, 1.0), 0.8, 0.8),
				"grid_glow": Color.from_hsv(hue, 0.6, 1.0),
				"accent": Color.from_hsv(hue, 0.7, 1.0),
				"cursor": COLOR_CURSOR,
				"target": COLOR_TARGET,
				"target_flip": COLOR_TARGET_FLIP,
				"target_expand": COLOR_TARGET_EXPAND,
				"score_color": Color.WHITE,
				"label_color": Color(COLOR_TARGET.r, COLOR_TARGET.g, COLOR_TARGET.b, 0.9),
				"hue_shift": true,
			}

# Trophies
var trophies_unlocked: Dictionary = {}
var trophy_layer: CanvasLayer = null

# Settings & Dev Mode
var dev_mode_enabled: bool = true  # Default ON for development
var settings_layer: CanvasLayer = null
var settings_button: Button = null
var _state_before_pause: GameState = GameState.MENU  # Saved state when pausing

# Vectrex CRT effect state
var game_environment: Environment = null
var scanline_layer: CanvasLayer = null
var scanline_material: ShaderMaterial = null
var _core_is_wireframe: bool = false
var _original_core_mesh: Mesh = null  # Saved solid SphereMesh for restoring

# Create a rounded box mesh with smooth corners
func create_chamfer_box(width: float, height: float, depth: float, chamfer: float) -> ArrayMesh:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var hw = width / 2.0
	var hh = height / 2.0
	var hd = depth / 2.0
	var c = min(chamfer, min(hw, min(hh, hd)) * 0.5)
	var segments = 8  # Subdivisions per corner arc — smooth, no visible faceting

	# Corner arc centers (top-right, top-left, bottom-left, bottom-right)
	var corners = [
		Vector2(hw - c, hh - c),
		Vector2(-hw + c, hh - c),
		Vector2(-hw + c, -hh + c),
		Vector2(hw - c, -hh + c),
	]
	var start_angles = [0.0, PI / 2.0, PI, 3.0 * PI / 2.0]

	# Build 2D cross-section profile and per-vertex outward normals
	var profile: Array[Vector2] = []
	var normals_2d: Array[Vector2] = []
	for ci in range(4):
		for seg in range(segments):
			var angle = start_angles[ci] + (PI / 2.0) * float(seg) / float(segments)
			var dir = Vector2(cos(angle), sin(angle))
			profile.append(corners[ci] + dir * c)
			normals_2d.append(dir)

	var n = profile.size()

	# Front face (Z+) — triangle fan, flat normal
	for i in range(n):
		var ni = (i + 1) % n
		st.set_normal(Vector3(0, 0, 1))
		st.add_vertex(Vector3(0, 0, hd))
		st.add_vertex(Vector3(profile[i].x, profile[i].y, hd))
		st.add_vertex(Vector3(profile[ni].x, profile[ni].y, hd))

	# Back face (Z-) — triangle fan, reversed winding
	for i in range(n):
		var ni = (i + 1) % n
		st.set_normal(Vector3(0, 0, -1))
		st.add_vertex(Vector3(0, 0, -hd))
		st.add_vertex(Vector3(profile[ni].x, profile[ni].y, -hd))
		st.add_vertex(Vector3(profile[i].x, profile[i].y, -hd))

	# Side wall — quads connecting front to back with smooth normals
	for i in range(n):
		var ni = (i + 1) % n
		var f0 = Vector3(profile[i].x, profile[i].y, hd)
		var f1 = Vector3(profile[ni].x, profile[ni].y, hd)
		var b0 = Vector3(profile[i].x, profile[i].y, -hd)
		var b1 = Vector3(profile[ni].x, profile[ni].y, -hd)
		var n0 = Vector3(normals_2d[i].x, normals_2d[i].y, 0)
		var n1 = Vector3(normals_2d[ni].x, normals_2d[ni].y, 0)
		# Triangle 1
		st.set_normal(n0); st.add_vertex(f0)
		st.set_normal(n0); st.add_vertex(b0)
		st.set_normal(n1); st.add_vertex(b1)
		# Triangle 2
		st.set_normal(n0); st.add_vertex(f0)
		st.set_normal(n1); st.add_vertex(b1)
		st.set_normal(n1); st.add_vertex(f1)

	return st.commit()

# Update target appearance based on target type (expand, flip, regular)
var _expand_pulse_overlay: MeshInstance3D = null

func update_target_appearance() -> void:
	if not target_mesh:
		return

	target_mesh.visible = true
	target_mesh.position = Vector3(0, (CORE_RADIUS + active_radius) / 2.0, 0)

	# Scale target up to compensate for camera zoom so it appears the same visual size
	var zoom_factor = (active_radius / DEFAULT_ORBIT_RADIUS) * 1.1
	if zoom_factor < 1.0:
		zoom_factor = 1.0
	var target_scale = Vector3.ONE * zoom_factor

	# Set color on standard material
	var mat = target_mesh.material_override as StandardMaterial3D
	if mat:
		if is_expand_target:
			mat.albedo_color = COLOR_TARGET_EXPAND
		elif is_flip_target:
			mat.albedo_color = COLOR_TARGET_FLIP
		else:
			mat.albedo_color = COLOR_TARGET

	# Clean up old pulse overlay
	if _expand_pulse_overlay and is_instance_valid(_expand_pulse_overlay):
		_expand_pulse_overlay.queue_free()
		_expand_pulse_overlay = null

	# Add animated radiating rings overlay for expand targets
	if is_expand_target:
		_expand_pulse_overlay = MeshInstance3D.new()
		var disc = CylinderMesh.new()
		disc.top_radius = TARGET_RADIUS * 1.05
		disc.bottom_radius = TARGET_RADIUS * 1.05
		disc.height = TARGET_HEIGHT + 0.01
		disc.radial_segments = 32
		_expand_pulse_overlay.mesh = disc

		var shader = Shader.new()
		shader.code = "shader_type spatial;\nrender_mode blend_add, unshaded, cull_disabled;\nuniform float ring_speed = 3.0;\nuniform float ring_count = 4.0;\nvoid fragment() {\n\tvec2 c = UV - vec2(0.5);\n\tfloat d = length(c) * 2.0;\n\tfloat rings = sin((d * ring_count - TIME * ring_speed) * 6.28318) * 0.5 + 0.5;\n\tfloat fade = smoothstep(1.0, 0.3, d);\n\tALBEDO = vec3(1.0, 0.7, 0.2);\n\tALPHA = rings * fade * 0.5;\n}\n"
		var smat = ShaderMaterial.new()
		smat.shader = shader
		smat.set_shader_parameter("ring_speed", 3.0)
		smat.set_shader_parameter("ring_count", 4.0)
		_expand_pulse_overlay.material_override = smat

		_expand_pulse_overlay.position = target_mesh.position
		_expand_pulse_overlay.rotation.x = deg_to_rad(90)
		target_holder.add_child(_expand_pulse_overlay)

	# Coin spin-in: 0.75 rotations while scaling up from nothing
	var spin_in_duration: float = 0.5
	target_mesh.rotation = Vector3(deg_to_rad(90) + TAU * 0.75, 0, 0)
	target_mesh.scale = target_scale * 0.1
	var grow_tween = create_tween()
	grow_tween.set_parallel(true)
	grow_tween.tween_property(target_mesh, "rotation:x", deg_to_rad(90), spin_in_duration).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	grow_tween.tween_property(target_mesh, "scale", target_scale, spin_in_duration).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	if _expand_pulse_overlay and is_instance_valid(_expand_pulse_overlay):
		_expand_pulse_overlay.scale = target_scale * 0.1
		grow_tween.tween_property(_expand_pulse_overlay, "scale", target_scale, spin_in_duration).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)

# Create a ring material with the current theme color
func create_ring_material(alpha: float = 0.8) -> StandardMaterial3D:
	var mat = StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var ring_color = Color.from_hsv(current_hue, 0.35, 0.55)
	ring_color.a = alpha
	mat.albedo_color = ring_color
	mat.metallic = 0.0
	mat.roughness = 1.0
	return mat

# Update cursor mesh and position based on current active_radius
func update_cursor_mesh() -> void:
	var full_gap = active_radius - CORE_RADIUS
	var hand_length = full_gap * CURSOR_LENGTH_RATIO
	cursor_mesh.mesh = create_chamfer_box(CURSOR_WIDTH, hand_length, CURSOR_DEPTH, CURSOR_CHAMFER)
	cursor_mesh.scale = Vector3.ONE
	cursor_mesh.rotation = Vector3.ZERO
	cursor_mesh.position = Vector3(0, (CORE_RADIUS + active_radius) / 2.0, 0)
	# Sync ghost meshes
	for ghost in ghost_meshes:
		ghost.mesh = cursor_mesh.mesh
		ghost.position = cursor_mesh.position

func _ready() -> void:
	current_state = GameState.MENU

	# Load fonts
	font_bold = load("res://fonts/Orbitron-Bold.ttf")
	font_black = load("res://fonts/Orbitron-Black.ttf")

	# Load saved settings (dev mode, etc.)
	_load_settings()

	# Load saved high score
	load_high_score()

	# Build the entire scene programmatically for reliability
	build_scene()

	# Initialize star manager
	_init_star_manager()

	# Initialize IAP manager
	_init_iap_manager()

	# Initialize AdMob
	_init_admob()

	# Sync star display with actual star_manager state
	_update_star_display()

	update_ui()
	update_theme_colors()

func build_scene() -> void:
	# Camera - looking at ring from front (like a clock face)
	camera = Camera3D.new()
	camera.name = "Camera3D"
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.current = true
	camera.size = 9.0
	camera.near = 0.05
	camera.far = 100.0
	camera.position = Vector3(0, 0, 10)  # In front of the ring
	camera.rotation = Vector3.ZERO  # Looking at origin
	add_child(camera)

	# Add lighting for shaded spheres (very soft shadows)
	var light = DirectionalLight3D.new()
	light.name = "MainLight"
	light.rotation = Vector3(deg_to_rad(-30), deg_to_rad(30), 0)
	light.light_energy = 0.3  # Half intensity for softer shadows
	add_child(light)

	# Add stronger ambient light to fill shadows
	var env = Environment.new()
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.6, 0.65)
	env.ambient_light_energy = 0.9
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.04, 0.04, 0.07)  # Very dark for synthwave look
	game_environment = env
	var world_env = WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	# Background quad with gradient
	var bg_quad = MeshInstance3D.new()
	bg_quad.name = "Background"
	var quad_mesh = QuadMesh.new()
	quad_mesh.size = Vector2(20, 30)
	bg_quad.mesh = quad_mesh
	bg_quad.position = Vector3(0, 0, -5)

	var bg_shader = Shader.new()
	bg_shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled;

uniform vec3 color_top : source_color;
uniform vec3 color_bottom : source_color;

void fragment() {
	float gradient = 1.0 - SCREEN_UV.y;
	vec3 col = mix(color_bottom, color_top, gradient);
	// Dither to break up banding on dark gradients
	float noise = fract(sin(dot(FRAGCOORD.xy, vec2(12.9898, 78.233))) * 43758.5453);
	col += (noise - 0.5) / 255.0;
	ALBEDO = col;
}
"""
	bg_material = ShaderMaterial.new()
	bg_material.shader = bg_shader
	var top_color = Color.from_hsv(current_hue, 0.35, 0.45)
	var bottom_color = Color.from_hsv(current_hue, 0.5, 0.08)  # Very dark bottom
	bg_material.set_shader_parameter("color_top", Vector3(top_color.r, top_color.g, top_color.b))
	bg_material.set_shader_parameter("color_bottom", Vector3(bottom_color.r, bottom_color.g, bottom_color.b))
	bg_quad.material_override = bg_material
	add_child(bg_quad)

	# Floor grid (3D plane below the ring, extending to horizon)
	build_floor_grid()

	# Background effects (2D canvas overlays)
	build_background_effects()

	# Scanline overlay for CRT themes (starts hidden)
	_build_scanline_overlay()

	# Core sphere at center (single mesh, splits into clamshell during capture)
	core_sphere = MeshInstance3D.new()
	core_sphere.name = "CoreSphere"
	var core_mesh = SphereMesh.new()
	core_mesh.radius = CORE_RADIUS
	core_mesh.height = CORE_RADIUS * 2
	core_mesh.radial_segments = 96
	core_mesh.rings = 48
	core_sphere.mesh = core_mesh
	core_material = StandardMaterial3D.new()
	core_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var core_color = Color.from_hsv(current_hue, 0.4, 0.85)
	core_color.a = 0.85  # Slightly transparent
	core_material.albedo_color = core_color
	core_material.metallic = 0.0
	core_material.roughness = 1.0  # Fully matte
	core_sphere.material_override = core_material
	_original_core_mesh = core_mesh
	add_child(core_sphere)

	# Streak arc segments — 3 arcs around the hub, slightly larger than core sphere
	_build_streak_arcs()

	# Score label in center of core sphere
	score_label = Label3D.new()
	score_label.name = "ScoreLabel"
	score_label.text = "0"
	score_label.font_size = 140
	score_label.position = Vector3(0, 0, 1.0)
	if font_black:
		score_label.font = font_black  # Heavier weight for clean readability
	elif font_bold:
		score_label.font = font_bold
	score_label.modulate = Color.WHITE
	score_label.outline_modulate = Color(1, 1, 1, 0.3)
	score_label.outline_size = 2
	score_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	score_label.no_depth_test = true  # Always render on top
	score_label.render_priority = 10
	add_child(score_label)  # Add to main node, not core_sphere

	# World group (flips on X axis)
	world_group = Node3D.new()
	world_group.name = "WorldGroup"
	add_child(world_group)

	# Orbit ring (torus in XY plane)
	orbit_ring = MeshInstance3D.new()
	orbit_ring.name = "OrbitRing"
	var ring_mesh = TorusMesh.new()
	ring_mesh.inner_radius = active_radius - RING_THICKNESS
	ring_mesh.outer_radius = active_radius + RING_THICKNESS
	ring_mesh.rings = 128
	ring_mesh.ring_segments = 32
	orbit_ring.mesh = ring_mesh
	# Rotate torus to be in XY plane (facing camera)
	orbit_ring.rotation.x = deg_to_rad(90)
	ring_material = create_ring_material()
	orbit_ring.material_override = ring_material
	world_group.add_child(orbit_ring)

	# Cursor pivot (rotates on Z axis like a clock hand)
	cursor_pivot = Node3D.new()
	cursor_pivot.name = "CursorPivot"
	world_group.add_child(cursor_pivot)

	# Cursor - chamfer box shape (box with beveled edges)
	cursor_mesh = MeshInstance3D.new()
	cursor_mesh.name = "Cursor"
	update_cursor_mesh()
	var cursor_mat = StandardMaterial3D.new()
	cursor_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var cursor_color = COLOR_CURSOR
	cursor_color.a = 0.9
	cursor_mat.albedo_color = cursor_color
	cursor_mat.metallic = 0.0
	cursor_mat.roughness = 1.0  # Fully matte
	cursor_mesh.material_override = cursor_mat
	cursor_pivot.add_child(cursor_mesh)

	# Ghost cursor echoes (visible during frenzy)
	ghost_pivots.clear()
	ghost_meshes.clear()
	ghost_materials.clear()
	for i in range(GHOST_COUNT):
		var gp = Node3D.new()
		gp.name = "GhostPivot%d" % i
		world_group.add_child(gp)
		ghost_pivots.append(gp)
		var gm = MeshInstance3D.new()
		gm.name = "GhostCursor%d" % i
		gm.mesh = cursor_mesh.mesh
		gm.position = cursor_mesh.position
		gm.visible = false
		var gmat = StandardMaterial3D.new()
		gmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		var gc = COLOR_CURSOR
		gc.a = GHOST_ALPHAS[i]
		gmat.albedo_color = gc
		gmat.metallic = 0.0
		gmat.roughness = 1.0
		gm.material_override = gmat
		gp.add_child(gm)
		ghost_meshes.append(gm)
		ghost_materials.append(gmat)

	# Target holder (rotates on Z axis)
	target_holder = Node3D.new()
	target_holder.name = "TargetHolder"
	world_group.add_child(target_holder)

	# Target cylinder (shaded, slightly transparent)
	target_mesh = MeshInstance3D.new()
	target_mesh.name = "Target"
	var target_cylinder = CylinderMesh.new()
	target_cylinder.top_radius = TARGET_RADIUS
	target_cylinder.bottom_radius = TARGET_RADIUS
	target_cylinder.height = TARGET_HEIGHT
	target_cylinder.radial_segments = 32
	target_mesh.mesh = target_cylinder
	target_mesh.position = Vector3(0, (CORE_RADIUS + active_radius) / 2.0, 0)  # Halfway between center sphere and ring
	target_mesh.rotation.x = deg_to_rad(90)  # Flat faces toward camera
	target_mesh.visible = false
	var target_mat = StandardMaterial3D.new()
	target_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var target_color = COLOR_TARGET
	target_color.a = 0.9
	target_mat.albedo_color = target_color
	target_mat.metallic = 0.0
	target_mat.roughness = 1.0  # Fully matte
	target_mesh.material_override = target_mat
	target_holder.add_child(target_mesh)

	# Build progress ring around core
	create_progress_ring()

	# Build HUD
	build_hud()

	# Build level select screen
	build_level_select()

	# Build audio system
	build_audio()


func build_floor_grid() -> void:
	var floor_grid = MeshInstance3D.new()
	floor_grid.name = "FloorGrid"
	var quad = QuadMesh.new()
	quad.size = Vector2(1200, 15000)
	floor_grid.mesh = quad
	# Position below the ring, laid flat, extending into distance
	floor_grid.position = Vector3(0, -4.5, -7000.0)
	floor_grid.rotation.x = -PI / 2

	var floor_shader = Shader.new()
	floor_shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;

uniform vec3 near_color : source_color = vec3(0.0, 0.94, 1.0);
uniform vec3 far_color : source_color = vec3(0.4, 0.0, 1.0);
uniform float grid_spacing : hint_range(0.2, 2.0) = 0.8;
uniform float line_width : hint_range(0.01, 0.15) = 0.04;
uniform float grid_opacity : hint_range(0.0, 1.0) = 0.9;

uniform float glow_intensity : hint_range(0.0, 3.0) = 0.3;
uniform vec3 glow_color : source_color = vec3(0.0, 0.94, 1.0);

varying vec3 world_vertex;

void vertex() {
	world_vertex = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 pos = world_vertex.xz;

	// Grid lines from world position
	vec2 grid_pos = pos / grid_spacing;
	vec2 grid_fract = abs(fract(grid_pos - 0.5) - 0.5);
	vec2 grid_deriv = fwidth(grid_pos);
	vec2 line_aa = grid_fract / grid_deriv;
	float line = min(line_aa.x, line_aa.y);
	float grid_alpha = 1.0 - clamp(line - line_width * 10.0, 0.0, 1.0);

	// Distance fade
	float dist_from_center = length(pos) / 6000.0;
	float fade = 1.0 - smoothstep(0.5, 1.0, dist_from_center);

	// Horizon fade based on screen position
	float screen_y = SCREEN_UV.y;
	float back_fade = smoothstep(0.55, 0.62, screen_y);

	// Gradient from near to far
	float depth_blend = 1.0 - smoothstep(0.55, 0.62, screen_y);
	vec3 grid_color = mix(near_color, far_color, depth_blend);

	// Intensity fade toward horizon
	float intensity_fade = 1.0 - (1.0 - smoothstep(0.55, 0.62, screen_y)) * 0.95;

	// Core glow reflection on floor
	float glow_dist = length(pos) / 3.0;
	float glow_falloff = exp(-glow_dist * glow_dist * 0.5);
	float ambient_glow = glow_falloff * glow_intensity;
	vec3 final_color = grid_color + glow_color * ambient_glow;
	float glow_alpha_boost = ambient_glow * 0.5;

	ALBEDO = final_color;
	ALPHA = clamp(grid_alpha * fade * back_fade * intensity_fade * grid_opacity + glow_alpha_boost, 0.0, 1.0);
}
"""
	floor_grid_material = ShaderMaterial.new()
	floor_grid_material.shader = floor_shader
	# Use hue-based colors for the floor grid
	var near_col = Color.from_hsv(current_hue, 0.8, 1.0)  # Bright saturated
	var far_col = Color.from_hsv(fmod(current_hue + 0.3, 1.0), 0.8, 0.8)  # Shifted hue
	floor_grid_material.set_shader_parameter("near_color", Vector3(near_col.r, near_col.g, near_col.b))
	floor_grid_material.set_shader_parameter("far_color", Vector3(far_col.r, far_col.g, far_col.b))
	floor_grid_material.set_shader_parameter("grid_spacing", 0.8)
	floor_grid_material.set_shader_parameter("line_width", 0.04)
	floor_grid_material.set_shader_parameter("grid_opacity", 0.9)
	var glow_col = Color.from_hsv(current_hue, 0.6, 1.0)
	floor_grid_material.set_shader_parameter("glow_color", Vector3(glow_col.r, glow_col.g, glow_col.b))
	floor_grid_material.set_shader_parameter("glow_intensity", 0.3)
	floor_grid.material_override = floor_grid_material
	add_child(floor_grid)

func build_background_effects() -> void:
	bg_effects_layer = CanvasLayer.new()
	bg_effects_layer.name = "BackgroundEffects"
	bg_effects_layer.layer = 0  # Behind HUD
	add_child(bg_effects_layer)

	# Animated grid overlay
	var grid = ColorRect.new()
	grid.name = "GridOverlay"
	grid.set_anchors_preset(Control.PRESET_FULL_RECT)
	grid_pulse_material = ShaderMaterial.new()
	grid_pulse_material.shader = preload("res://shaders/grid_pulse.gdshader")
	var accent = Color.from_hsv(current_hue, 0.7, 1.0)
	grid_pulse_material.set_shader_parameter("line_color", Vector3(accent.r, accent.g, accent.b))
	grid_pulse_material.set_shader_parameter("line_opacity", 0.025)
	grid.material = grid_pulse_material
	bg_effects_layer.add_child(grid)

	# Radial glow behind core sphere
	var core_glow = ColorRect.new()
	core_glow.name = "CoreGlow"
	core_glow.size = Vector2(300, 300)
	core_glow.position = Vector2(45, 230)  # Centered behind game area
	radial_glow_material = ShaderMaterial.new()
	radial_glow_material.shader = preload("res://shaders/radial_glow.gdshader")
	radial_glow_material.set_shader_parameter("glow_color", Vector3(accent.r, accent.g, accent.b))
	radial_glow_material.set_shader_parameter("base_opacity", 0.12)
	core_glow.material = radial_glow_material
	bg_effects_layer.add_child(core_glow)

	# Floating particles rising from bottom
	floating_particles = GPUParticles2D.new()
	floating_particles.name = "FloatingParticles"
	floating_particles.amount = 60
	floating_particles.lifetime = 8.0
	floating_particles.preprocess = 4.0
	floating_particles.position = Vector2(195, 864)

	var pmat = ParticleProcessMaterial.new()
	pmat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pmat.emission_box_extents = Vector3(150, 1, 1)
	pmat.direction = Vector3(0, -1, 0)
	pmat.spread = 0.0
	pmat.initial_velocity_min = 300.0
	pmat.initial_velocity_max = 500.0
	pmat.gravity = Vector3.ZERO
	pmat.linear_accel_min = -25.0
	pmat.linear_accel_max = 25.0
	pmat.scale_min = 1.0
	pmat.scale_max = 1.0

	# Color gradient (fade in/out with hue-matched color)
	var gradient = Gradient.new()
	gradient.set_color(0, Color(accent.r, accent.g, accent.b, 0.0))
	gradient.add_point(0.1, Color(accent.r, accent.g, accent.b, 0.8))
	gradient.add_point(0.9, Color(accent.r, accent.g, accent.b, 0.8))
	gradient.set_color(gradient.get_point_count() - 1, Color(accent.r, accent.g, accent.b, 0.0))
	var grad_tex = GradientTexture1D.new()
	grad_tex.gradient = gradient
	pmat.color_ramp = grad_tex

	floating_particles.process_material = pmat

	# Small streak texture (1x5 pixel)
	var img = Image.create(1, 5, false, Image.FORMAT_RGBA8)
	for y in range(5):
		var alpha = 1.0
		if y == 0 or y == 4:
			alpha = 0.5
		img.set_pixel(0, y, Color(1, 1, 1, alpha))
	var tex = ImageTexture.create_from_image(img)
	floating_particles.texture = tex

	bg_effects_layer.add_child(floating_particles)

	# Bottom glow
	var bottom_glow = ColorRect.new()
	bottom_glow.name = "BottomGlow"
	bottom_glow.size = Vector2(390, 150)
	bottom_glow.position = Vector2(0, 694)
	var bottom_mat = ShaderMaterial.new()
	bottom_mat.shader = preload("res://shaders/bottom_glow.gdshader")
	bottom_mat.set_shader_parameter("glow_color", Vector3(accent.r, accent.g, accent.b))
	bottom_glow.material = bottom_mat
	bg_effects_layer.add_child(bottom_glow)

func build_hud() -> void:
	var hud = CanvasLayer.new()
	hud.name = "HUD"
	add_child(hud)

	# High score label
	# Best score with crown (top-right, above star count)
	high_score_label = Label.new()
	high_score_label.name = "HighScoreLabel"
	high_score_label.text = "👑 0"
	high_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	high_score_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	high_score_label.anchor_left = 1.0
	high_score_label.anchor_right = 1.0
	high_score_label.offset_left = -120
	high_score_label.offset_right = -20
	high_score_label.offset_top = 60
	high_score_label.offset_bottom = 90
	high_score_label.add_theme_font_size_override("font_size", 20)
	if font_bold:
		high_score_label.add_theme_font_override("font", font_bold)
	high_score_label.add_theme_color_override("font_color", Color(1.0, 0.84, 0.0, 0.8))
	high_score_label.visible = false
	hud.add_child(high_score_label)

	# Instruction label
	instruction_label = Label.new()
	instruction_label.name = "InstructionLabel"
	instruction_label.text = "TAP TO START"
	instruction_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	instruction_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	instruction_label.anchor_left = 0.5
	instruction_label.anchor_right = 0.5
	instruction_label.anchor_top = 1.0
	instruction_label.anchor_bottom = 1.0
	instruction_label.offset_left = -150
	instruction_label.offset_right = 150
	instruction_label.offset_top = -150
	instruction_label.offset_bottom = -100
	instruction_label.add_theme_font_size_override("font_size", 28)
	if font_black:
		instruction_label.add_theme_font_override("font", font_black)
	instruction_label.visible = false  # Hidden by default; curved text replaces it
	hud.add_child(instruction_label)

	# Fail label
	fail_label = Label.new()
	fail_label.name = "FailLabel"
	fail_label.text = "MISSED!"
	fail_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	fail_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	fail_label.anchor_left = 0.5
	fail_label.anchor_right = 0.5
	fail_label.anchor_top = 0.5
	fail_label.anchor_bottom = 0.5
	fail_label.offset_left = -150
	fail_label.offset_right = 150
	fail_label.offset_top = -50
	fail_label.offset_bottom = 50
	fail_label.visible = false
	fail_label.add_theme_font_size_override("font_size", 36)
	if font_black:
		fail_label.add_theme_font_override("font", font_black)
	fail_label.add_theme_color_override("font_color", COLOR_HOT_MAGENTA)
	hud.add_child(fail_label)

	# Game title (centered across rings, 80% screen width, visible on menu only)
	title_label = Label.new()
	title_label.name = "TitleLabel"
	title_label.text = "ORBITAL POP"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_label.anchor_left = 0.1
	title_label.anchor_right = 0.9
	title_label.anchor_top = 0.5
	title_label.anchor_bottom = 0.5
	title_label.offset_left = 0
	title_label.offset_right = 0
	title_label.offset_top = -30
	title_label.offset_bottom = 30
	title_label.add_theme_font_size_override("font_size", 42)
	if font_black:
		title_label.add_theme_font_override("font", font_black)
	title_label.add_theme_color_override("font_color", Color.WHITE)
	title_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	title_label.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	title_label.clip_text = false
	title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Apply animated gradient shader
	title_shader = load("res://shaders/gradient_text.gdshader")
	title_material = ShaderMaterial.new()
	title_material.shader = title_shader
	title_label.material = title_material
	title_label.visible = false
	hud.add_child(title_label)

	# Level label (top center)
	level_label = Label.new()
	level_label.name = "LevelLabel"
	level_label.text = "LEVEL 1"
	level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	level_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	level_label.anchor_left = 1.0
	level_label.anchor_right = 1.0
	level_label.offset_left = -160
	level_label.offset_right = -20
	level_label.offset_top = 55
	level_label.offset_bottom = 80
	level_label.add_theme_font_size_override("font_size", 24)
	if font_bold:
		level_label.add_theme_font_override("font", font_bold)
	level_label.add_theme_color_override("font_color", Color(0.0, 0.9, 0.9, 0.95))
	hud.add_child(level_label)

	# Progress label (below level label, centered)
	progress_label = Label.new()
	progress_label.name = "ProgressLabel"
	progress_label.text = "0 / 10"
	progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	progress_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	progress_label.anchor_left = 0.5
	progress_label.anchor_right = 0.5
	progress_label.offset_left = -80
	progress_label.offset_right = 80
	progress_label.offset_top = 90
	progress_label.offset_bottom = 115
	progress_label.add_theme_font_size_override("font_size", 16)
	if font_bold:
		progress_label.add_theme_font_override("font", font_bold)
	progress_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.5))
	hud.add_child(progress_label)

	# Levels button (top right, only visible in menu)
	levels_button = Button.new()
	levels_button.name = "LevelsButton"
	levels_button.text = "LEVELS"
	levels_button.anchor_left = 1.0
	levels_button.anchor_right = 1.0
	levels_button.offset_left = -100
	levels_button.offset_right = -20
	levels_button.offset_top = 60
	levels_button.offset_bottom = 100
	levels_button.add_theme_font_size_override("font_size", 18)
	if font_bold:
		levels_button.add_theme_font_override("font", font_bold)
	levels_button.pressed.connect(func(): show_level_select())
	levels_button.visible = false
	hud.add_child(levels_button)

	# Star display (top right, below best score)
	var star_container = HBoxContainer.new()
	star_container.name = "StarContainer"
	star_container.anchor_left = 1.0
	star_container.anchor_right = 1.0
	star_container.offset_left = -90
	star_container.offset_right = -20
	star_container.offset_top = 82
	star_container.offset_bottom = 110
	hud.add_child(star_container)

	var star_icon = Label.new()
	star_icon.text = "★"
	star_icon.add_theme_font_size_override("font_size", 24)
	star_icon.add_theme_color_override("font_color", Color(1.0, 0.84, 0.0))
	star_container.add_child(star_icon)

	star_label = Label.new()
	star_label.name = "StarLabel"
	star_label.text = str(star_manager.stars) if star_manager else "0"
	star_label.add_theme_font_size_override("font_size", 24)
	if font_bold:
		star_label.add_theme_font_override("font", font_bold)
	star_label.add_theme_color_override("font_color", Color(1.0, 0.84, 0.0))
	star_container.add_child(star_label)

	# Menu button (top-left, visible hamburger icon)
	settings_button = Button.new()
	settings_button.name = "SettingsButton"
	settings_button.text = "☰"
	settings_button.offset_left = 12
	settings_button.offset_right = 62
	settings_button.offset_top = 55
	settings_button.offset_bottom = 105
	settings_button.flat = false
	settings_button.add_theme_font_size_override("font_size", 32)
	settings_button.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
	settings_button.add_theme_color_override("font_hover_color", Color.WHITE)
	# Semi-transparent background for visibility
	var menu_style = StyleBoxFlat.new()
	menu_style.bg_color = Color(1, 1, 1, 0.1)
	menu_style.corner_radius_top_left = 8
	menu_style.corner_radius_top_right = 8
	menu_style.corner_radius_bottom_left = 8
	menu_style.corner_radius_bottom_right = 8
	settings_button.add_theme_stylebox_override("normal", menu_style)
	var menu_style_hover = menu_style.duplicate()
	menu_style_hover.bg_color = Color(1, 1, 1, 0.2)
	settings_button.add_theme_stylebox_override("hover", menu_style_hover)
	settings_button.add_theme_stylebox_override("pressed", menu_style_hover)
	settings_button.pressed.connect(func(): _show_settings())
	hud.add_child(settings_button)

func _process(delta: float) -> void:
	# Don't tick safeguard timers while paused (any overlay open)
	var is_paused = settings_layer or trophy_layer or _trophy_inspect_layer or out_of_stars_layer
	if is_paused:
		# Only tick trophy inspect rotation, nothing else
		if _trophy_inspect_mesh and is_instance_valid(_trophy_inspect_mesh):
			_trophy_inspect_mesh.rotation.y += _trophy_spin_velocity_y * delta
			for child in _trophy_inspect_mesh.get_children():
				child.rotation.x += _trophy_spin_velocity_x * delta
				child.rotation.x = clampf(child.rotation.x, -PI / 2.0, PI / 2.0)
			_trophy_spin_velocity_y *= 0.98
			_trophy_spin_velocity_x *= 0.95
		return

	# Safeguard: Reset stuck states based on time (in case timer callbacks don't fire)
	var current_time = Time.get_ticks_msec() / 1000.0
	if input_blocked and current_time > input_block_end_time:
		input_blocked = false
	if spawn_grace_period and current_time > grace_end_time:
		spawn_grace_period = false
	if is_flipping and current_time > flip_end_time:
		is_flipping = false
	if is_expanding and current_time > expand_end_time:
		is_expanding = false
	if is_using_extra_life and current_time > extra_life_end_time:
		is_using_extra_life = false

	if current_state == GameState.PLAYING:
		# Move cursor around the ring (Z-axis rotation)
		cursor_angle += cursor_direction * cursor_speed * delta
		cursor_angle = fmod(cursor_angle, TAU)
		if cursor_angle < 0:
			cursor_angle += TAU

		# Update cursor pivot rotation
		cursor_pivot.rotation.z = cursor_angle

		# Ghost cursor echoes (trailing during frenzy) — lerp for inertia
		if is_frenzy_active and ghost_meshes.size() == GHOST_COUNT:
			var speed_factor = 0.08 + cursor_speed * 0.02
			for i in range(GHOST_COUNT):
				ghost_meshes[i].visible = true
				var target_z = cursor_angle - cursor_direction * (i + 1) * speed_factor
				# Lerp with decreasing responsiveness for each trail
				var lerp_speed = 12.0 / (i + 1)  # 12, 6, 4 — further ghosts lag more
				ghost_pivots[i].rotation.z = lerp_angle(ghost_pivots[i].rotation.z, target_z, clampf(lerp_speed * delta, 0.0, 1.0))
		else:
			for i in range(ghost_meshes.size()):
				ghost_meshes[i].visible = false
				# Reset ghost positions to cursor so they don't pop on next activation
				if i < ghost_pivots.size():
					ghost_pivots[i].rotation.z = cursor_angle

		# Boss mode: movement, bombs, HP bar tracking
		if is_boss_mode:
			_update_boss(delta)
		elif boss_hp_segments.size() > 0:
			# Safety: clean up stale HP bar if boss mode ended
			_clear_boss_hp_bar()

		# Check if cursor passed target (too slow)
		if not is_flipping and not is_expanding and not is_using_extra_life:
			check_too_slow()

		# Coyote time: decrement timer, fire game over when expired
		if _coyote_timer > 0.0 and not is_boss_mode:
			_coyote_timer -= delta
			if _coyote_timer <= 0.0:
				_coyote_timer = 0.0
				_show_miss_text("MISSED!")
				end_game(_coyote_title, _coyote_detail)

	# Trophy inspect rotation handled in paused block above

func _input(event: InputEvent) -> void:
	if input_blocked:
		return

	# Block game input when any overlay is open
	if settings_layer or trophy_layer or _trophy_inspect_layer or out_of_stars_layer:
		return
	if level_select_layer and level_select_layer.visible:
		return

	# Handle touch
	if event is InputEventScreenTouch:
		if event.pressed:
			handle_tap()
	# Handle mouse (for desktop testing)
	elif event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			handle_tap()
	# Handle spacebar
	elif event is InputEventKey:
		if event.pressed and event.keycode == KEY_SPACE:
			handle_tap()

func _is_free_play() -> bool:
	return dev_mode_enabled or (iap_manager and iap_manager.is_ads_disabled())

func handle_tap() -> void:
	match current_state:
		GameState.MENU:
			block_input_briefly()
			if not _is_free_play() and star_manager and not star_manager.has_stars():
				show_out_of_stars_modal()
			else:
				start_game()
		GameState.PLAYING:
			attempt_hit()
		GameState.LEVEL_COMPLETE:
			block_input_briefly()
			advance_to_next_level()
		GameState.GAME_OVER:
			block_input_briefly()
			if not _is_free_play() and star_manager and not star_manager.has_stars():
				show_out_of_stars_modal()
			else:
				restart_game()

func block_input_briefly() -> void:
	input_blocked = true
	input_block_end_time = Time.get_ticks_msec() / 1000.0 + INPUT_BLOCK_DURATION + 0.1
	get_tree().create_timer(INPUT_BLOCK_DURATION).timeout.connect(func(): input_blocked = false)

func setup_level(level: int) -> void:
	current_level = level
	level_hits = 0
	hits_required = level * 10  # Level 1 = 10 hits, Level 2 = 20 hits, etc.

	# Base speed by tier (PRD section 3.1)
	if level <= 10:
		level_base_speed = 2.5
	elif level <= 30:
		level_base_speed = 3.0
	elif level <= 60:
		level_base_speed = 3.5
	elif level <= 90:
		level_base_speed = 4.0
	else:
		level_base_speed = 4.5

	# Flip chance by tier (PRD section 3.2)
	if level <= 5:
		level_flip_chance = 0.0
	elif level <= 20:
		level_flip_chance = 0.15
	elif level <= 50:
		level_flip_chance = 0.25
	else:
		level_flip_chance = 0.35

	# Target size — uniform across all levels (scales with ring count in update_target_appearance)
	level_target_scale = 1.0

	# Expansion rarity - appears early so extra life system is meaningful
	if level <= 20:
		expansion_hit_threshold = 3
	elif level <= 50:
		expansion_hit_threshold = 5
	else:
		expansion_hit_threshold = 7

	cursor_speed = level_base_speed

func start_game() -> void:
	# Setup level configuration
	setup_level(current_level)
	score = maxi(hits_required - level_hits, 0)  # Countdown display, never negative
	cursor_direction = 1
	cursor_angle = -PI / 2  # Start at bottom (6 o'clock)
	is_flipping = false

	# Reset expansion state
	is_expand_target = false
	is_expanding = false
	is_using_extra_life = false
	hits_since_last_special = 0

	# Reset perfect/frenzy state
	last_hit_was_perfect = false
	level_perfect_hits = 0
	_break_frenzy_streak()
	_coyote_timer = 0.0
	_overdrive_active = false
	boss_frenzy_grace = 0
	_level_complete_deferred = false
	if not _preserve_rings_on_start:
		boss_encounters = 0
	if _overdrive_tween and _overdrive_tween.is_valid():
		_overdrive_tween.kill()
	_overdrive_tween = null

	# Daily seed RNG
	if is_daily_challenge:
		daily_rng = RandomNumberGenerator.new()
		daily_rng.seed = get_daily_seed()
	else:
		daily_rng = null

	# If we have inner rings (preserved from level advance), keep them
	if _preserve_rings_on_start:
		_preserve_rings_on_start = false
		ring_count = 1 + inner_rings.size()
		active_radius = DEFAULT_ORBIT_RADIUS + (ring_count - 1) * 0.5
	else:
		# Fresh start — clean up extra rings
		if inner_rings.size() > 0:
			orbit_ring.queue_free()
			orbit_ring = inner_rings[0]
			orbit_ring.scale = Vector3.ONE
			ring_material = inner_ring_materials[0]
			if ring_material:
				var ring_color = ring_material.albedo_color
				ring_color.a = 0.8
				ring_material.albedo_color = ring_color
			for i in range(1, inner_rings.size()):
				inner_rings[i].queue_free()
			inner_rings.clear()
			inner_ring_materials.clear()
		ring_count = 1
		active_radius = DEFAULT_ORBIT_RADIUS

	# Reset camera zoom to match current ring count
	if camera:
		var cam_size = 9.0
		if ring_count > 1:
			cam_size = 9.0 * (active_radius / DEFAULT_ORBIT_RADIUS) * 1.1
		camera.size = cam_size
		camera.position = Vector3(0, 0, 10)

	# Reset cursor size and position for default radius
	update_cursor_mesh()
	if cursor_mesh:
		cursor_mesh.visible = true

	# Reset theme colors
	update_theme_colors()

	# Reset world rotation
	world_group.rotation.x = 0

	cursor_pivot.rotation.z = cursor_angle

	# Reset flipped state
	world_flipped = false

	# Reset progress ring
	if progress_ring_material:
		progress_ring_material.set_shader_parameter("progress", 0.0)

	spawn_target()

	# Start countdown before gameplay begins
	_start_countdown()

func _start_countdown() -> void:
	current_state = GameState.COUNTDOWN
	input_blocked = true
	play_start_sound()

	# Hide instruction label during countdown
	if instruction_label:
		instruction_label.visible = false
	if fail_label:
		fail_label.visible = false

	# Show "3" on score label
	_pump_score("3")
	update_ui()

	# Countdown sequence: 3 -> 2 -> 1 -> GO
	get_tree().create_timer(1.0).timeout.connect(func():
		if current_state != GameState.COUNTDOWN:
			return
		_pump_score("2")
	)
	get_tree().create_timer(2.0).timeout.connect(func():
		if current_state != GameState.COUNTDOWN:
			return
		_pump_score("1")
	)
	get_tree().create_timer(3.0).timeout.connect(func():
		if current_state != GameState.COUNTDOWN:
			return
		# Transition to playing
		current_state = GameState.PLAYING
		input_blocked = false
		_pump_score(str(hits_required - level_hits))
		update_ui()
		score_changed.emit(score)
	)

func spawn_target(after_flip: bool = false, grace_override: float = 0.0) -> void:
	# Clean up any expand pulse overlay from previous target
	if _expand_pulse_overlay and is_instance_valid(_expand_pulse_overlay):
		_expand_pulse_overlay.queue_free()
		_expand_pulse_overlay = null
	# Normalize cursor angle first
	var normalized_cursor = fmod(cursor_angle, TAU)
	if normalized_cursor < 0:
		normalized_cursor += TAU

	# Determine spawn distance based on context
	var ahead_angle: float
	if after_flip:
		if daily_rng:
			ahead_angle = daily_rng.randf_range(PI * 0.25, PI * 0.5)
		else:
			ahead_angle = randf_range(PI * 0.25, PI * 0.5)  # 45-90 degrees
	else:
		if daily_rng:
			ahead_angle = daily_rng.randf_range(PI * 0.4, PI * 0.8)
		else:
			ahead_angle = randf_range(PI * 0.4, PI * 0.8)   # 72-144 degrees

	# Calculate target position
	# After flip: spawn opposite of cursor_direction (visual direction is inverted)
	# Normal: spawn in cursor_direction
	var direction_multiplier = -cursor_direction if after_flip else cursor_direction
	target_angle = normalized_cursor + (direction_multiplier * ahead_angle)

	# Normalize target angle to [0, TAU)
	target_angle = fmod(target_angle, TAU)
	if target_angle < 0:
		target_angle += TAU

	# Determine target type (expand, flip, or regular)
	# No flips or expands during boss mode — ring must stay stable at 45 degrees
	is_flip_target = false
	is_expand_target = false
	if not is_boss_mode:
		if ring_count < MAX_RINGS and hits_since_last_special >= expansion_hit_threshold:
			is_expand_target = true
		elif (daily_rng.randf() if daily_rng else randf()) < level_flip_chance:
			is_flip_target = true

	# Position target and update appearance
	target_holder.rotation.z = target_angle
	update_target_appearance()

	# Set grace period (longer after flip or expansion)
	spawn_grace_period = true
	var grace_time: float
	if grace_override > 0.0:
		grace_time = grace_override
	elif after_flip:
		grace_time = GRACE_AFTER_FLIP
	else:
		grace_time = GRACE_AFTER_SPAWN
	grace_end_time = Time.get_ticks_msec() / 1000.0 + grace_time + 0.1
	get_tree().create_timer(grace_time).timeout.connect(func(): spawn_grace_period = false)

	# Overdrive: brief speed dip on target spawn during streak 5+
	if _overdrive_active:
		if _overdrive_tween and _overdrive_tween.is_valid():
			_overdrive_tween.kill()
		var pre_slow_speed = cursor_speed
		cursor_speed *= OVERDRIVE_SLOW_FACTOR
		_overdrive_tween = create_tween()
		_overdrive_tween.tween_interval(OVERDRIVE_SLOW_DURATION)
		_overdrive_tween.tween_property(self, "cursor_speed", pre_slow_speed, OVERDRIVE_RAMP_DURATION)\
			.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)

func get_overlap_threshold() -> float:
	# Exact pixel-contact threshold: scrubber and stopper edges just touching
	var midpoint = (CORE_RADIUS + active_radius) / 2.0
	var stopper_half_angle = TARGET_RADIUS / midpoint
	var cursor_half_angle = (CURSOR_WIDTH / 2.0) / midpoint
	return stopper_half_angle + cursor_half_angle

func attempt_hit() -> void:
	if is_flipping or is_expanding or is_using_extra_life:
		return

	# Coyote time: if timer is active, accept as a standard hit
	if _coyote_timer > 0.0:
		_coyote_timer = 0.0
		last_hit_was_perfect = false
		on_target_hit()
		return

	# Calculate angle difference
	var diff = abs(cursor_angle - target_angle)
	if diff > PI:
		diff = TAU - diff

	var threshold = get_overlap_threshold()
	var perfect_ratio = PERFECT_HIT_RATIO * 2.0 if dev_mode_enabled else PERFECT_HIT_RATIO
	var perfect_threshold = threshold * perfect_ratio
	if diff < perfect_threshold:
		# PERFECT HIT!
		last_hit_was_perfect = true
		on_target_hit()
	elif diff < threshold:
		# Regular hit
		last_hit_was_perfect = false
		on_target_hit()
	elif spawn_grace_period:
		# During grace period, ignore misses — the target just spawned
		# and the player may be tapping from the previous hit's momentum
		pass
	else:
		# Early/bad tap — consume a ring or end the game
		_break_frenzy_streak()
		_show_miss_text("TOO EARLY!")
		end_game("MISSED!", "Tapped too early")

func check_too_slow() -> void:
	if current_state != GameState.PLAYING:
		return
	# Boss mode: misses are free — just respawn target, no penalty
	if is_boss_mode:
		return
	# Skip check during grace period after spawn
	if spawn_grace_period:
		return

	# Check if cursor has passed the target
	var angle_to_target = target_angle - cursor_angle
	if angle_to_target > PI:
		angle_to_target -= TAU
	elif angle_to_target < -PI:
		angle_to_target += TAU

	# If moving counter-clockwise (direction=1), target should be ahead (positive angle)
	# If moving clockwise (direction=-1), target should be ahead (negative angle)
	# cursor_direction already accounts for flip (reversed in do_flip), so use directly
	var expected_sign = cursor_direction
	var actual_sign = sign(angle_to_target)

	# If we've passed the target by more than the overlap threshold
	var _too_slow_threshold = get_overlap_threshold()
	if actual_sign != expected_sign and abs(angle_to_target) > _too_slow_threshold:
		# Already in coyote window — don't restart it
		if _coyote_timer > 0.0:
			return
		var title: String
		var detail: String
		if is_expand_target:
			title = "MISSED EXPAND!"
			detail = "The expansion stopper slipped past"
		elif world_flipped or is_flip_target:
			title = "FLIPPED OUT!"
			detail = "Missed after the ring flipped direction"
		elif cursor_speed >= BASE_SPEED:
			title = "TOO FAST!"
			detail = "Couldn't keep up with the speed"
		else:
			title = "MISSED!"
			detail = "The cursor passed the stopper"
		# Start coyote timer instead of immediate game over
		_coyote_timer = COYOTE_WINDOW
		_coyote_title = title
		_coyote_detail = detail

func on_target_hit() -> void:
	# Play appropriate hit sound + haptics
	if last_hit_was_perfect:
		play_perfect_hit_sound()
		haptic_double()
		level_perfect_hits += 1
		# Level hits only count outside boss mode
		if not is_boss_mode:
			level_hits += 1
			level_hits = mini(level_hits, hits_required)
		# Frenzy streak builds on perfects
		frenzy_streak += 1
		var mult_idx = mini(frenzy_streak, FRENZY_MULTIPLIERS.size() - 1)
		frenzy_multiplier = FRENZY_MULTIPLIERS[mult_idx]
		if frenzy_streak >= FRENZY_THRESHOLD and not is_frenzy_active:
			_activate_frenzy()
		if frenzy_streak >= OVERDRIVE_THRESHOLD and not _overdrive_active:
			_activate_overdrive()
		if frenzy_streak >= BOSS_TRIGGER_STREAK and not is_boss_mode:
			_activate_boss_mode()
		# Visual feedback: white flash on core sphere + "PERFECT" text
		_flash_core_white()
		_show_perfect_text()
		# Spawn bubble (visual only, no bonus hits — perfect counts as single hit)
		if not is_boss_mode:
			_spawn_streak_bubble(0)
		_update_streak_bar()
		update_progress_ring()
	else:
		play_hit_sound()
		haptic_light()
		# Level hits only count outside boss mode
		if not is_boss_mode:
			level_hits += 1
		# Regular hit breaks frenzy streak
		_break_frenzy_streak()

	hits_since_last_special += 1

	# During boss mode, freeze the level counter display
	if not is_boss_mode:
		score = maxi(hits_required - level_hits, 0)
		score_changed.emit(score)
		_pump_score(str(score))
		if progress_label:
			progress_label.text = str(level_hits) + " / " + str(hits_required)

		# Check level completion — defer if perfect streak is building toward boss
		if level_hits >= hits_required:
			if frenzy_streak > 0 and frenzy_streak < BOSS_TRIGGER_STREAK:
				# Perfect streak active — defer to let boss mode trigger
				_level_complete_deferred = true
			else:
				trigger_level_complete()
				return

	# Update theme colors
	update_theme_colors()

	# Speed increase within level (gradual ramp to level_base_speed * 1.5)
	var progress = float(level_hits) / float(hits_required)
	cursor_speed = level_base_speed * (1.0 + progress * 0.5)

	# Coin spin + explosion effect
	spawn_explosion(target_mesh.global_position)
	_spin_target_away()

	# Boss mode: fire bullet at invader — damage applied on bullet arrival
	if is_boss_mode and boss_mesh and is_instance_valid(boss_mesh):
		var is_perfect = last_hit_was_perfect
		var damage = 2 if is_perfect else 1
		_fire_boss_bullet(func():
			if not is_instance_valid(self):
				return
			if boss_shield_hp > 0:
				_damage_boss_shield()
				if is_perfect and boss_shield_hp > 0:
					_damage_boss_shield()  # Double damage on perfect
			else:
				boss_hp -= damage
				_flash_boss_hit()
				_update_boss_hp_bar()
				if boss_hp <= 0:
					_defeat_boss()
		, is_perfect)

	# Handle expand, flip, or reverse direction (no flips/expands during boss mode)
	if is_expand_target and not is_boss_mode:
		do_expand()
	elif is_flip_target and not is_boss_mode:
		do_flip()
	else:
		cursor_direction *= -1
		spawn_target()

	update_ui()

func do_flip() -> void:
	play_flip_sound()
	is_flipping = true
	flip_end_time = Time.get_ticks_msec() / 1000.0 + FLIP_DURATION + 1.0  # Extra buffer
	# Hide target during flip
	if target_mesh:
		target_mesh.visible = false
	var tween = create_tween()
	tween.set_parallel(true)
	var target_rotation = world_group.rotation.x + PI
	# Don't move cursor - just flip the world around it
	# The cursor stays at the same angle, continuing in the same direction
	tween.tween_property(world_group, "rotation:x", target_rotation, FLIP_DURATION)

	# Inner rings flip in the opposite direction
	# Since they're children of world_group, counter-rotate by -2*PI to achieve opposite flip
	for ring in inner_rings:
		var ring_target = ring.rotation.x - TAU  # -2*PI to flip opposite
		tween.tween_property(ring, "rotation:x", ring_target, FLIP_DURATION)

	tween.set_parallel(false)
	tween.tween_callback(func():
		if current_state != GameState.PLAYING:
			return
		# Toggle flipped state
		world_flipped = not world_flipped

		# Wait then spawn target ahead
		get_tree().create_timer(0.5).timeout.connect(func():
			if current_state != GameState.PLAYING:
				return
			is_flipping = false
			spawn_target(true)  # after_flip = true
		)
	)

func get_collapsed_ring_radius(ring_index: int) -> float:
	# Tight packing: each ring sits just outside the previous with a small gap
	var gap = 0.06  # Pixels of spacing between rings
	var first_ring_radius = CORE_RADIUS + RING_THICKNESS + gap
	return first_ring_radius + ring_index * (RING_THICKNESS * 2.0 + gap)

func _create_curved_text(text: String, radius: float, arc_degrees: float, color: Color) -> Node3D:
	var container = Node3D.new()
	container.name = "CurvedText"
	var chars = text.length()
	if chars == 0:
		return container
	var arc_rad = deg_to_rad(arc_degrees)
	var angle_per_char = arc_rad / max(chars - 1, 1)
	var start_angle = deg_to_rad(270.0) - arc_rad / 2.0  # Center at bottom (270°)
	for ci in range(chars):
		var ch = text[ci]
		if ch == " ":
			continue
		var angle = start_angle + ci * angle_per_char
		var lbl = Label3D.new()
		lbl.text = ch
		lbl.font_size = 64
		lbl.pixel_size = 0.01
		if font_black:
			lbl.font = font_black
		lbl.modulate = Color(color.r, color.g, color.b, 0.5)
		lbl.outline_modulate = Color(0, 0, 0, 0.2)
		lbl.outline_size = 4
		lbl.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		lbl.no_depth_test = true
		lbl.render_priority = 10
		lbl.position = Vector3(cos(angle) * radius, sin(angle) * radius, 0.5)
		# Rotate so text follows the arc (upright at bottom)
		lbl.rotation.z = angle - deg_to_rad(270.0)
		container.add_child(lbl)
	return container

var _curved_text_tween: Tween = null

func _show_curved_text(text: String) -> void:
	_hide_curved_text()
	var tc = _theme_colors(current_ui_theme, current_hue)
	var text_color: Color = tc["accent"] if current_ui_theme == "vectrex" else Color.WHITE
	curved_text_node = _create_curved_text(text, CORE_RADIUS + 0.55, 260.0, text_color)
	add_child(curved_text_node)
	# Slow continuous rotation around the hub
	_curved_text_tween = create_tween()
	_curved_text_tween.set_loops()
	_curved_text_tween.tween_property(curved_text_node, "rotation:z", TAU, 12.0).from(0.0)

func _hide_curved_text() -> void:
	if _curved_text_tween and _curved_text_tween.is_valid():
		_curved_text_tween.kill()
		_curved_text_tween = null
	if curved_text_node and is_instance_valid(curved_text_node):
		curved_text_node.queue_free()
		curved_text_node = null

func do_expand() -> void:
	play_expand_sound()
	is_expanding = true
	expand_end_time = Time.get_ticks_msec() / 1000.0 + EXPAND_DURATION + 1.0  # Extra buffer
	ring_count += 1
	hits_since_last_special = 0

	# Hide target during expansion
	if target_mesh:
		target_mesh.visible = false

	# Store current ring as an inner ring
	inner_rings.append(orbit_ring)
	inner_ring_materials.append(ring_material)

	# Calculate new outer radius (each ring adds 0.5 to the radius)
	var new_radius = active_radius + 0.5
	var shrink_scale = 0.4  # Each inner ring shrinks to 40% (closer to center sphere)

	# Create new outer ring
	var outer_ring = MeshInstance3D.new()
	outer_ring.name = "OuterRing"
	var outer_ring_mesh = TorusMesh.new()
	outer_ring_mesh.inner_radius = new_radius - RING_THICKNESS
	outer_ring_mesh.outer_radius = new_radius + RING_THICKNESS
	outer_ring_mesh.rings = 128
	outer_ring_mesh.ring_segments = 32
	outer_ring.mesh = outer_ring_mesh
	outer_ring.rotation.x = deg_to_rad(90)

	# New ring material
	ring_material = create_ring_material()
	outer_ring.material_override = ring_material

	# Add outer ring to world group
	world_group.add_child(outer_ring)
	orbit_ring = outer_ring

	# Update active radius for new gameplay
	active_radius = new_radius

	# Apply current theme to the new ring (Vectrex needs emission/unshaded)
	update_theme_colors()

	# Show "RING ADDED!" floating up from above the ring
	_show_ring_added_text()

	# Animate all inner rings to concentric positions around center sphere
	var shrink_tween = create_tween()
	shrink_tween.set_parallel(true)
	var num_inner = inner_rings.size()
	for i in range(num_inner):
		var ring = inner_rings[i]
		var mat = inner_ring_materials[i]
		# Tight packing from core outward - thin collapsed rings
		# Ring 0 (oldest) is closest to core
		var target_radius = get_collapsed_ring_radius(i)
		var original_radius = DEFAULT_ORBIT_RADIUS  # All rings started at this radius
		var target_scale = target_radius / original_radius
		shrink_tween.tween_property(ring, "scale", Vector3(target_scale, target_scale, target_scale), 0.8).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		# Keep inner rings visible — slight fade for depth, but clearly readable
		if mat:
			var faded_color = mat.albedo_color
			faded_color.a = 0.7  # All inner rings clearly visible
			shrink_tween.tween_property(mat, "albedo_color", faded_color, 0.8)

	# Zoom camera out to show the entire new ring
	var new_camera_size = 9.0 * (new_radius / DEFAULT_ORBIT_RADIUS) * 1.1  # Scale up with some padding
	var camera_tween = create_tween()
	camera_tween.tween_property(camera, "size", new_camera_size, EXPAND_DURATION).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)

	# Resize and reposition cursor for new radius
	var new_cursor_pos = Vector3(0, (CORE_RADIUS + active_radius) / 2.0, 0)
	update_cursor_mesh()

	# Animate cursor to new position
	var cursor_tween = create_tween()
	cursor_tween.tween_property(cursor_mesh, "position", new_cursor_pos, 0.5).set_ease(Tween.EASE_OUT)

	# Reverse direction and spawn new target after animation
	cursor_direction *= -1
	get_tree().create_timer(EXPAND_DURATION).timeout.connect(func():
		if current_state != GameState.PLAYING:
			return
		is_expanding = false
		spawn_target(false, GRACE_AFTER_EXPAND * (1.0 + 0.15 * (ring_count - 1)))
	)

func trigger_level_complete() -> void:
	# Never interrupt boss mode — defer instead
	if is_boss_mode:
		_level_complete_deferred = true
		return
	play_level_complete_sound()
	current_state = GameState.LEVEL_COMPLETE
	update_ui()
	# Block input so the tap that triggered the final hit doesn't also advance the level
	input_blocked = true
	input_block_end_time = Time.get_ticks_msec() / 1000.0 + 1.5
	get_tree().create_timer(1.5).timeout.connect(func(): input_blocked = false)

	# Unlock next level
	if current_level < 100:
		max_unlocked_level = max(max_unlocked_level, current_level + 1)

	# Frenzy star bonus: 1 bonus star (doubled if frenzy active)
	if star_manager:
		var bonus = 2 if is_frenzy_active else 1
		star_manager.stars = mini(star_manager.stars + bonus, star_manager.MAX_STARS)
		star_manager.save_star_state()
		star_manager.stars_changed.emit(star_manager.stars)
		_update_star_display()

	# Complete daily challenge if active
	if is_daily_challenge and star_manager:
		star_manager.complete_daily_challenge()

	# End boss mode if active
	if is_boss_mode:
		_end_boss_mode()

	# Reset frenzy state
	_break_frenzy_streak()

	save_progress()

	# Spin target away
	_spin_target_away()

	# Visual celebration - gold glow on core
	if core_material:
		var gold = Color(1.0, 0.84, 0.0)
		gold.a = 0.9
		var celebrate_tween = create_tween()
		celebrate_tween.tween_property(core_material, "albedo_color", gold, 0.3)

	# Spawn celebratory particles
	spawn_level_complete_particles()

	# Hide cursor during celebration
	if cursor_mesh:
		cursor_mesh.visible = false

	# Celebrate with spinning rings - rotate all rings around the sphere
	var spin_tween = create_tween()
	spin_tween.set_parallel(true)

	# Spin the main orbit ring (3 full rotations over 2 seconds)
	if orbit_ring:
		var start_rot = orbit_ring.rotation.z
		spin_tween.tween_property(orbit_ring, "rotation:z", start_rot + TAU * 3, 2.0).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)

	# Spin inner rings in alternating directions
	for i in range(inner_rings.size()):
		var ring = inner_rings[i]
		var start_rot_inner = ring.rotation.z
		var direction = 1 if i % 2 == 0 else -1
		var rotations = 3 + i  # Inner rings spin more
		spin_tween.tween_property(ring, "rotation:z", start_rot_inner + TAU * rotations * direction, 2.0).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)

	# Slide-up success message — positioned above the main ring
	if fail_label:
		var msg = "LEVEL " + str(current_level) + " COMPLETE!"
		if level_perfect_hits >= hits_required:
			msg += "\nPERFECT STREAK!"
		elif level_perfect_hits > 0:
			msg += "\n" + str(level_perfect_hits) + " PERFECT HITS"
		fail_label.text = msg
		fail_label.add_theme_font_size_override("font_size", 26)
		fail_label.add_theme_color_override("font_color", Color(1.0, 0.84, 0.0))  # Gold
		# Position above the orbit ring
		var ring_top_world = Vector3(0, active_radius + 0.3, 0)
		var ring_top_screen = camera.unproject_position(ring_top_world)
		fail_label.anchor_top = 0.0
		fail_label.anchor_bottom = 0.0
		fail_label.offset_top = ring_top_screen.y - 90
		fail_label.offset_bottom = ring_top_screen.y
		fail_label.visible = true
		fail_label.modulate.a = 0.0
		fail_label.position.y += 60  # Start below final position
		var slide_tween = create_tween()
		slide_tween.set_parallel(true)
		slide_tween.tween_property(fail_label, "modulate:a", 1.0, 0.3).set_ease(Tween.EASE_OUT)
		slide_tween.tween_property(fail_label, "position:y", fail_label.position.y - 60, 0.5).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)

	# Level label stays fixed in upper right
	_position_level_label()

	# Show "TAP TO CONTINUE" after slide-up completes
	if instruction_label:
		instruction_label.visible = false
	get_tree().create_timer(0.6).timeout.connect(func():
		if current_state == GameState.LEVEL_COMPLETE:
			_show_curved_text("TAP TO CONTINUE")
	)

	# Wait for user tap to continue (no auto-advance)

func advance_to_next_level() -> void:
	if current_level < 100:
		current_level += 1
	# Preserve earned rings into the next level
	_preserve_rings_on_start = true

	# Reset fail label to default state
	_reset_fail_label()

	# Start next level
	setup_level(current_level)
	start_game()

func spawn_level_complete_particles() -> void:
	# Golden burst from center
	var gold = Color(1.0, 0.84, 0.0)
	for i in range(40):
		var particle = MeshInstance3D.new()
		var sphere = SphereMesh.new()
		sphere.radius = 0.1 * randf_range(0.8, 1.5)
		sphere.height = sphere.radius * 2
		particle.mesh = sphere

		var mat = StandardMaterial3D.new()
		mat.albedo_color = gold
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		particle.material_override = mat

		add_child(particle)
		particle.position = Vector3.ZERO

		# Burst outward in all directions
		var angle = (TAU / 40.0) * i + randf_range(-0.2, 0.2)
		var distance = randf_range(2.0, 4.0)
		var dir = Vector3(cos(angle), sin(angle), randf_range(-0.5, 0.5)) * distance

		var tween = create_tween()
		tween.set_parallel(true)
		tween.tween_property(particle, "position", dir, 0.8).set_ease(Tween.EASE_OUT)
		tween.tween_property(particle, "scale", Vector3.ZERO, 0.8).set_ease(Tween.EASE_IN)
		tween.tween_property(mat, "albedo_color:a", 0.0, 0.8)
		tween.set_parallel(false)
		tween.tween_callback(particle.queue_free)

func update_progress_ring() -> void:
	if progress_ring_material:
		var progress = clampf(float(frenzy_streak) / float(FRENZY_THRESHOLD), 0.0, 1.0)
		progress_ring_material.set_shader_parameter("progress", progress)

func create_progress_ring() -> void:
	# Create progress ring mesh around core sphere
	progress_ring = MeshInstance3D.new()
	progress_ring.name = "ProgressRing"
	var ring_mesh = TorusMesh.new()
	ring_mesh.inner_radius = CORE_RADIUS + 0.02
	ring_mesh.outer_radius = CORE_RADIUS + 0.12
	ring_mesh.rings = 128
	ring_mesh.ring_segments = 32
	progress_ring.mesh = ring_mesh
	progress_ring.rotation.x = deg_to_rad(90)  # Face camera

	# Create shader for partial arc rendering
	var shader = Shader.new()
	shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled;

uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform vec3 fill_color : source_color = vec3(1.0, 0.84, 0.0);
uniform vec3 empty_color : source_color = vec3(0.3, 0.3, 0.3);
uniform float alpha : hint_range(0.0, 1.0) = 0.8;

void fragment() {
	// Calculate angle from UV (torus UVs wrap around)
	float angle = UV.x;  // 0 to 1 around the ring

	// Fill from bottom (0.5) going clockwise
	float fill_start = 0.5;
	float fill_end = fill_start + progress;

	// Normalize angle check
	float adjusted_angle = angle;
	if (adjusted_angle < fill_start) {
		adjusted_angle += 1.0;
	}

	if (adjusted_angle <= fill_end) {
		ALBEDO = fill_color;
		ALPHA = alpha;
	} else {
		ALBEDO = empty_color;
		ALPHA = alpha * 0.3;
	}
}
"""

	progress_ring_material = ShaderMaterial.new()
	progress_ring_material.shader = shader
	progress_ring_material.set_shader_parameter("progress", 0.0)
	progress_ring_material.set_shader_parameter("fill_color", Vector3(1.0, 0.84, 0.0))  # Gold
	progress_ring_material.set_shader_parameter("empty_color", Vector3(0.3, 0.3, 0.3))
	progress_ring_material.set_shader_parameter("alpha", 0.8)

	progress_ring.material_override = progress_ring_material
	add_child(progress_ring)

func _spin_target_away() -> void:
	# Clean up expand pulse overlay
	if _expand_pulse_overlay and is_instance_valid(_expand_pulse_overlay):
		_expand_pulse_overlay.queue_free()
		_expand_pulse_overlay = null
	if not target_mesh or not target_mesh.material_override:
		return
	# Duplicate the live target into a standalone holder (same structure as target_holder)
	var spin_holder = Node3D.new()
	spin_holder.name = "SpinHolder"
	world_group.add_child(spin_holder)
	spin_holder.rotation.z = target_holder.rotation.z  # Same angle on ring

	var spinner = target_mesh.duplicate() as MeshInstance3D
	spin_holder.add_child(spinner)
	spinner.position = target_mesh.position
	spinner.rotation = Vector3(deg_to_rad(90), 0, 0)  # Clean starting rotation
	spinner.scale = target_mesh.scale
	spinner.visible = true

	# Duplicate material for independent fade
	var mat = (target_mesh.material_override as StandardMaterial3D).duplicate() as StandardMaterial3D
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	spinner.material_override = mat

	target_mesh.visible = false

	# Reverse of animate-on: spin -0.75 rotations on X + shrink to zero
	var spin_duration: float = 0.5
	var spin_tween = create_tween()
	spin_tween.set_parallel(true)
	spin_tween.tween_property(spinner, "rotation:x", deg_to_rad(90) - TAU * 0.75, spin_duration).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_SINE)
	spin_tween.tween_property(spinner, "scale", Vector3.ZERO, spin_duration).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_BACK)
	spin_tween.set_parallel(false)
	spin_tween.set_parallel(false)
	spin_tween.tween_callback(func():
		if is_instance_valid(spin_holder):
			spin_holder.queue_free()
	)
	# Safety cleanup
	get_tree().create_timer(spin_duration + 0.5).timeout.connect(func():
		if is_instance_valid(spin_holder):
			spin_holder.queue_free()
	)

func spawn_explosion(pos: Vector3) -> void:
	# More particles and bigger effect for special targets
	var particle_count: int
	var base_size: float
	var explosion_color: Color
	var duration: float
	var spread: float

	if is_expand_target:
		particle_count = 30
		base_size = 0.14
		explosion_color = COLOR_TARGET_EXPAND
		duration = 0.7
		spread = 3.0
	elif is_flip_target:
		particle_count = 24
		base_size = 0.12
		explosion_color = COLOR_TARGET_FLIP
		duration = 0.6
		spread = 2.5
	else:
		particle_count = 12
		base_size = 0.08
		explosion_color = COLOR_TARGET
		duration = 0.4
		spread = 1.5

	for i in range(particle_count):
		var particle = MeshInstance3D.new()
		var sphere = SphereMesh.new()
		sphere.radius = base_size * randf_range(0.8, 1.2)
		sphere.height = sphere.radius * 2
		particle.mesh = sphere

		var mat = StandardMaterial3D.new()
		mat.albedo_color = explosion_color
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		particle.material_override = mat

		add_child(particle)
		particle.global_position = pos

		# Random direction in XY plane
		var angle = (TAU / particle_count) * i + randf_range(-0.3, 0.3)
		var distance = randf_range(0.5, spread)
		var dir = Vector3(cos(angle), sin(angle), randf_range(-0.3, 0.3)) * distance

		# Animate outward, scale down, and fade
		var tween = create_tween()
		tween.set_parallel(true)
		tween.tween_property(particle, "position", particle.position + dir, duration).set_ease(Tween.EASE_OUT)
		tween.tween_property(particle, "scale", Vector3.ZERO, duration).set_ease(Tween.EASE_IN)
		tween.tween_property(mat, "albedo_color:a", 0.0, duration)
		tween.set_parallel(false)
		tween.tween_callback(particle.queue_free)

	# Extra ring burst for special targets
	if is_flip_target:
		spawn_ring_burst(pos, COLOR_TARGET_FLIP)
	elif is_expand_target:
		spawn_ring_burst(pos, COLOR_TARGET_EXPAND)

func spawn_ring_burst(pos: Vector3, burst_color: Color = COLOR_TARGET_FLIP) -> void:
	# Expanding ring effect for special targets
	var ring = MeshInstance3D.new()
	var torus = TorusMesh.new()
	torus.inner_radius = 0.1
	torus.outer_radius = 0.15
	torus.rings = 64
	torus.ring_segments = 24
	ring.mesh = torus
	ring.rotation.x = deg_to_rad(90)  # Face camera

	var mat = StandardMaterial3D.new()
	mat.albedo_color = burst_color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring.material_override = mat

	add_child(ring)
	ring.global_position = pos

	# Expand and fade
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(ring, "scale", Vector3(8, 8, 8), 0.5).set_ease(Tween.EASE_OUT)
	tween.tween_property(mat, "albedo_color:a", 0.0, 0.5)
	tween.set_parallel(false)
	tween.tween_callback(ring.queue_free)

func pulse_score() -> void:
	if score_label:
		var tween = create_tween()
		tween.tween_property(score_label, "scale", Vector3(1.3, 1.3, 1.3), 0.1)
		tween.tween_property(score_label, "scale", Vector3.ONE, 0.1)

func spawn_ring_explosion() -> void:
	# Explode particles along the active ring circumference
	var particle_count = 32
	var ring_color = ring_material.albedo_color if ring_material else COLOR_CURSOR

	for i in range(particle_count):
		var angle = (TAU / particle_count) * i
		var pos = Vector3(cos(angle) * active_radius, sin(angle) * active_radius, 0)

		var particle = MeshInstance3D.new()
		var sphere = SphereMesh.new()
		sphere.radius = 0.1
		sphere.height = 0.2
		particle.mesh = sphere

		var mat = StandardMaterial3D.new()
		mat.albedo_color = ring_color
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		particle.material_override = mat

		add_child(particle)
		particle.position = pos

		# Animate outward from ring and fade
		var outward_dir = Vector3(cos(angle), sin(angle), randf_range(-0.2, 0.2))
		var target_pos = pos + outward_dir * 1.5

		var tween = create_tween()
		tween.set_parallel(true)
		tween.tween_property(particle, "position", target_pos, 0.5).set_ease(Tween.EASE_OUT)
		tween.tween_property(particle, "scale", Vector3.ZERO, 0.5).set_ease(Tween.EASE_IN)
		tween.tween_property(mat, "albedo_color:a", 0.0, 0.5)
		tween.set_parallel(false)
		tween.tween_callback(particle.queue_free)

func use_extra_life() -> void:
	# Pause gameplay during ring collapse (prevents check_too_slow from firing)
	current_state = GameState.COUNTDOWN  # Cursor stops moving
	is_using_extra_life = true
	extra_life_end_time = Time.get_ticks_msec() / 1000.0 + 3.0
	input_blocked = true

	# Play miss sound to indicate a ring was consumed
	play_miss_sound()
	_show_miss_text("MISSED!")
	get_tree().create_timer(0.25).timeout.connect(func():
		if is_instance_valid(self):
			_show_miss_text("RING LOST!")
	)

	# Hide the missed target
	if target_mesh:
		target_mesh.visible = false

	# Explode the current outer ring
	spawn_ring_explosion()

	# Remove the current active (outer) ring
	if is_instance_valid(orbit_ring):
		orbit_ring.queue_free()

	# Pop the outermost inner ring and make it the new active ring
	var restored_ring = inner_rings.pop_back()
	var restored_material = inner_ring_materials.pop_back()

	if not is_instance_valid(restored_ring):
		# Ring was freed somehow — fall through to game over
		current_state = GameState.PLAYING
		inner_rings.clear()
		inner_ring_materials.clear()
		ring_count = 1
		end_game("MISSED!", "Ring lost")
		return

	orbit_ring = restored_ring
	ring_material = restored_material
	ring_count -= 1

	# Calculate the new active radius based on remaining ring count
	active_radius = DEFAULT_ORBIT_RADIUS + (ring_count - 1) * 0.5

	# Screen shake to indicate ring loss
	shake_camera()

	# Animate restored ring to full active size
	var restore_tween = create_tween()
	restore_tween.set_parallel(true)

	restore_tween.tween_property(orbit_ring, "scale", Vector3.ONE, 0.6).set_ease(Tween.EASE_OUT)

	if ring_material:
		var full_color = ring_material.albedo_color
		full_color.a = 0.8
		restore_tween.tween_property(ring_material, "albedo_color", full_color, 0.6)

	# Zoom camera to match the new ring count
	var new_camera_size = 9.0
	if ring_count > 1:
		new_camera_size = 9.0 * (active_radius / DEFAULT_ORBIT_RADIUS) * 1.1
	restore_tween.tween_property(camera, "size", new_camera_size, 0.6).set_ease(Tween.EASE_OUT)

	# Reposition remaining inner rings (tight packing from core outward)
	for i in range(inner_rings.size()):
		var ring = inner_rings[i]
		if is_instance_valid(ring):
			var target_radius = get_collapsed_ring_radius(i)
			var target_scale = target_radius / DEFAULT_ORBIT_RADIUS
			restore_tween.tween_property(ring, "scale", Vector3(target_scale, target_scale, target_scale), 0.6)

	# Resize cursor for restored radius
	var new_cursor_pos = Vector3(0, (CORE_RADIUS + active_radius) / 2.0, 0)
	update_cursor_mesh()

	restore_tween.tween_property(cursor_mesh, "position", new_cursor_pos, RESTORE_DURATION)

	# After animation, resume gameplay
	restore_tween.set_parallel(false)
	restore_tween.tween_callback(_resume_after_extra_life)

	# Safety fallback: if tween callback doesn't fire, resume after 2 seconds
	get_tree().create_timer(2.0).timeout.connect(func():
		if not is_instance_valid(self):
			return
		if current_state == GameState.COUNTDOWN and is_using_extra_life:
			_resume_after_extra_life()
	)

func _resume_after_extra_life() -> void:
	if not is_instance_valid(self):
		return
	if current_state != GameState.COUNTDOWN:
		return
	current_state = GameState.PLAYING
	cursor_direction *= -1
	spawn_target(false, GRACE_AFTER_EXPAND * (1.0 + 0.15 * (ring_count - 1)))
	input_blocked = false
	is_using_extra_life = false

func end_game(title: String, detail: String = "") -> void:
	# Prevent double game-over calls
	if current_state == GameState.GAME_OVER:
		return
	# Prevent end_game during extra life transition
	if current_state == GameState.COUNTDOWN:
		return

	# Check if we have extra lives (inner rings)
	# Validate that the rings are still valid instances
	var valid_rings: int = 0
	for ring in inner_rings:
		if is_instance_valid(ring):
			valid_rings += 1
	if valid_rings > 0:
		use_extra_life()
		return

	# Play miss sound + heavy haptic
	play_miss_sound()
	haptic_heavy()

	current_state = GameState.GAME_OVER
	is_flipping = false
	is_expanding = false
	is_using_extra_life = false

	# End boss mode if active
	if is_boss_mode:
		_end_boss_mode()

	# Reset frenzy
	_break_frenzy_streak()

	# Check for new high score
	if score > high_score:
		high_score = score
		save_high_score()

	# Change target to red to show missed stopper
	if target_mesh:
		var mat = target_mesh.material_override as StandardMaterial3D
		if mat:
			var red_color = COLOR_CURSOR  # Red color
			red_color.a = 0.9
			mat.albedo_color = red_color

	# Show GAME OVER with animated gradient
	if fail_label:
		fail_label.text = "GAME OVER"
		fail_label.add_theme_font_size_override("font_size", 36)
		fail_label.add_theme_color_override("font_color", Color.WHITE)
		fail_label.anchor_left = 0.1
		fail_label.anchor_right = 0.9
		fail_label.anchor_top = 0.5
		fail_label.anchor_bottom = 0.5
		fail_label.offset_left = 0
		fail_label.offset_right = 0
		fail_label.offset_top = -30
		fail_label.offset_bottom = 30
		if title_shader:
			var go_mat = ShaderMaterial.new()
			go_mat.shader = title_shader
			fail_label.material = go_mat
		fail_label.visible = true

	# Consume a star on game over (skip in free play)
	if not _is_free_play() and star_manager:
		star_manager.consume_star()
		_update_star_display()

	# Screen shake
	shake_camera()

	update_ui()
	game_over.emit(title)

func _show_toast(message: String, duration: float = 2.5) -> void:
	var toast = Label.new()
	toast.text = message
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	toast.anchor_left = 0.5
	toast.anchor_right = 0.5
	toast.anchor_top = 1.0
	toast.anchor_bottom = 1.0
	toast.offset_left = -200
	toast.offset_right = 200
	toast.offset_top = -200
	toast.offset_bottom = -160
	toast.add_theme_font_size_override("font_size", 18)
	if font_bold:
		toast.add_theme_font_override("font", font_bold)
	toast.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.8))
	toast.modulate.a = 0.0
	fail_label.get_parent().add_child(toast)

	# Fade in
	var tween = create_tween()
	tween.tween_property(toast, "modulate:a", 1.0, 0.2)
	# Hold
	tween.tween_interval(duration)
	# Fade out
	tween.tween_property(toast, "modulate:a", 0.0, 0.3)
	tween.tween_callback(toast.queue_free)

func shake_camera() -> void:
	if not camera:
		return
	var original_pos = camera.position
	var tween = create_tween()
	for i in range(6):
		var offset = Vector3(randf_range(-0.15, 0.15), randf_range(-0.15, 0.15), 0)
		tween.tween_property(camera, "position", original_pos + offset, 0.05)
	tween.tween_property(camera, "position", original_pos, 0.05)

func _position_level_label() -> void:
	# Fixed position in upper right — no longer tracks ring
	if not level_label:
		return
	level_label.offset_top = 55
	level_label.offset_bottom = 80

func _reset_fail_label() -> void:
	if fail_label:
		fail_label.material = null
		fail_label.add_theme_color_override("font_color", COLOR_HOT_MAGENTA)
		fail_label.add_theme_font_size_override("font_size", 36)
		fail_label.anchor_left = 0.5
		fail_label.anchor_right = 0.5
		fail_label.anchor_top = 0.5
		fail_label.anchor_bottom = 0.5
		fail_label.offset_left = -150
		fail_label.offset_right = 150
		fail_label.offset_top = -50
		fail_label.offset_bottom = 50
		fail_label.visible = false

func restart_game() -> void:
	_hide_curved_text()
	_reset_fail_label()
	start_game()

func update_ui() -> void:
	match current_state:
		GameState.MENU:
			if title_label:
				title_label.visible = true
			if score_label:
				score_label.visible = false
			if instruction_label:
				instruction_label.visible = false
			_show_curved_text("TAP TO START")
			if fail_label:
				fail_label.visible = false
			if level_label:
				level_label.visible = false
			if progress_label:
				progress_label.visible = false
			if levels_button:
				levels_button.visible = false
		GameState.LEVEL_SELECT:
			if levels_button:
				levels_button.visible = false
		GameState.COUNTDOWN:
			if title_label:
				title_label.visible = false
			if score_label:
				score_label.visible = true
			if instruction_label:
				instruction_label.visible = false
			_hide_curved_text()
			if fail_label:
				fail_label.visible = false
			_pump_level("LEVEL " + str(current_level))
			if level_label:
				level_label.visible = true
			_position_level_label()
			if progress_label:
				progress_label.visible = false
			if levels_button:
				levels_button.visible = false
		GameState.PLAYING:
			if score_label:
				score_label.visible = true
			if instruction_label:
				instruction_label.visible = false
			_hide_curved_text()
			_pump_score(str(hits_required - level_hits))
			if fail_label:
				fail_label.visible = false
			_pump_level("LEVEL " + str(current_level))
			if level_label:
				level_label.visible = true
			_position_level_label()
			if progress_label:
				progress_label.visible = false
			if levels_button:
				levels_button.visible = false
		GameState.LEVEL_COMPLETE:
			# Hide 3D score label so it doesn't overlap curved text
			if score_label:
				score_label.visible = false
			if level_label:
				level_label.visible = true
			_position_level_label()
			if progress_label:
				progress_label.visible = false
			if levels_button:
				levels_button.visible = false
		GameState.GAME_OVER:
			if score_label:
				score_label.visible = false
			if instruction_label:
				instruction_label.visible = false
			if star_manager and star_manager.has_stars():
				_show_curved_text("TAP TO RETRY")
			else:
				_hide_curved_text()
			if level_label:
				level_label.visible = true
			if progress_label:
				progress_label.visible = false
			if levels_button:
				levels_button.visible = false

	# Always update high score display
	if high_score_label:
		high_score_label.text = "👑 " + str(high_score)

func _build_scanline_overlay() -> void:
	scanline_layer = CanvasLayer.new()
	scanline_layer.name = "ScanlineOverlay"
	scanline_layer.layer = 90  # Above almost everything
	scanline_layer.visible = false
	add_child(scanline_layer)

	var rect = ColorRect.new()
	rect.name = "ScanlineRect"
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scanline_material = ShaderMaterial.new()
	scanline_material.shader = preload("res://shaders/scanlines.gdshader")
	rect.material = scanline_material
	scanline_layer.add_child(rect)

func _create_wireframe_sphere(radius: float, lat_segments: int = 16, lon_segments: int = 24) -> ArrayMesh:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_LINES)

	# Latitude rings (horizontal circles)
	for i in range(1, lat_segments):
		var phi = PI * float(i) / float(lat_segments)
		var ring_r = radius * sin(phi)
		var y = radius * cos(phi)
		for j in range(lon_segments):
			var theta0 = TAU * float(j) / float(lon_segments)
			var theta1 = TAU * float(j + 1) / float(lon_segments)
			st.add_vertex(Vector3(ring_r * cos(theta0), y, ring_r * sin(theta0)))
			st.add_vertex(Vector3(ring_r * cos(theta1), y, ring_r * sin(theta1)))

	# Longitude lines (vertical arcs)
	for j in range(lon_segments):
		var theta = TAU * float(j) / float(lon_segments)
		for i in range(lat_segments):
			var phi0 = PI * float(i) / float(lat_segments)
			var phi1 = PI * float(i + 1) / float(lat_segments)
			st.add_vertex(Vector3(radius * sin(phi0) * cos(theta), radius * cos(phi0), radius * sin(phi0) * sin(theta)))
			st.add_vertex(Vector3(radius * sin(phi1) * cos(theta), radius * cos(phi1), radius * sin(phi1) * sin(theta)))

	return st.commit()

func _update_core_mesh_for_theme(is_vectrex: bool) -> void:
	if not core_sphere:
		return
	if is_vectrex and not _core_is_wireframe:
		core_sphere.mesh = _create_wireframe_sphere(CORE_RADIUS)
		_core_is_wireframe = true
	elif not is_vectrex and _core_is_wireframe:
		core_sphere.mesh = _original_core_mesh
		_core_is_wireframe = false

func update_theme_colors() -> void:
	var tc = _theme_colors(current_ui_theme, current_hue)

	# Only shift hue for themes that want it
	if tc["hue_shift"]:
		current_hue = fmod(0.45 + (score * HUE_SHIFT_PER_POINT), 1.0)
		tc = _theme_colors(current_ui_theme, current_hue)

	# Background gradient
	if bg_material:
		var top_c: Color = tc["bg_top"]
		var bot_c: Color = tc["bg_bottom"]
		bg_material.set_shader_parameter("color_top", Vector3(top_c.r, top_c.g, top_c.b))
		bg_material.set_shader_parameter("color_bottom", Vector3(bot_c.r, bot_c.g, bot_c.b))

	# Core sphere
	if core_material:
		core_material.albedo_color = tc["core"]

	# Main orbit ring
	if ring_material:
		ring_material.albedo_color = tc["ring"]

	# Inner rings
	for mat in inner_ring_materials:
		if mat:
			mat.albedo_color = tc["inner_ring"]

	# Floor grid
	if floor_grid_material:
		var near_c: Color = tc["grid_near"]
		var far_c: Color = tc["grid_far"]
		var glow_c: Color = tc["grid_glow"]
		floor_grid_material.set_shader_parameter("near_color", Vector3(near_c.r, near_c.g, near_c.b))
		floor_grid_material.set_shader_parameter("far_color", Vector3(far_c.r, far_c.g, far_c.b))
		floor_grid_material.set_shader_parameter("glow_color", Vector3(glow_c.r, glow_c.g, glow_c.b))

	# Grid pulse overlay
	if grid_pulse_material:
		var accent: Color = tc["accent"]
		grid_pulse_material.set_shader_parameter("line_color", Vector3(accent.r, accent.g, accent.b))

	# Radial glow (skip during frenzy — frenzy has its own gold glow)
	if radial_glow_material and not is_frenzy_active:
		var accent: Color = tc["accent"]
		radial_glow_material.set_shader_parameter("glow_color", Vector3(accent.r, accent.g, accent.b))

	# Score label color
	if score_label:
		score_label.modulate = tc["score_color"]

	# Level label color — fixed turquoise
	if level_label:
		level_label.add_theme_color_override("font_color", Color(0.0, 0.9, 0.9, 0.95))

	# Title gradient — match theme accent for vectrex
	if title_material:
		if current_ui_theme == "vectrex":
			var accent: Color = tc["accent"]
			var accent_dim = Color.from_hsv(fmod(accent.h + 0.15, 1.0), accent.s * 0.8, accent.v * 0.85)
			title_material.set_shader_parameter("color_start", accent)
			title_material.set_shader_parameter("color_mid", accent_dim)
			title_material.set_shader_parameter("color_end", accent)
		else:
			title_material.set_shader_parameter("color_start", Color(0.0, 0.94, 1.0))
			title_material.set_shader_parameter("color_mid", Color(1.0, 0.0, 0.67))
			title_material.set_shader_parameter("color_end", Color(0.0, 0.94, 1.0))

	# Cursor color
	if cursor_mesh and cursor_mesh.material_override:
		var cc: Color = tc["cursor"]
		cc.a = 0.9
		cursor_mesh.material_override.albedo_color = cc

	# Target color (only update if not mid-special — flip/expand have own colors)
	if target_mesh and target_mesh.material_override and target_mesh.visible:
		var tgt: Color = tc["target"]
		tgt.a = 0.9
		target_mesh.material_override.albedo_color = tgt

	# --- Vectrex CRT effects ---
	var is_vectrex = current_ui_theme == "vectrex"

	# Glow / bloom
	if game_environment:
		if is_vectrex:
			game_environment.glow_enabled = true
			game_environment.glow_intensity = 0.8
			game_environment.glow_strength = 1.2
			game_environment.glow_bloom = 0.3
			game_environment.glow_hdr_threshold = 0.8
			game_environment.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
		else:
			game_environment.glow_enabled = false

	# Scanline overlay
	if scanline_layer:
		scanline_layer.visible = is_vectrex

	# Material emission for vector glow look
	var vectrex_mats: Array[StandardMaterial3D] = []
	if core_material:
		vectrex_mats.append(core_material)
	if ring_material:
		vectrex_mats.append(ring_material)
	for mat in inner_ring_materials:
		if mat:
			vectrex_mats.append(mat)
	if cursor_mesh and cursor_mesh.material_override:
		vectrex_mats.append(cursor_mesh.material_override as StandardMaterial3D)
	if target_mesh and target_mesh.material_override:
		vectrex_mats.append(target_mesh.material_override as StandardMaterial3D)
	for gmat in ghost_materials:
		if gmat:
			vectrex_mats.append(gmat)

	if is_vectrex:
		var emit_color: Color = tc["accent"]
		# HDR emission — push brightness beyond 1.0 for bloom
		var emit_hdr = Color(emit_color.r * 1.5, emit_color.g * 1.5, emit_color.b * 1.5)
		for mat in vectrex_mats:
			mat.emission_enabled = true
			mat.emission = emit_hdr
			mat.emission_energy_multiplier = 1.4
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	else:
		for mat in vectrex_mats:
			mat.emission_enabled = false
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL

	# Wireframe core swap
	_update_core_mesh_for_theme(is_vectrex)

	# Settings gear button style
	if settings_button:
		if is_vectrex:
			var phosphor: Color = tc["accent"]
			var phosphor_dim = Color(phosphor.r * 0.15, phosphor.g * 0.15, phosphor.b * 0.15, 0.3)
			var vectrex_style = StyleBoxFlat.new()
			vectrex_style.draw_center = false
			vectrex_style.border_color = phosphor
			vectrex_style.border_width_left = 2
			vectrex_style.border_width_right = 2
			vectrex_style.border_width_top = 2
			vectrex_style.border_width_bottom = 2
			vectrex_style.corner_radius_top_left = 8
			vectrex_style.corner_radius_top_right = 8
			vectrex_style.corner_radius_bottom_left = 8
			vectrex_style.corner_radius_bottom_right = 8
			settings_button.add_theme_stylebox_override("normal", vectrex_style)
			var vectrex_hover = vectrex_style.duplicate()
			vectrex_hover.draw_center = true
			vectrex_hover.bg_color = phosphor_dim
			settings_button.add_theme_stylebox_override("hover", vectrex_hover)
			settings_button.add_theme_stylebox_override("pressed", vectrex_hover)
			settings_button.add_theme_color_override("font_color", Color(phosphor.r, phosphor.g, phosphor.b, 0.9))
			settings_button.add_theme_color_override("font_hover_color", phosphor)
		else:
			var menu_style = StyleBoxFlat.new()
			menu_style.bg_color = Color(1, 1, 1, 0.1)
			menu_style.corner_radius_top_left = 8
			menu_style.corner_radius_top_right = 8
			menu_style.corner_radius_bottom_left = 8
			menu_style.corner_radius_bottom_right = 8
			settings_button.add_theme_stylebox_override("normal", menu_style)
			var menu_hover = menu_style.duplicate()
			menu_hover.bg_color = Color(1, 1, 1, 0.2)
			settings_button.add_theme_stylebox_override("hover", menu_hover)
			settings_button.add_theme_stylebox_override("pressed", menu_hover)
			settings_button.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
			settings_button.add_theme_color_override("font_hover_color", Color.WHITE)

	# HUD labels — theme-aware colors
	if is_vectrex:
		var accent: Color = tc["accent"]
		var accent_dim = Color(accent.r, accent.g, accent.b, 0.7)
		if high_score_label:
			high_score_label.add_theme_color_override("font_color", accent_dim)
		if progress_label:
			progress_label.add_theme_color_override("font_color", Color(accent.r, accent.g, accent.b, 0.5))
		if levels_button:
			var lv_style = StyleBoxFlat.new()
			lv_style.draw_center = false
			lv_style.border_color = accent
			lv_style.border_width_left = 2
			lv_style.border_width_right = 2
			lv_style.border_width_top = 2
			lv_style.border_width_bottom = 2
			lv_style.corner_radius_top_left = 6
			lv_style.corner_radius_top_right = 6
			lv_style.corner_radius_bottom_left = 6
			lv_style.corner_radius_bottom_right = 6
			levels_button.add_theme_stylebox_override("normal", lv_style)
			var lv_hover = lv_style.duplicate()
			lv_hover.draw_center = true
			lv_hover.bg_color = Color(accent.r * 0.15, accent.g * 0.15, accent.b * 0.15, 0.3)
			levels_button.add_theme_stylebox_override("hover", lv_hover)
			levels_button.add_theme_stylebox_override("pressed", lv_hover)
			levels_button.add_theme_color_override("font_color", accent)
			levels_button.add_theme_color_override("font_hover_color", accent)
	else:
		if high_score_label:
			high_score_label.add_theme_color_override("font_color", Color(1.0, 0.84, 0.0, 0.8))
		if progress_label:
			var tgt_c: Color = tc["target"]
			progress_label.add_theme_color_override("font_color", Color(tgt_c.r, tgt_c.g, tgt_c.b, 0.5))
		if levels_button:
			levels_button.remove_theme_stylebox_override("normal")
			levels_button.remove_theme_stylebox_override("hover")
			levels_button.remove_theme_stylebox_override("pressed")
			levels_button.remove_theme_color_override("font_color")
			levels_button.remove_theme_color_override("font_hover_color")

	# Re-color curved text if visible (menu / game over screens)
	if curved_text_node and is_instance_valid(curved_text_node):
		var ct_color: Color = tc["accent"] if is_vectrex else Color.WHITE
		for child in curved_text_node.get_children():
			if child is Label3D:
				child.modulate = Color(ct_color.r, ct_color.g, ct_color.b, 0.45)

func load_high_score() -> void:
	load_progress()

func save_high_score() -> void:
	save_progress()

func load_progress() -> void:
	var config = ConfigFile.new()
	var err = config.load("user://save.cfg")
	if err == OK:
		max_unlocked_level = config.get_value("progress", "max_level", 1)
		high_score = config.get_value("progress", "high_score", 0)

func save_progress() -> void:
	var config = ConfigFile.new()
	config.load("user://save.cfg")  # Load existing to preserve star data
	config.set_value("progress", "max_level", max_unlocked_level)
	config.set_value("progress", "high_score", high_score)
	config.save("user://save.cfg")

func build_level_select() -> void:
	# Create canvas layer for level select UI
	level_select_layer = CanvasLayer.new()
	level_select_layer.name = "LevelSelectLayer"
	level_select_layer.layer = 10  # Above game
	level_select_layer.visible = false
	add_child(level_select_layer)

	level_select_layer.add_child(_modal_background())

	# Title
	var title = _styled_title("SELECT LEVEL", COLOR_ELECTRIC_CYAN, 32)
	title.anchor_left = 0.5
	title.anchor_right = 0.5
	title.offset_left = -150
	title.offset_right = 150
	title.offset_top = 60
	title.offset_bottom = 100
	level_select_layer.add_child(title)

	# Grid container for level buttons
	var grid_container = GridContainer.new()
	grid_container.name = "LevelGrid"
	grid_container.columns = 4
	grid_container.anchor_left = 0.5
	grid_container.anchor_right = 0.5
	grid_container.anchor_top = 0.5
	grid_container.anchor_bottom = 0.5
	grid_container.offset_left = -160
	grid_container.offset_right = 160
	grid_container.offset_top = -200
	grid_container.offset_bottom = 200
	grid_container.add_theme_constant_override("h_separation", 10)
	grid_container.add_theme_constant_override("v_separation", 10)
	level_select_layer.add_child(grid_container)

	# Create 20 level buttons (4x5 grid per page)
	level_buttons.clear()
	for i in range(20):
		var btn = Button.new()
		btn.custom_minimum_size = Vector2(70, 70)
		if font_bold:
			btn.add_theme_font_override("font", font_bold)
		btn.add_theme_font_size_override("font_size", 22)
		grid_container.add_child(btn)
		level_buttons.append(btn)

		# Connect button press
		var level_idx = i
		btn.pressed.connect(func(): on_level_button_pressed(level_idx))

	# Page navigation buttons
	var nav_container = HBoxContainer.new()
	nav_container.anchor_left = 0.5
	nav_container.anchor_right = 0.5
	nav_container.anchor_top = 1.0
	nav_container.offset_left = -120
	nav_container.offset_right = 120
	nav_container.offset_top = -120
	nav_container.offset_bottom = -70
	nav_container.alignment = BoxContainer.ALIGNMENT_CENTER
	nav_container.add_theme_constant_override("separation", 16)
	level_select_layer.add_child(nav_container)

	var prev_btn = _styled_button("<", COLOR_ELECTRIC_CYAN, Vector2(50, 44))
	prev_btn.pressed.connect(func(): change_level_page(-1))
	nav_container.add_child(prev_btn)

	var page_label = Label.new()
	page_label.name = "PageLabel"
	page_label.text = "1 / 5"
	page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	page_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	page_label.custom_minimum_size = Vector2(80, 44)
	page_label.add_theme_font_size_override("font_size", 18)
	if font_bold:
		page_label.add_theme_font_override("font", font_bold)
	page_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
	nav_container.add_child(page_label)

	var next_btn = _styled_button(">", COLOR_ELECTRIC_CYAN, Vector2(50, 44))
	next_btn.pressed.connect(func(): change_level_page(1))
	nav_container.add_child(next_btn)

	# Back button
	var back_btn = _styled_button("BACK", Color(0.5, 0.5, 0.6), Vector2(200, 44))
	back_btn.anchor_left = 0.5
	back_btn.anchor_right = 0.5
	back_btn.anchor_top = 1.0
	back_btn.offset_left = -100
	back_btn.offset_right = 100
	back_btn.offset_top = -60
	back_btn.offset_bottom = -16
	back_btn.pressed.connect(func(): hide_level_select())
	level_select_layer.add_child(back_btn)

func update_level_buttons() -> void:
	var start_level = current_page * 20 + 1
	for i in range(level_buttons.size()):
		var btn = level_buttons[i]
		var level = start_level + i

		if level > 100:
			btn.visible = false
			continue

		btn.visible = true
		btn.text = str(level)

		# Style based on unlock state
		if level <= max_unlocked_level:
			btn.disabled = false
			var accent: Color
			if level < max_unlocked_level:
				# Completed level - gold
				accent = Color(1.0, 0.84, 0.0)
			else:
				# Current unlocked level - cyan
				accent = COLOR_ELECTRIC_CYAN
			var bg = Color(accent.r * 0.2, accent.g * 0.2, accent.b * 0.2, 0.9)
			var style = StyleBoxFlat.new()
			style.bg_color = bg
			style.border_color = accent
			style.border_width_left = 2
			style.border_width_right = 2
			style.border_width_top = 2
			style.border_width_bottom = 2
			style.corner_radius_top_left = 8
			style.corner_radius_top_right = 8
			style.corner_radius_bottom_left = 8
			style.corner_radius_bottom_right = 8
			btn.add_theme_stylebox_override("normal", style)
			var hover_style = style.duplicate()
			hover_style.bg_color = Color(accent.r * 0.3, accent.g * 0.3, accent.b * 0.3, 0.95)
			btn.add_theme_stylebox_override("hover", hover_style)
			var pressed_style = style.duplicate()
			pressed_style.bg_color = Color(accent.r * 0.15, accent.g * 0.15, accent.b * 0.15, 0.95)
			btn.add_theme_stylebox_override("pressed", pressed_style)
			btn.add_theme_color_override("font_color", accent)
			btn.add_theme_color_override("font_hover_color", accent)
		else:
			# Locked level
			btn.disabled = true
			btn.text = "🔒"
			var locked_style = StyleBoxFlat.new()
			locked_style.bg_color = Color(0.1, 0.1, 0.15, 0.9)
			locked_style.border_color = Color(0.3, 0.3, 0.35)
			locked_style.border_width_left = 1
			locked_style.border_width_right = 1
			locked_style.border_width_top = 1
			locked_style.border_width_bottom = 1
			locked_style.corner_radius_top_left = 8
			locked_style.corner_radius_top_right = 8
			locked_style.corner_radius_bottom_left = 8
			locked_style.corner_radius_bottom_right = 8
			btn.add_theme_stylebox_override("normal", locked_style)
			btn.add_theme_stylebox_override("disabled", locked_style)
			btn.add_theme_color_override("font_color", Color(0.4, 0.4, 0.4))
			btn.add_theme_color_override("font_disabled_color", Color(0.4, 0.4, 0.4))

	# Update page label
	var page_label = level_select_layer.get_node_or_null("PageLabel")
	if not page_label:
		for child in level_select_layer.get_children():
			if child is HBoxContainer:
				for subchild in child.get_children():
					if subchild is Label and subchild.name == "PageLabel":
						page_label = subchild
						break
	if page_label:
		page_label.text = str(current_page + 1) + " / 5"

func change_level_page(direction: int) -> void:
	current_page = clamp(current_page + direction, 0, 4)
	update_level_buttons()

func on_level_button_pressed(button_index: int) -> void:
	var level = current_page * 20 + button_index + 1
	if level <= max_unlocked_level and level <= 100:
		current_level = level
		hide_level_select()
		start_game()

func show_level_select() -> void:
	current_state = GameState.LEVEL_SELECT
	current_page = (max_unlocked_level - 1) / 20  # Go to page with highest unlocked level
	update_level_buttons()
	if level_select_layer:
		level_select_layer.visible = true

func hide_level_select() -> void:
	current_state = GameState.MENU
	if level_select_layer:
		level_select_layer.visible = false
	update_ui()

# ===== SETTINGS, STARS, IAP & ADMOB =====

func _load_settings() -> void:
	var config = ConfigFile.new()
	if config.load("user://save.cfg") == OK:
		dev_mode_enabled = config.get_value("settings", "dev_mode", true)
		current_ui_theme = config.get_value("settings", "ui_theme", "vectrex")
		# Load all trophies dynamically
		if BOSS_REGISTRY.size() == 0:
			_init_boss_registry()
		for boss in BOSS_REGISTRY:
			trophies_unlocked[boss["key"]] = config.get_value("trophies", boss["key"], false)

func _save_settings() -> void:
	var config = ConfigFile.new()
	config.load("user://save.cfg")
	config.set_value("settings", "dev_mode", dev_mode_enabled)
	config.set_value("settings", "ui_theme", current_ui_theme)
	# Save all trophies dynamically
	for key in trophies_unlocked:
		config.set_value("trophies", key, trophies_unlocked[key])
	config.save("user://save.cfg")

func _init_star_manager() -> void:
	var script = load("res://scripts/star_manager.gd")
	if script:
		star_manager = Node.new()
		star_manager.set_script(script)
		star_manager.name = "StarManager"
		add_child(star_manager)
		star_manager.stars_changed.connect(_on_stars_changed)
		print("[OrbitalPop] Star manager initialized, stars=%d" % star_manager.stars)

func _init_iap_manager() -> void:
	var script = load("res://scripts/iap_manager.gd")
	if script:
		iap_manager = Node.new()
		iap_manager.set_script(script)
		iap_manager.name = "IAPManager"
		add_child(iap_manager)
		iap_manager.purchase_completed.connect(_on_iap_purchase_completed)
		iap_manager.purchase_failed.connect(_on_iap_purchase_failed)
		print("[OrbitalPop] IAP manager initialized")

func _init_admob() -> void:
	var script = load("res://scripts/admob_manager.gd")
	if script:
		admob_manager = Node.new()
		admob_manager.set_script(script)
		admob_manager.name = "AdMobManager"
		add_child(admob_manager)
		admob_manager.ad_rewarded.connect(_on_ad_rewarded)
		admob_manager.ad_closed.connect(_on_ad_closed)
		admob_manager.ad_failed.connect(_on_ad_failed)
		print("[OrbitalPop] AdMob manager initialized")

func _on_stars_changed(new_count: int) -> void:
	_update_star_display()

func _update_star_display() -> void:
	if star_label and star_manager:
		star_label.text = str(star_manager.stars)
		var tween = create_tween()
		tween.tween_property(star_label, "scale", Vector2(1.3, 1.3), 0.1)
		tween.tween_property(star_label, "scale", Vector2.ONE, 0.1)

# ----- UI Styling Helpers (borrowed from Cube Planet) -----

func _styled_button(text: String, accent_color: Color, size: Vector2 = Vector2(260, 50)) -> Button:
	var button = Button.new()
	button.text = text
	button.custom_minimum_size = size
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

	var normal_style = StyleBoxFlat.new()
	normal_style.border_width_left = 2
	normal_style.border_width_right = 2
	normal_style.border_width_top = 2
	normal_style.border_width_bottom = 2
	normal_style.corner_radius_top_left = 8
	normal_style.corner_radius_top_right = 8
	normal_style.corner_radius_bottom_left = 8
	normal_style.corner_radius_bottom_right = 8

	var text_color: Color
	if current_ui_theme == "vectrex":
		var phosphor = _theme_colors("vectrex", current_hue)["accent"]
		var phosphor_dim = Color(phosphor.r * 0.15, phosphor.g * 0.15, phosphor.b * 0.15, 0.3)
		normal_style.draw_center = false
		normal_style.border_color = phosphor
		var hover_style = normal_style.duplicate()
		hover_style.draw_center = true
		hover_style.bg_color = phosphor_dim
		button.add_theme_stylebox_override("normal", normal_style)
		button.add_theme_stylebox_override("hover", hover_style)
		button.add_theme_stylebox_override("pressed", hover_style)
		text_color = phosphor
	else:
		var bg_color = Color(accent_color.r * 0.2, accent_color.g * 0.2, accent_color.b * 0.2, 0.9)
		var hover_color = Color(accent_color.r * 0.3, accent_color.g * 0.3, accent_color.b * 0.3, 0.95)
		normal_style.bg_color = bg_color
		normal_style.border_color = accent_color
		button.add_theme_stylebox_override("normal", normal_style)
		var hover_style = normal_style.duplicate()
		hover_style.bg_color = hover_color
		button.add_theme_stylebox_override("hover", hover_style)
		var pressed_style = normal_style.duplicate()
		pressed_style.bg_color = Color(accent_color.r * 0.15, accent_color.g * 0.15, accent_color.b * 0.15, 0.95)
		button.add_theme_stylebox_override("pressed", pressed_style)
		var luminance = accent_color.r * 0.299 + accent_color.g * 0.587 + accent_color.b * 0.114
		text_color = Color.WHITE if luminance < 0.3 else accent_color

	if font_bold:
		button.add_theme_font_override("font", font_bold)
	button.add_theme_font_size_override("font_size", 18)
	button.add_theme_color_override("font_color", text_color)
	button.add_theme_color_override("font_hover_color", text_color)

	return button

func _styled_text_button(text: String) -> Button:
	var button = Button.new()
	button.text = text
	button.flat = true
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	if font_bold:
		button.add_theme_font_override("font", font_bold)
	button.add_theme_font_size_override("font_size", 14)
	button.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7))
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	return button

func _styled_title(text: String, accent_color: Color = COLOR_ELECTRIC_CYAN, size: int = 36) -> Label:
	var label = Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", size)
	if font_bold:
		label.add_theme_font_override("font", font_bold)
	label.add_theme_color_override("font_color", accent_color)
	return label

func _modal_background() -> ColorRect:
	var bg = ColorRect.new()
	bg.color = Color(0.02, 0.02, 0.05, 0.85)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	return bg

func _modal_container(separation: int = 12) -> VBoxContainer:
	var container = VBoxContainer.new()
	container.anchor_left = 0.5
	container.anchor_right = 0.5
	container.anchor_top = 0.5
	container.anchor_bottom = 0.5
	container.offset_left = -150
	container.offset_right = 150
	container.offset_top = -250
	container.offset_bottom = 250
	container.alignment = BoxContainer.ALIGNMENT_CENTER
	container.add_theme_constant_override("separation", separation)
	return container

func _fade_in_layer(layer: CanvasLayer) -> void:
	for child in layer.get_children():
		if child is Control:
			child.modulate.a = 0
			var tween = child.create_tween()
			tween.tween_property(child, "modulate:a", 1.0, 0.2)

# ----- Settings Menu -----

func _show_settings() -> void:
	if settings_layer:
		return

	# Pause game if playing or in countdown
	_state_before_pause = current_state
	if current_state == GameState.PLAYING or current_state == GameState.COUNTDOWN:
		current_state = GameState.MENU  # Stops cursor movement in _process
		# Stop any playing sounds
		if sfx_hit and sfx_hit.playing: sfx_hit.stop()
		if sfx_miss and sfx_miss.playing: sfx_miss.stop()
		if sfx_flip and sfx_flip.playing: sfx_flip.stop()
		if sfx_expand and sfx_expand.playing: sfx_expand.stop()
		if sfx_level_complete and sfx_level_complete.playing: sfx_level_complete.stop()

	settings_layer = CanvasLayer.new()
	settings_layer.name = "SettingsLayer"
	settings_layer.layer = 15
	add_child(settings_layer)

	settings_layer.add_child(_modal_background())

	var container = _modal_container()
	settings_layer.add_child(container)

	# Title
	var title_text = "PAUSED" if _state_before_pause == GameState.PLAYING or _state_before_pause == GameState.COUNTDOWN else "SETTINGS"
	container.add_child(_styled_title(title_text))

	# Spacer
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 12)
	container.add_child(spacer)

	# Sound toggle
	var sound_btn = _styled_button("Sound: OFF" if sound_muted else "Sound: ON", COLOR_ELECTRIC_CYAN)
	sound_btn.pressed.connect(func():
		toggle_mute()
		sound_btn.text = "Sound: OFF" if sound_muted else "Sound: ON"
	)
	container.add_child(sound_btn)

	# Music selector
	var music_row = HBoxContainer.new()
	music_row.alignment = BoxContainer.ALIGNMENT_CENTER
	music_row.add_theme_constant_override("separation", 12)
	var music_prev = _styled_button("<", COLOR_ELECTRIC_CYAN, Vector2(44, 44))
	var music_lbl = Label.new()
	music_lbl.text = "Music: " + current_bgm.to_upper()
	music_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	music_lbl.custom_minimum_size = Vector2(160, 44)
	music_lbl.add_theme_color_override("font_color", COLOR_ELECTRIC_CYAN)
	var music_next = _styled_button(">", COLOR_ELECTRIC_CYAN, Vector2(44, 44))
	var _cycle_music = func(dir: int):
		var idx = BGM_TRACKS.find(current_bgm)
		idx = (idx + dir) % BGM_TRACKS.size()
		if idx < 0:
			idx += BGM_TRACKS.size()
		switch_bgm(BGM_TRACKS[idx])
		music_lbl.text = "Music: " + current_bgm.to_upper()
	music_prev.pressed.connect(func(): _cycle_music.call(-1))
	music_next.pressed.connect(func(): _cycle_music.call(1))
	music_row.add_child(music_prev)
	music_row.add_child(music_lbl)
	music_row.add_child(music_next)
	container.add_child(music_row)

	# Theme selector
	var theme_row = HBoxContainer.new()
	theme_row.alignment = BoxContainer.ALIGNMENT_CENTER
	theme_row.add_theme_constant_override("separation", 12)
	var theme_prev = _styled_button("<", COLOR_ELECTRIC_CYAN, Vector2(44, 44))
	var theme_display_name = current_ui_theme.to_upper()
	var theme_lbl = Label.new()
	theme_lbl.text = "Theme: " + theme_display_name
	theme_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	theme_lbl.custom_minimum_size = Vector2(160, 44)
	theme_lbl.add_theme_font_size_override("font_size", 18)
	if font_bold:
		theme_lbl.add_theme_font_override("font", font_bold)
	theme_lbl.add_theme_color_override("font_color", Color.WHITE)
	var theme_next = _styled_button(">", COLOR_ELECTRIC_CYAN, Vector2(44, 44))
	var _cycle_theme = func(dir: int):
		var idx = UI_THEMES.find(current_ui_theme)
		idx = (idx + dir) % UI_THEMES.size()
		if idx < 0:
			idx += UI_THEMES.size()
		current_ui_theme = UI_THEMES[idx]
		theme_lbl.text = "Theme: " + current_ui_theme.to_upper()
		_save_settings()
		update_theme_colors()
	theme_prev.pressed.connect(func(): _cycle_theme.call(-1))
	theme_next.pressed.connect(func(): _cycle_theme.call(1))
	theme_row.add_child(theme_prev)
	theme_row.add_child(theme_lbl)
	theme_row.add_child(theme_next)
	container.add_child(theme_row)

	# Trophies button
	if BOSS_REGISTRY.size() == 0:
		_init_boss_registry()
	var trophy_count = 0
	if dev_mode_enabled:
		trophy_count = BOSS_REGISTRY.size()
	else:
		for key in trophies_unlocked:
			if trophies_unlocked[key]:
				trophy_count += 1
	var trophy_btn = _styled_button("Trophies  [%d/%d]" % [trophy_count, BOSS_REGISTRY.size()], Color(1.0, 0.84, 0.0))
	trophy_btn.pressed.connect(func():
		# Close settings layer but DON'T resume game — trophy room keeps it paused
		if settings_layer:
			settings_layer.queue_free()
			settings_layer = null
		_show_trophy_room()
	)
	container.add_child(trophy_btn)

	# Dev Mode toggle
	var dev_btn = _styled_button("Dev Mode: ON" if dev_mode_enabled else "Dev Mode: OFF", COLOR_FLOPPY_YELLOW)
	dev_btn.pressed.connect(func():
		dev_mode_enabled = not dev_mode_enabled
		_save_settings()
		dev_btn.text = "Dev Mode: ON" if dev_mode_enabled else "Dev Mode: OFF"
	)
	container.add_child(dev_btn)

	# Remove Ads / Ads Removed
	if iap_manager and iap_manager.is_ads_disabled():
		var removed_label = Label.new()
		removed_label.text = "✓ Ads Removed"
		removed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		removed_label.add_theme_font_size_override("font_size", 18)
		if font_bold:
			removed_label.add_theme_font_override("font", font_bold)
		removed_label.add_theme_color_override("font_color", Color(0.22, 1.0, 0.08))
		container.add_child(removed_label)
	else:
		var price = iap_manager.get_remove_ads_price() if iap_manager else "$2.99"
		var iap_btn = _styled_button("Remove Ads - %s" % price, COLOR_ELECTRIC_CYAN)
		iap_btn.pressed.connect(func():
			if iap_manager:
				iap_btn.disabled = true
				iap_btn.text = "PURCHASING..."
				iap_manager.purchase_remove_ads()
		)
		container.add_child(iap_btn)

	# Restore Purchases
	var restore_btn = _styled_text_button("Restore Purchases")
	restore_btn.pressed.connect(func():
		if iap_manager:
			restore_btn.text = "Restoring..."
			iap_manager.restore_purchases()
	)
	container.add_child(restore_btn)

	# Return to Menu (only if playing or game over)
	if _state_before_pause in [GameState.PLAYING, GameState.COUNTDOWN, GameState.GAME_OVER]:
		var menu_btn = _styled_button("Return to Menu", COLOR_HOT_MAGENTA)
		menu_btn.pressed.connect(func():
			_close_settings()
			_return_to_menu()
		)
		container.add_child(menu_btn)

	# Close button
	var close_btn = _styled_button("CLOSE", Color(0.5, 0.5, 0.6), Vector2(200, 44))
	close_btn.pressed.connect(func(): _close_settings())
	container.add_child(close_btn)

	_fade_in_layer(settings_layer)

func _close_settings() -> void:
	if settings_layer:
		settings_layer.queue_free()
		settings_layer = null
	# Resume game if it was playing/countdown before pause
	if _state_before_pause == GameState.PLAYING or _state_before_pause == GameState.COUNTDOWN:
		current_state = _state_before_pause

func _make_boss_viewport(rows: Array, boss_color: Color, vp_size: int, update_mode: int, anim_frames: Array = []) -> SubViewport:
	# Creates an isolated SubViewport with just a 3D boss mesh, camera, and lights
	var vp = SubViewport.new()
	vp.size = Vector2i(vp_size, vp_size)
	vp.transparent_bg = true
	vp.render_target_update_mode = update_mode
	vp.msaa_3d = Viewport.MSAA_2X
	vp.own_world_3d = true
	vp.world_3d = World3D.new()

	var env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0, 0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.5, 0.55)
	env.ambient_light_energy = 0.8
	var we = WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)

	var cam = Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 1.6
	cam.position = Vector3(0, 0, 3)
	cam.look_at(Vector3.ZERO)
	vp.add_child(cam)

	var light = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-25, 35, 0)
	light.light_energy = 1.8
	vp.add_child(light)

	var light2 = DirectionalLight3D.new()
	light2.rotation_degrees = Vector3(15, -50, 0)
	light2.light_energy = 0.5
	vp.add_child(light2)

	var pivot = Node3D.new()
	pivot.name = "Pivot"
	vp.add_child(pivot)

	var mesh_inst = MeshInstance3D.new()
	mesh_inst.mesh = _build_invader_mesh_from_rows(rows)
	var mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = boss_color
	mesh_inst.material_override = mat
	mesh_inst.rotation_degrees = Vector3(20, -30, 0)
	pivot.add_child(mesh_inst)

	# Animate sprite frames if this boss has animation
	if anim_frames.size() > 1 and update_mode == SubViewport.UPDATE_ALWAYS:
		var frame_idx = [0]  # Wrapped in array for closure capture
		var timer = Timer.new()
		timer.wait_time = 0.3  # Match game animation speed
		timer.autostart = true
		timer.timeout.connect(func():
			frame_idx[0] = (frame_idx[0] + 1) % anim_frames.size()
			if is_instance_valid(mesh_inst):
				mesh_inst.mesh = _build_invader_mesh_from_rows(anim_frames[frame_idx[0]])
		)
		vp.add_child(timer)

	return vp

func _show_trophy_room() -> void:
	if trophy_layer:
		return
	if BOSS_REGISTRY.size() == 0:
		_init_boss_registry()
	trophy_layer = CanvasLayer.new()
	trophy_layer.name = "TrophyLayer"
	trophy_layer.layer = 16
	add_child(trophy_layer)

	trophy_layer.add_child(_modal_background())

	var outer = VBoxContainer.new()
	outer.set_anchors_preset(Control.PRESET_FULL_RECT)
	outer.offset_left = 12
	outer.offset_right = -12
	outer.offset_top = 60
	outer.offset_bottom = -40
	outer.add_theme_constant_override("separation", 8)
	trophy_layer.add_child(outer)

	outer.add_child(_styled_title("TROPHY ROOM", Color(1.0, 0.84, 0.0), 28))

	var trophy_count = 0
	if dev_mode_enabled:
		trophy_count = BOSS_REGISTRY.size()
	else:
		for key in trophies_unlocked:
			if trophies_unlocked[key]:
				trophy_count += 1
	var count_lbl = Label.new()
	count_lbl.text = "%d / %d captured" % [trophy_count, BOSS_REGISTRY.size()]
	count_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	count_lbl.add_theme_font_size_override("font_size", 13)
	count_lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7))
	if font_bold:
		count_lbl.add_theme_font_override("font", font_bold)
	outer.add_child(count_lbl)

	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)

	var grid = GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid)

	for boss in BOSS_REGISTRY:
		var unlocked = dev_mode_enabled or trophies_unlocked.get(boss["key"], false)
		var boss_color = boss["color"]

		# Container for each tile
		var tile_wrap = Control.new()
		tile_wrap.custom_minimum_size = Vector2(64, 64)
		tile_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		if unlocked:
			# 2D pixel-art thumbnail rendered directly to Image (no SubViewport)
			var tex = _make_boss_icon_texture(boss["rows"], boss_color)

			# Dark background panel
			var bg_panel = Panel.new()
			bg_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
			var bg_style = StyleBoxFlat.new()
			bg_style.bg_color = Color(boss_color.r * 0.1, boss_color.g * 0.1, boss_color.b * 0.1, 0.9)
			bg_style.border_width_left = 1
			bg_style.border_width_right = 1
			bg_style.border_width_top = 1
			bg_style.border_width_bottom = 1
			bg_style.corner_radius_top_left = 4
			bg_style.corner_radius_top_right = 4
			bg_style.corner_radius_bottom_left = 4
			bg_style.corner_radius_bottom_right = 4
			bg_style.border_color = Color(1.0, 0.84, 0.0, 0.6)
			if current_ui_theme == "vectrex":
				var phosphor = _theme_colors("vectrex", current_hue)["accent"]
				bg_style.bg_color = Color(phosphor.r * 0.05, phosphor.g * 0.05, phosphor.b * 0.05, 0.9)
				bg_style.border_color = Color(phosphor.r, phosphor.g, phosphor.b, 0.6)
			bg_panel.add_theme_stylebox_override("panel", bg_style)
			tile_wrap.add_child(bg_panel)

			var thumb = TextureRect.new()
			thumb.set_anchors_preset(Control.PRESET_FULL_RECT)
			thumb.texture = tex
			thumb.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
			thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			thumb.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
			tile_wrap.add_child(thumb)

			# Invisible button for tap detection
			var tap_btn = Button.new()
			tap_btn.set_anchors_preset(Control.PRESET_FULL_RECT)
			tap_btn.flat = true
			tap_btn.modulate = Color(1, 1, 1, 0)
			var boss_ref = boss
			tap_btn.pressed.connect(func(): _show_boss_inspect(boss_ref))
			tile_wrap.add_child(tap_btn)
		else:
			# Locked tile
			var locked = Panel.new()
			locked.set_anchors_preset(Control.PRESET_FULL_RECT)
			var ls = StyleBoxFlat.new()
			ls.bg_color = Color(0.04, 0.04, 0.06, 0.9)
			ls.border_width_left = 1
			ls.border_width_right = 1
			ls.border_width_top = 1
			ls.border_width_bottom = 1
			ls.corner_radius_top_left = 4
			ls.corner_radius_top_right = 4
			ls.corner_radius_bottom_left = 4
			ls.corner_radius_bottom_right = 4
			ls.border_color = Color(0.12, 0.12, 0.15)
			if current_ui_theme == "vectrex":
				var p = _theme_colors("vectrex", current_hue)["accent"]
				ls.border_color = Color(p.r * 0.15, p.g * 0.15, p.b * 0.15, 0.3)
			locked.add_theme_stylebox_override("panel", ls)
			tile_wrap.add_child(locked)

			var q_lbl = Label.new()
			q_lbl.text = "?"
			q_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			q_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			q_lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
			q_lbl.add_theme_font_size_override("font_size", 22)
			q_lbl.add_theme_color_override("font_color", Color(0.18, 0.18, 0.22))
			if font_bold:
				q_lbl.add_theme_font_override("font", font_bold)
			tile_wrap.add_child(q_lbl)

		grid.add_child(tile_wrap)

	var back_btn = _styled_button("BACK", Color(0.5, 0.5, 0.6), Vector2(200, 44))
	back_btn.pressed.connect(func():
		_close_trophy_room()
		_show_settings()
	)
	outer.add_child(back_btn)

	_fade_in_layer(trophy_layer)

var _trophy_inspect_layer: CanvasLayer = null
var _trophy_inspect_mesh: Node3D = null
var _trophy_spin_velocity_x: float = 0.0
var _trophy_spin_velocity_y: float = 0.0
var _trophy_drag_active: bool = false
var _trophy_drag_prev_x: float = 0.0
var _trophy_drag_prev_y: float = 0.0

func _show_boss_inspect(boss: Dictionary) -> void:
	_close_boss_inspect()
	_trophy_spin_velocity_x = 0.0
	_trophy_spin_velocity_y = 0.0
	_trophy_drag_active = false

	_trophy_inspect_layer = CanvasLayer.new()
	_trophy_inspect_layer.name = "TrophyInspect"
	_trophy_inspect_layer.layer = 17
	add_child(_trophy_inspect_layer)

	# Full-screen touch area: handles drag-to-spin and tap-to-close
	var touch_area = Control.new()
	touch_area.set_anchors_preset(Control.PRESET_FULL_RECT)
	touch_area.mouse_filter = Control.MOUSE_FILTER_STOP

	# Dark background
	var bg = ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.0, 0.0, 0.0, 0.8)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	touch_area.add_child(bg)

	# Handle touch input for drag-spin and tap-close
	var _drag_start_pos = Vector2.ZERO
	var _drag_moved = false
	touch_area.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton:
			if event.pressed:
				_trophy_drag_active = true
				_trophy_drag_prev_x = event.position.x
				_trophy_drag_prev_y = event.position.y
				_drag_start_pos = event.position
				_drag_moved = false
			else:
				_trophy_drag_active = false
				if not _drag_moved or _drag_start_pos.distance_to(event.position) < 15.0:
					_close_boss_inspect()
		elif event is InputEventMouseMotion and _trophy_drag_active:
			var dx = event.position.x - _trophy_drag_prev_x
			var dy = event.position.y - _trophy_drag_prev_y
			_trophy_drag_prev_x = event.position.x
			_trophy_drag_prev_y = event.position.y
			_trophy_spin_velocity_y = dx * 0.02
			_trophy_spin_velocity_x = -dy * 0.015
			if _trophy_inspect_mesh and is_instance_valid(_trophy_inspect_mesh):
				_trophy_inspect_mesh.rotation.y += dx * 0.01
				for child in _trophy_inspect_mesh.get_children():
					child.rotation.x = clampf(child.rotation.x - dy * 0.008, -PI / 2.0, PI / 2.0)
			if _drag_start_pos.distance_to(event.position) > 10:
				_drag_moved = true
		elif event is InputEventScreenTouch:
			if event.pressed:
				_trophy_drag_active = true
				_trophy_drag_prev_x = event.position.x
				_trophy_drag_prev_y = event.position.y
				_drag_start_pos = event.position
				_drag_moved = false
			else:
				_trophy_drag_active = false
				if not _drag_moved or _drag_start_pos.distance_to(event.position) < 15.0:
					_close_boss_inspect()
		elif event is InputEventScreenDrag:
			var dx = event.position.x - _trophy_drag_prev_x
			var dy = event.position.y - _trophy_drag_prev_y
			_trophy_drag_prev_x = event.position.x
			_trophy_drag_prev_y = event.position.y
			_trophy_spin_velocity_y = dx * 0.02
			_trophy_spin_velocity_x = -dy * 0.015
			if _trophy_inspect_mesh and is_instance_valid(_trophy_inspect_mesh):
				_trophy_inspect_mesh.rotation.y += dx * 0.01
				for child in _trophy_inspect_mesh.get_children():
					child.rotation.x = clampf(child.rotation.x - dy * 0.008, -PI / 2.0, PI / 2.0)
			if _drag_start_pos.distance_to(event.position) > 10:
				_drag_moved = true
	)
	_trophy_inspect_layer.add_child(touch_area)

	# Center layout
	var col = VBoxContainer.new()
	col.anchor_left = 0.5
	col.anchor_right = 0.5
	col.anchor_top = 0.5
	col.anchor_bottom = 0.5
	col.offset_left = -160
	col.offset_right = 160
	col.offset_top = -220
	col.offset_bottom = 220
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 8)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_trophy_inspect_layer.add_child(col)

	# 3D boss viewport — rendered via TextureRect (not SubViewportContainer to avoid duplication)
	var vp = _make_boss_viewport(boss["rows"], boss["color"], 400, SubViewport.UPDATE_ALWAYS, boss.get("anim_frames", []))
	# Camera sized to show boss large but fully visible
	for child in vp.get_children():
		if child is Camera3D:
			child.size = 1.8
	# Straight-on initial rotation so user can spin it
	for child in vp.get_children():
		if child.name == "Pivot":
			_trophy_inspect_mesh = child
			for mesh_child in child.get_children():
				mesh_child.rotation_degrees = Vector3(15, 0, 0)
			break
	# Parent VP to the layer (not the column) so it doesn't affect layout
	_trophy_inspect_layer.add_child(vp)

	# Display the viewport texture
	var vp_display = TextureRect.new()
	vp_display.custom_minimum_size = Vector2(300, 300)
	vp_display.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vp_display.texture = vp.get_texture()
	vp_display.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	vp_display.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	vp_display.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(vp_display)

	# Boss name
	var name_lbl = Label.new()
	name_lbl.text = boss["name"]
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_size_override("font_size", 32)
	if font_bold:
		name_lbl.add_theme_font_override("font", font_bold)
	if current_ui_theme == "vectrex":
		name_lbl.add_theme_color_override("font_color", _theme_colors("vectrex", current_hue)["accent"])
	else:
		name_lbl.add_theme_color_override("font_color", boss["color"])
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(name_lbl)

	# CAPTURED
	var status_lbl = Label.new()
	status_lbl.text = "CAPTURED"
	status_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_lbl.add_theme_font_size_override("font_size", 16)
	if font_bold:
		status_lbl.add_theme_font_override("font", font_bold)
	status_lbl.add_theme_color_override("font_color", Color(0.2, 1.0, 0.3))
	status_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(status_lbl)

	# Hint
	var hint = Label.new()
	hint.text = "drag to rotate  ·  tap to close"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color(0.4, 0.4, 0.5))
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(hint)

	_fade_in_layer(_trophy_inspect_layer)

func _close_boss_inspect() -> void:
	_trophy_inspect_mesh = null
	_trophy_drag_active = false
	_trophy_spin_velocity_x = 0.0
	_trophy_spin_velocity_y = 0.0
	if _trophy_inspect_layer:
		_trophy_inspect_layer.queue_free()
		_trophy_inspect_layer = null

func _close_trophy_room() -> void:
	_close_boss_inspect()
	if trophy_layer:
		trophy_layer.queue_free()
		trophy_layer = null

func _show_trophy_unlocked_text(boss_name: String) -> void:
	var lbl = Label3D.new()
	lbl.text = boss_name + " CAPTURED!"
	lbl.font_size = 80
	if font_bold:
		lbl.font = font_bold
	lbl.modulate = Color(1.0, 0.84, 0.0, 1.0)
	lbl.outline_modulate = Color(1.0, 0.84, 0.0, 0.6)
	lbl.outline_size = 6
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.no_depth_test = true
	lbl.position = Vector3(0, 0, 2.0)
	lbl.scale = Vector3(0.3, 0.3, 0.3)
	add_child(lbl)
	var t = create_tween()
	t.set_parallel(true)
	t.tween_property(lbl, "scale", Vector3(1.0, 1.0, 1.0), 0.5).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	t.tween_property(lbl, "position:y", 1.5, 0.5).set_ease(Tween.EASE_OUT)
	t.set_parallel(false)
	t.tween_interval(1.0)
	t.tween_property(lbl, "modulate:a", 0.0, 0.4)
	t.tween_property(lbl, "outline_modulate:a", 0.0, 0.4)
	t.tween_callback(lbl.queue_free)

func _return_to_menu() -> void:
	_state_before_pause = GameState.MENU  # Prevent _close_settings from restoring play state
	current_state = GameState.MENU
	# Reset game visuals
	if fail_label:
		fail_label.visible = false
	if cursor_mesh:
		cursor_mesh.visible = true
	if target_mesh:
		target_mesh.visible = false
	# Reset camera
	if camera:
		camera.size = 9.0
		camera.position = Vector3(0, 0, 10)
	update_ui()

# ----- IAP Callbacks -----

func _on_iap_purchase_completed(product_id: String) -> void:
	print("[OrbitalPop] Purchase completed: %s" % product_id)
	_close_settings()
	_close_out_of_stars_modal()
	_update_star_display()

func _on_iap_purchase_failed(error: String) -> void:
	print("[OrbitalPop] Purchase failed: %s" % error)
	# Settings will be rebuilt next time it's opened

# ----- Out of Stars Modal -----

func show_out_of_stars_modal() -> void:
	if out_of_stars_layer and out_of_stars_layer.visible:
		return

	if out_of_stars_layer:
		out_of_stars_layer.queue_free()

	out_of_stars_layer = CanvasLayer.new()
	out_of_stars_layer.name = "OutOfStarsLayer"
	out_of_stars_layer.layer = 20
	add_child(out_of_stars_layer)

	out_of_stars_layer.add_child(_modal_background())

	var container = _modal_container()
	out_of_stars_layer.add_child(container)

	container.add_child(_styled_title("OUT OF STARS", COLOR_FLOPPY_YELLOW))

	var star_count = Label.new()
	star_count.text = "★ %d" % (star_manager.stars if star_manager else 0)
	star_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	star_count.add_theme_font_size_override("font_size", 48)
	if font_bold:
		star_count.add_theme_font_override("font", font_bold)
	star_count.add_theme_color_override("font_color", Color(1.0, 0.84, 0.0))
	container.add_child(star_count)

	var desc = Label.new()
	desc.name = "Description"
	desc.text = "Watch an ad to get 2 more stars!"
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.add_theme_font_size_override("font_size", 16)
	if font_bold:
		desc.add_theme_font_override("font", font_bold)
	desc.add_theme_color_override("font_color", Color(1, 1, 1, 0.5))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	container.add_child(desc)

	# Watch Ad button
	var ad_btn = _styled_button("Watch Ad +2★", Color(0.22, 1.0, 0.08))
	ad_btn.name = "WatchAdButton"
	ad_btn.pressed.connect(func(): _on_watch_ad_pressed(ad_btn, desc))
	container.add_child(ad_btn)

	# Remove Ads button
	var price = iap_manager.get_remove_ads_price() if iap_manager else "$2.99"
	var iap_btn = _styled_button("Remove Ads - %s" % price, COLOR_ELECTRIC_CYAN)
	iap_btn.pressed.connect(func():
		if iap_manager:
			iap_btn.disabled = true
			iap_btn.text = "PURCHASING..."
			iap_manager.purchase_remove_ads()
	)
	container.add_child(iap_btn)

	# Menu button
	var menu_btn = _styled_button("MENU", COLOR_HOT_MAGENTA)
	menu_btn.pressed.connect(func(): _close_out_of_stars_modal())
	container.add_child(menu_btn)

	_fade_in_layer(out_of_stars_layer)

# ----- Ad Callbacks -----

var _watch_ad_btn: Button = null
var _watch_ad_desc: Label = null

func _on_watch_ad_pressed(ad_btn: Button, desc_label: Label) -> void:
	_watch_ad_btn = ad_btn
	_watch_ad_desc = desc_label
	ad_btn.disabled = true
	ad_btn.text = "LOADING..."

	# Check if ad system is available
	var ad_ready = admob_manager and admob_manager.is_ad_ready() if admob_manager else false
	if ad_ready:
		admob_manager.show_rewarded_ad()
	else:
		# Ad not available — grant stars directly (no ads configured / dev / test)
		print("[OrbitalPop] Ad not available, granting stars directly")
		_grant_stars_and_play()

func _grant_stars_and_play() -> void:
	if star_manager:
		star_manager.grant_ad_reward_stars()
		_update_star_display()
	_close_out_of_stars_modal()
	start_game()

func _on_ad_rewarded() -> void:
	print("[OrbitalPop] Ad reward earned - granting 2 stars")
	_grant_stars_and_play()

func _on_ad_closed() -> void:
	# Ad was closed without earning reward — re-enable button
	if _watch_ad_btn and is_instance_valid(_watch_ad_btn):
		_watch_ad_btn.disabled = false
		_watch_ad_btn.text = "Watch Ad +2★"

func _on_ad_failed() -> void:
	print("[OrbitalPop] Ad failed to show — granting stars as fallback")
	# Ad system is broken — just give the stars so the player isn't stuck
	_grant_stars_and_play()

func _close_out_of_stars_modal() -> void:
	if out_of_stars_layer:
		out_of_stars_layer.queue_free()
		out_of_stars_layer = null

# ===== HAPTICS =====

func haptic_light() -> void:
	Input.vibrate_handheld(50)

func haptic_double() -> void:
	Input.vibrate_handheld(100)
	get_tree().create_timer(0.05).timeout.connect(func(): Input.vibrate_handheld(50))

func haptic_heavy() -> void:
	Input.vibrate_handheld(300)

# ===== FRENZY SYSTEM =====

func _activate_frenzy() -> void:
	is_frenzy_active = true
	if radial_glow_material:
		radial_glow_material.set_shader_parameter("glow_color", Vector3(1.0, 0.84, 0.0))
		radial_glow_material.set_shader_parameter("base_opacity", 0.25)

func _activate_overdrive() -> void:
	_overdrive_active = true
	if radial_glow_material:
		radial_glow_material.set_shader_parameter("base_opacity", 0.8)
	if current_ui_theme == "vectrex" and scanline_material:
		scanline_material.set_shader_parameter("flicker_speed", 5.0)

func _deactivate_overdrive() -> void:
	_overdrive_active = false
	if _overdrive_tween and _overdrive_tween.is_valid():
		_overdrive_tween.kill()
	_overdrive_tween = null
	if current_ui_theme == "vectrex" and scanline_material:
		scanline_material.set_shader_parameter("flicker_speed", 2.5)

func _break_frenzy_streak() -> void:
	var was_active = is_frenzy_active
	frenzy_streak = 0
	frenzy_multiplier = 1.0
	is_frenzy_active = false
	# Hide ghost cursors
	for ghost in ghost_meshes:
		ghost.visible = false
	# Deactivate overdrive
	if _overdrive_active:
		_deactivate_overdrive()
	# Boss frenzy grace: allow some non-perfect hits after boss defeat
	if boss_frenzy_grace > 0:
		boss_frenzy_grace -= 1
		return
	# If level complete was deferred waiting for boss mode, fire it now
	if _level_complete_deferred and not is_boss_mode:
		_level_complete_deferred = false
		trigger_level_complete()
		return
	_update_streak_bar()
	update_progress_ring()
	# Restore glow to current theme color
	if was_active and radial_glow_material:
		var accent = Color.from_hsv(current_hue, 0.7, 1.0)
		radial_glow_material.set_shader_parameter("glow_color", Vector3(accent.r, accent.g, accent.b))
		radial_glow_material.set_shader_parameter("base_opacity", 0.12)

func _make_boss_icon_texture(rows: Array, boss_color: Color) -> ImageTexture:
	# Renders boss pixel-art rows into a small Image for use as a 2D icon
	# Column 0 = single center pixel, columns 1+ = mirrored left/right
	var max_col = 0
	for row in rows:
		for col in row:
			if col > max_col:
				max_col = col
	# Width: 1 center + max_col on each side = 1 + 2*max_col
	var grid_w = 1 + max_col * 2
	var grid_h = rows.size()
	var img_w = grid_w + 4  # 2px padding each side
	var img_h = grid_h + 4
	var img = Image.create(img_w, img_h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var center_x = img_w / 2
	for row_idx in range(grid_h):
		var cols = rows[row_idx]
		var py = row_idx + 2
		for col in cols:
			if col == 0:
				# Single center pixel
				if center_x >= 0 and center_x < img_w:
					img.set_pixel(center_x, py, boss_color)
			else:
				# Mirror left and right
				var px_right = center_x + col
				var px_left = center_x - col
				if px_right >= 0 and px_right < img_w:
					img.set_pixel(px_right, py, boss_color)
				if px_left >= 0 and px_left < img_w:
					img.set_pixel(px_left, py, boss_color)

	return ImageTexture.create_from_image(img)

# ── Boss Mode ──────────────────────────────────────────────────────────

func _build_invader_mesh_from_rows(rows: Array, cell: float = 0.12) -> ArrayMesh:
	# Shared builder: creates extruded 3D voxel pixel-art from row data
	# Column 0 = single center cell, columns 1+ = mirrored left/right
	# Each pixel cell becomes a small box with depth = TARGET_HEIGHT
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var h = rows.size()
	var hd = TARGET_HEIGHT / 2.0  # Half-depth for Z extrusion
	for row_idx in range(h):
		var y = (float(h) / 2.0 - row_idx) * cell
		var cols = rows[row_idx]
		for col in cols:
			# Column 0 = center (x=0), columns 1+ mirrored at ±col
			var positions: Array = []
			if col == 0:
				positions = [0.0]
			else:
				positions = [float(col) * cell, float(-col) * cell]
			for x_center in positions:
				var x0 = x_center - cell * 0.5
				var x1 = x_center + cell * 0.5
				var y0 = y - cell * 0.5
				var y1 = y + cell * 0.5
				# 8 corners of the box
				var ftl = Vector3(x0, y1, hd)   # front top-left
				var ftr = Vector3(x1, y1, hd)   # front top-right
				var fbl = Vector3(x0, y0, hd)   # front bottom-left
				var fbr = Vector3(x1, y0, hd)   # front bottom-right
				var btl = Vector3(x0, y1, -hd)  # back top-left
				var btr = Vector3(x1, y1, -hd)
				var bbl = Vector3(x0, y0, -hd)
				var bbr = Vector3(x1, y0, -hd)
				# Front face (+Z)
				st.set_normal(Vector3(0, 0, 1))
				st.add_vertex(fbl); st.add_vertex(fbr); st.add_vertex(ftr)
				st.add_vertex(fbl); st.add_vertex(ftr); st.add_vertex(ftl)
				# Back face (-Z)
				st.set_normal(Vector3(0, 0, -1))
				st.add_vertex(bbr); st.add_vertex(bbl); st.add_vertex(btl)
				st.add_vertex(bbr); st.add_vertex(btl); st.add_vertex(btr)
				# Top face (+Y)
				st.set_normal(Vector3(0, 1, 0))
				st.add_vertex(ftl); st.add_vertex(ftr); st.add_vertex(btr)
				st.add_vertex(ftl); st.add_vertex(btr); st.add_vertex(btl)
				# Bottom face (-Y)
				st.set_normal(Vector3(0, -1, 0))
				st.add_vertex(fbr); st.add_vertex(fbl); st.add_vertex(bbl)
				st.add_vertex(fbr); st.add_vertex(bbl); st.add_vertex(bbr)
				# Right face (+X)
				st.set_normal(Vector3(1, 0, 0))
				st.add_vertex(fbr); st.add_vertex(bbr); st.add_vertex(btr)
				st.add_vertex(fbr); st.add_vertex(btr); st.add_vertex(ftr)
				# Left face (-X)
				st.set_normal(Vector3(-1, 0, 0))
				st.add_vertex(fbl); st.add_vertex(ftl); st.add_vertex(btl)
				st.add_vertex(fbl); st.add_vertex(btl); st.add_vertex(bbl)
	return st.commit()

# --- Boss Registry: all capturable bosses ---
# Each entry: { "key": str, "name": str, "icon": str, "color": Color, "rows": Array }
var BOSS_REGISTRY: Array = []

func _init_boss_registry() -> void:
	# Solid-fill pixel art bosses: dense filled shapes with eye/mouth cutouts
	# Column 0 = single center pixel, columns 1+ mirrored left/right
	BOSS_REGISTRY = [
		{"key": "mawface", "name": "MAWFACE", "icon": ":D", "color": Color(1.0, 0.2, 0.2), "rows": [
			[0, 1, 2],
			[0, 1, 2, 3],
			[0, 2, 3],
			[0, 2, 3, 4, 5],
			[0, 1, 2, 3, 5],
			[3, 5],
			[0, 1, 2, 3],
			[1, 3],
			[1, 3],
		]},
		{"key": "grinner", "name": "GRINNER", "icon": "=D", "color": Color(1.0, 0.8, 0.0), "rows": [
			[2, 3],
			[2],
			[0, 1, 2],
			[0, 1, 2, 3],
			[0, 4],
			[0, 2, 4],
			[0, 1, 2, 3, 4],
			[3, 4, 5],
			[0, 1, 2, 3, 4, 5],
			[0, 1, 2, 3, 4],
			[3],
		]},
		{"key": "stickbug", "name": "STICKBUG", "icon": "Xo", "color": Color(0.2, 1.0, 0.3), "rows": [
			[0, 1],
			[0, 1, 2],
			[0, 2, 3],
			[0, 2, 3],
			[0, 1, 2, 3, 4],
			[0, 1, 2, 5],
			[0, 1],
			[2],
			[3],
			[3],
		], "anim_frames": [
			[  # Frame 1: arms out, legs apart
				[0, 1],
				[0, 1, 2],
				[0, 2, 3],
				[0, 2, 3],
				[0, 1, 2, 3, 5],
				[0, 1, 2, 4],
				[0, 1],
				[1, 3],
				[2, 4],
				[2, 4],
			],
			[  # Frame 2: arms up, legs together
				[0, 1],
				[0, 1, 2],
				[0, 2, 3],
				[0, 2, 3],
				[0, 1, 2, 3, 4],
				[0, 1, 2, 5],
				[0, 1],
				[2],
				[3],
				[3],
			],
			[  # Frame 3: arms down, legs apart (opposite of frame 1)
				[0, 1],
				[0, 1, 2],
				[0, 2, 3],
				[0, 2, 3],
				[0, 1, 2, 3, 4],
				[0, 1, 2],
				[0, 1, 4],
				[1, 3],
				[2, 4],
				[2, 4],
			],
		]},
		{"key": "sprawler", "name": "SPRAWLER", "icon": "XX", "color": Color(0.4, 0.4, 1.0), "rows": [
			[4],
			[3],
			[0, 1, 2],
			[0, 1, 2, 3],
			[0, 3],
			[0, 1, 2, 3, 4, 5],
			[2, 3, 5],
			[0, 1, 2, 3],
			[3],
			[3, 4],
		]},
		{"key": "bigsmile", "name": "BIGSMILE", "icon": "=)", "color": Color(1.0, 0.6, 0.0), "rows": [
			[0, 1],
			[0, 1, 2],
			[0, 1, 2, 3],
			[0, 1, 3, 4],
			[0, 1, 2, 3, 4, 5],
			[2, 3, 4],
			[0, 1, 2, 3],
			[0, 1, 2, 4],
			[0, 1, 2, 5],
			[0, 1],
			[0],
		]},
		{"key": "mothbug", "name": "MOTHBUG", "icon": "oX", "color": Color(0.0, 0.9, 0.5), "rows": [
			[4, 5],
			[3, 4],
			[0, 1, 2, 3],
			[0, 1, 2, 3, 4],
			[0, 1, 2, 3, 4],
			[0, 1, 2, 3, 4],
			[1, 2, 3],
			[0, 1, 2],
			[0, 1, 2],
			[0, 1, 2, 3],
			[1, 2, 3, 4],
		]},
		{"key": "skullcross", "name": "SKULLCROSS", "icon": "xX", "color": Color(0.9, 0.2, 0.9), "rows": [
			[3, 4],
			[2, 3],
			[0, 1, 2],
			[0, 1, 2, 3],
			[0, 1, 2, 3, 4, 5, 6],
			[0, 1, 2, 3, 4, 5],
			[1, 2, 3],
			[0, 1, 2],
			[0, 1, 2, 3],
			[2, 3],
		]},
		{"key": "droopy", "name": "DROOPY", "icon": ":/", "color": Color(0.3, 0.7, 1.0), "rows": [
			[0, 1, 2],
			[0, 1, 2, 3],
			[0, 1, 2, 3, 4],
			[0, 1, 2, 3, 4],
			[1, 2, 3, 4, 5],
			[0, 1, 2, 3, 4, 5],
			[1, 2, 3, 4],
			[1, 2, 3, 4],
		]},
		{"key": "lovebug", "name": "LOVEBUG", "icon": "<3", "color": Color(1.0, 0.15, 0.5), "rows": [
			[0, 1],
			[0, 1, 2],
			[0, 1, 2, 3],
			[0, 3, 4],
			[0, 1, 2, 3, 4],
			[2, 3, 4],
			[2, 3],
			[0, 1, 2],
			[0, 1, 2, 3],
			[0, 1, 4],
			[0],
		]},
		{"key": "walker", "name": "WALKER", "icon": "[]", "color": Color(0.3, 0.3, 1.0), "rows": [
			[0, 1, 2],
			[0, 1, 2, 3],
			[0, 1, 2, 3],
			[0, 1, 2, 3],
			[0, 1, 2, 3, 4, 5],
			[1, 2, 3, 4, 5],
			[0, 1, 2],
			[1, 2],
			[1, 2, 3],
		]},
		{"key": "happywide", "name": "HAPPYWIDE", "icon": "=]", "color": Color(1.0, 0.4, 0.4), "rows": [
			[0, 1],
			[0, 1, 2, 3],
			[0, 1, 3, 4],
			[0, 1, 2, 3, 4, 5],
			[3, 4, 5],
			[0, 1, 2, 3, 4, 5],
			[1, 3, 5],
			[1, 3, 5],
		]},
		{"key": "helmetbot", "name": "HELMETBOT", "icon": "--", "color": Color(0.9, 0.7, 0.0), "rows": [
			[0, 1],
			[0, 1, 2],
			[0, 2, 3],
			[0, 2, 3],
			[0, 1, 2, 3],
			[2, 4],
			[0, 1, 2, 5],
			[0, 1],
		]},
		{"key": "smilecap", "name": "SMILECAP", "icon": ":)", "color": Color(0.0, 0.85, 0.85), "rows": [
			[0, 1],
			[0, 1, 2],
			[0, 1, 2, 3],
			[0, 2, 3],
			[0, 1, 2, 3, 4],
			[0, 1, 2, 3, 5],
			[1, 3],
			[1, 3],
		]},
		{"key": "rageblock", "name": "RAGEBLOCK", "icon": ">X<", "color": Color(1.0, 0.0, 0.8), "rows": [
			[0, 3, 4],
			[0, 1, 2, 3, 4],
			[0, 1, 2, 3, 4],
			[0, 1, 2, 3, 4, 6],
			[0, 1, 2, 3, 4, 5, 6],
			[0, 1, 3, 4, 5, 6],
			[0, 1, 2, 3, 4, 5],
			[0, 1, 2, 3, 4, 5],
			[0, 2, 3, 5],
			[0, 1, 2, 3, 4, 5],
			[0, 1, 2, 3, 4, 5],
			[2, 4],
			[0, 1, 2, 4, 5],
		]},
		{"key": "angrydome", "name": "ANGRYDOME", "icon": ">:", "color": Color(1.0, 0.0, 0.0), "rows": [
			[4],
			[0, 1, 2, 3],
			[0, 1, 3],
			[0, 1, 2, 3],
			[2, 3, 4],
			[0, 1, 2, 3, 4],
			[0, 1, 2, 3, 5],
			[0, 1, 2, 5],
			[2],
		]},
		{"key": "sidebot", "name": "SIDEBOT", "icon": "!]", "color": Color(0.0, 1.0, 0.7), "rows": [
			[0],
			[0, 1],
			[0, 1],
			[0, 1, 2],
			[0, 2, 3],
			[0, 1, 2],
			[2, 3],
			[0, 1, 2],
			[0, 1, 2, 3],
			[1, 3],
			[1, 3],
		]},
		{"key": "crosslegs", "name": "CROSSLEGS", "icon": "XX", "color": Color(0.6, 0.2, 1.0), "rows": [
			[1, 2],
			[0, 1, 2],
			[0, 1, 2, 3],
			[0, 1, 2, 3, 4, 5, 6],
			[0, 1, 2, 3, 4, 5],
			[0, 1, 2, 3],
			[1, 2, 3],
			[1, 2, 3, 4],
		]},
		{"key": "squat", "name": "SQUAT", "icon": "VV", "color": Color(0.5, 1.0, 0.0), "rows": [
			[2, 3, 4],
			[2, 3],
			[0, 1, 2, 3],
			[0, 1, 2, 3, 4],
			[0, 1, 2, 3, 4],
			[0, 1, 2, 3, 4],
			[0, 1, 2, 3, 4],
			[0, 1, 2, 3, 4, 5],
			[1, 2, 5, 6],
			[2, 3],
		]},
		{"key": "smilehelm", "name": "SMILEHELM", "icon": "=)", "color": Color(1.0, 0.5, 0.3), "rows": [
			[1],
			[0, 1, 2, 3],
			[1, 3, 4],
			[0, 1, 2, 3, 4],
			[2, 3, 4, 5],
			[0, 1, 2, 3, 4],
			[0, 2, 4],
		]},
		{"key": "bughelm", "name": "BUGHELM", "icon": "BH", "color": Color(0.0, 0.6, 1.0), "rows": [
			[2, 3],
			[0, 1, 2],
			[0, 1, 2, 3],
			[0, 1, 2, 3, 4],
			[0, 1, 2, 3, 4],
			[1, 2, 3, 4, 5],
			[0, 1, 2, 4, 5],
			[1, 2],
			[1, 2, 3],
		]},
		{"key": "hornbug", "name": "HORNBUG", "icon": "HH", "color": Color(0.2, 0.8, 0.8), "rows": [
			[3, 4],
			[2, 3, 4],
			[0, 1, 2, 3],
			[0, 1, 2, 3, 4],
			[0, 1, 3, 4, 5],
			[0, 1, 3, 4, 5],
			[0, 1, 2, 3, 4, 5, 6],
			[0, 1, 2, 3, 4, 5, 6],
			[1, 2, 3, 4],
			[1, 2, 3, 4],
			[2, 3, 4, 5],
		]},
		{"key": "flatsmile", "name": "FLATSMILE", "icon": "=_", "color": Color(1.0, 0.5, 0.0), "rows": [
			[0, 1, 2, 3, 4, 5, 6],
			[0, 1, 2, 3, 4, 5, 6],
			[0, 1, 3, 5, 6],
			[0, 1, 2, 3, 4, 5, 6],
			[0, 2, 3, 4, 6],
			[0, 1, 2, 3, 4, 5, 6],
			[0, 1, 2, 3, 4, 5],
			[0, 1, 4, 5],
		]},
		{"key": "tinybug", "name": "TINYBUG", "icon": "CC", "color": Color(0.8, 0.0, 0.6), "rows": [
			[0, 1, 3, 4],
			[0, 1, 2, 3, 4],
			[0, 1, 2, 3, 4, 5],
			[0, 1, 2, 3, 4, 5],
			[0, 1, 3, 4, 5],
			[0, 1, 2, 3, 4, 5],
			[0, 1, 2, 3, 4],
			[0, 1, 3, 4],
		]},
		{"key": "tankbot", "name": "TANKBOT", "icon": "TB", "color": Color(0.4, 0.9, 0.2), "rows": [
			[3, 4],
			[0, 1, 2, 3],
			[0, 1, 2, 3, 4],
			[0, 1, 3, 4, 5],
			[0, 1, 3, 4, 5, 6],
			[0, 1, 2, 3, 4, 5, 6, 7],
			[0, 1, 2, 3, 4, 5, 6, 7],
			[3, 4, 6, 7],
			[3, 4],
			[2, 3, 4],
		]},
	]

func _get_boss_for_encounter() -> Dictionary:
	# Pick a random uncaptured boss; if all captured, pick any random boss
	if BOSS_REGISTRY.size() == 0:
		_init_boss_registry()
	var uncaptured: Array = []
	for boss in BOSS_REGISTRY:
		if not trophies_unlocked.get(boss["key"], false):
			uncaptured.append(boss)
	if uncaptured.size() > 0:
		return uncaptured[randi() % uncaptured.size()]
	# All captured — pick any random boss
	return BOSS_REGISTRY[randi() % BOSS_REGISTRY.size()]

func _get_boss_mesh_for_level() -> ArrayMesh:
	var boss = _get_boss_for_encounter()
	return _build_invader_mesh_from_rows(boss["rows"])

func _build_boss_shield() -> void:
	# Shield is HP-only — no visible mesh, just the HP mechanic
	boss_shield_hp = 2 + mini(boss_encounters, 3)
	boss_shield_mesh = null
	boss_shield_material = null

func _damage_boss_shield() -> void:
	boss_shield_hp -= 1
	# Flash shield white
	if boss_shield_material:
		var orig = boss_shield_material.albedo_color
		boss_shield_material.albedo_color = Color.WHITE
		var tw = create_tween()
		tw.tween_property(boss_shield_material, "albedo_color", orig, 0.15)
	# Sparks at boss position
	_spawn_boss_sparks(4)
	_update_boss_hp_bar()
	if boss_shield_hp <= 0:
		_shatter_boss_shield()

func _shatter_boss_shield() -> void:
	if not boss_shield_mesh or not is_instance_valid(boss_shield_mesh):
		return
	# Spawn fragments scattering outward
	var pos = boss_mesh.global_position if boss_mesh and is_instance_valid(boss_mesh) else Vector3(0, BOSS_INVADER_HEIGHT, 0)
	for i in range(12):
		var frag = MeshInstance3D.new()
		var box = BoxMesh.new()
		box.size = Vector3(0.08, 0.08, 0.02)
		frag.mesh = box
		var mat = StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(0.3, 0.8, 1.0, 0.8)
		frag.material_override = mat
		add_child(frag)
		var angle = TAU * float(i) / 12.0
		frag.global_position = pos + Vector3(cos(angle) * 0.5, sin(angle) * 0.5, 0)
		var dir = Vector3(cos(angle), sin(angle), randf_range(-0.3, 0.3)) * randf_range(1.5, 3.0)
		var tw = create_tween()
		tw.set_parallel(true)
		tw.tween_property(frag, "position", frag.position + dir, 0.6).set_ease(Tween.EASE_OUT)
		tw.tween_property(frag, "scale", Vector3.ZERO, 0.6)
		tw.tween_property(mat, "albedo_color:a", 0.0, 0.6)
		tw.set_parallel(false)
		tw.tween_callback(frag.queue_free)
	# Remove shield mesh
	boss_shield_mesh.queue_free()
	boss_shield_mesh = null
	boss_shield_material = null

func _build_boss_hp_bar() -> void:
	# Simple single bar that shrinks as HP decreases
	_clear_boss_hp_bar()
	var bar_width = 2.0
	# Background (dark)
	var bg = MeshInstance3D.new()
	bg.name = "BossHPBg"
	var bg_box = BoxMesh.new()
	bg_box.size = Vector3(bar_width + 0.06, 0.16, 0.02)
	bg.mesh = bg_box
	var bg_mat = StandardMaterial3D.new()
	bg_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bg_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bg_mat.albedo_color = Color(0.1, 0.1, 0.1, 0.7)
	bg.material_override = bg_mat
	bg.position = Vector3(0, BOSS_INVADER_HEIGHT + 1.6, -0.01)
	add_child(bg)
	boss_hp_segments.append(bg)
	boss_hp_segment_materials.append(bg_mat)
	# Foreground (colored fill)
	var fill = MeshInstance3D.new()
	fill.name = "BossHPFill"
	var fill_box = BoxMesh.new()
	fill_box.size = Vector3(bar_width, 0.12, 0.02)
	fill.mesh = fill_box
	var fill_mat = StandardMaterial3D.new()
	fill_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fill_mat.albedo_color = Color(1.0, 0.3, 0.1, 0.95)
	if current_ui_theme == "vectrex":
		var p = _theme_colors("vectrex", current_hue)["accent"]
		fill_mat.albedo_color = Color(p.r, p.g, p.b, 0.95)
		fill_mat.emission_enabled = true
		fill_mat.emission = p
		fill_mat.emission_energy_multiplier = 1.0
	fill.material_override = fill_mat
	fill.position = Vector3(0, BOSS_INVADER_HEIGHT + 1.6, 0)
	add_child(fill)
	boss_hp_segments.append(fill)
	boss_hp_segment_materials.append(fill_mat)

func _update_boss_hp_bar() -> void:
	if boss_hp_segments.size() < 2:
		return
	var bg = boss_hp_segments[0]
	var fill = boss_hp_segments[1]
	if not is_instance_valid(bg) or not is_instance_valid(fill):
		return
	# Scale fill bar based on remaining HP ratio
	var total_hp = boss_max_hp_current + boss_shield_hp
	var current = boss_hp + boss_shield_hp
	var ratio = float(current) / float(total_hp) if total_hp > 0 else 0.0
	fill.scale.x = maxf(ratio, 0.01)
	# Color shifts: green > yellow > red as HP drops
	if ratio > 0.5:
		boss_hp_segment_materials[1].albedo_color = Color(0.2, 1.0, 0.3, 0.95)
	elif ratio > 0.25:
		boss_hp_segment_materials[1].albedo_color = Color(1.0, 0.8, 0.1, 0.95)
	else:
		boss_hp_segment_materials[1].albedo_color = Color(1.0, 0.2, 0.1, 0.95)
	# Track boss movement
	if boss_mesh and is_instance_valid(boss_mesh):
		bg.position.x = boss_mesh.position.x
		bg.position.y = boss_mesh.position.y + 1.6
		fill.position.x = boss_mesh.position.x
		fill.position.y = boss_mesh.position.y + 1.6

func _clear_boss_hp_bar() -> void:
	for seg in boss_hp_segments:
		if is_instance_valid(seg):
			seg.queue_free()
	boss_hp_segments.clear()
	boss_hp_segment_materials.clear()

func _spawn_boss_sparks(count: int = 8) -> void:
	# Impact sparks at boss position
	var pos = boss_mesh.global_position if boss_mesh and is_instance_valid(boss_mesh) else Vector3(0, BOSS_INVADER_HEIGHT, 0)
	for i in range(count):
		var spark = MeshInstance3D.new()
		var box = BoxMesh.new()
		box.size = Vector3(0.04, 0.04, 0.04)
		spark.mesh = box
		var mat = StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(1.0, 0.9, 0.6, 1.0)  # Hot white-orange
		if current_ui_theme == "vectrex":
			mat.emission_enabled = true
			mat.emission = Color.WHITE
			mat.emission_energy_multiplier = 2.0
		spark.material_override = mat
		add_child(spark)
		spark.global_position = pos + Vector3(randf_range(-0.2, 0.2), randf_range(-0.2, 0.2), 0)
		var dir = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-0.3, 0.3)).normalized() * randf_range(0.5, 1.5)
		var tw = create_tween()
		tw.set_parallel(true)
		tw.tween_property(spark, "position", spark.position + dir, 0.3).set_ease(Tween.EASE_OUT)
		tw.tween_property(spark, "scale", Vector3.ZERO, 0.3)
		tw.tween_property(mat, "albedo_color:a", 0.0, 0.3)
		tw.set_parallel(false)
		tw.tween_callback(spark.queue_free)

func _spawn_boss_bomb() -> void:
	if not boss_mesh or not is_instance_valid(boss_mesh):
		return
	if boss_bombs.size() >= 5:  # Cap at 5 active bombs
		return
	var bomb = MeshInstance3D.new()
	bomb.name = "BossBomb"
	# Wireframe cross for bomb visual
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_LINES)
	var sz = 0.12
	st.set_normal(Vector3(0, 0, 1))
	# X cross
	st.add_vertex(Vector3(-sz, -sz, 0)); st.add_vertex(Vector3(sz, sz, 0))
	st.add_vertex(Vector3(-sz, sz, 0)); st.add_vertex(Vector3(sz, -sz, 0))
	# + cross
	st.add_vertex(Vector3(0, -sz, 0)); st.add_vertex(Vector3(0, sz, 0))
	st.add_vertex(Vector3(-sz, 0, 0)); st.add_vertex(Vector3(sz, 0, 0))
	# Diamond outline
	st.add_vertex(Vector3(0, sz, 0)); st.add_vertex(Vector3(sz, 0, 0))
	st.add_vertex(Vector3(sz, 0, 0)); st.add_vertex(Vector3(0, -sz, 0))
	st.add_vertex(Vector3(0, -sz, 0)); st.add_vertex(Vector3(-sz, 0, 0))
	st.add_vertex(Vector3(-sz, 0, 0)); st.add_vertex(Vector3(0, sz, 0))
	bomb.mesh = st.commit()
	var mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1.0, 0.4, 0.0, 1.0)
	if current_ui_theme == "vectrex":
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.4, 0.0)
		mat.emission_energy_multiplier = 1.4
	bomb.material_override = mat
	bomb.position = boss_mesh.position
	bomb.scale = Vector3(1.5, 1.5, 1.5)
	add_child(bomb)
	boss_bombs.append(bomb)

func _update_boss_bombs(delta: float) -> void:
	var speed = BOSS_BOMB_SPEED * (1.0 + boss_encounters * 0.2)
	var to_remove: Array = []
	for bomb in boss_bombs:
		if not is_instance_valid(bomb):
			to_remove.append(bomb)
			continue
		# Move toward ring center
		var target_pos = Vector3(0, 0, 0)
		bomb.position = bomb.position.move_toward(target_pos, speed * delta)
		# Spin the bomb for visual flair
		bomb.rotation.z += delta * 4.0
		# Check if bomb reached the ring area
		if bomb.position.length() < active_radius + 0.3:
			# Check proximity to cursor
			var bomb_angle = atan2(bomb.position.y, bomb.position.x) - PI / 2.0
			var angle_diff = abs(cursor_angle - bomb_angle)
			if angle_diff > PI:
				angle_diff = TAU - angle_diff
			if angle_diff < get_overlap_threshold() * 2.0:
				# Bomb hits near cursor — visual effect only (boss immune to miss)
				_spawn_boss_sparks(6)
				_show_miss_text("BLOCKED!")
			# Remove bomb regardless
			to_remove.append(bomb)
			bomb.queue_free()
	for bomb in to_remove:
		boss_bombs.erase(bomb)

func _clear_boss_bombs() -> void:
	for bomb in boss_bombs:
		if is_instance_valid(bomb):
			bomb.queue_free()
	boss_bombs.clear()
	boss_bomb_timer = 0.0

func _update_boss(delta: float) -> void:
	# Enforce 45° tilt — lerp toward target to correct any drift
	if world_group and abs(world_group.rotation.x - _boss_tilt_target) > 0.01:
		world_group.rotation.x = lerp_angle(world_group.rotation.x, _boss_tilt_target, 5.0 * delta)

	# Boss movement: drift + bob
	boss_drift_time += delta * boss_drift_speed
	if boss_mesh and is_instance_valid(boss_mesh):
		boss_mesh.position.x = sin(boss_drift_time) * 0.8
		boss_mesh.position.y = BOSS_INVADER_HEIGHT + sin(boss_drift_time * 1.7) * 0.15

	# Animate boss sprite frames (if this boss has animation)
	if boss_anim_frames.size() > 1 and boss_mesh and is_instance_valid(boss_mesh):
		boss_anim_timer += delta
		if boss_anim_timer >= 0.3:  # 3.3 FPS — chunky pixel-art style
			boss_anim_timer = 0.0
			boss_anim_frame = (boss_anim_frame + 1) % boss_anim_frames.size()
			boss_mesh.mesh = _build_invader_mesh_from_rows(boss_anim_frames[boss_anim_frame])

	# Update HP bar positions to follow boss
	_update_boss_hp_bar()

	# Bomb timer
	boss_bomb_timer -= delta
	if boss_bomb_timer <= 0.0:
		_spawn_boss_bomb()
		boss_bomb_timer = BOSS_BOMB_INTERVAL / (1.0 + boss_encounters * 0.2)

	# Update bomb positions
	_update_boss_bombs(delta)

	# Boss escape timer
	boss_timer -= delta
	if boss_timer <= 0.0:
		_boss_escape()

func _boss_escape() -> void:
	# Boss flies away — player took too long
	if not is_boss_mode or _boss_defeated or _boss_escaped:
		return
	is_boss_mode = false
	_boss_escaped = true

	# Play sad escape sound
	if sfx_boss_escape and not sound_muted:
		sfx_boss_escape.play()

	# Clean up shield, HP bar, bombs
	if boss_shield_mesh and is_instance_valid(boss_shield_mesh):
		boss_shield_mesh.queue_free()
		boss_shield_mesh = null
	boss_shield_material = null
	_clear_boss_hp_bar()
	_clear_boss_bombs()

	# Boss swirls and flies away — no reparenting, animate position directly
	if boss_mesh and is_instance_valid(boss_mesh):
		var start_pos = boss_mesh.position
		var start_rot_y = boss_mesh.rotation.y
		var escape_mesh = boss_mesh
		boss_mesh = null  # Clear reference immediately so nothing else touches it

		var swirl_tw = create_tween()
		swirl_tw.set_parallel(true)
		# Fly upward and to the side in a curve
		swirl_tw.tween_property(escape_mesh, "position:y", start_pos.y + 10.0, 1.5).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		swirl_tw.tween_property(escape_mesh, "position:x", start_pos.x + 3.0, 1.5).set_ease(Tween.EASE_IN)
		# Spin fast on multiple axes
		swirl_tw.tween_property(escape_mesh, "rotation:y", start_rot_y + TAU * 6, 1.5)
		swirl_tw.tween_property(escape_mesh, "rotation:x", TAU * 2, 1.5)
		# Shrink to nothing
		swirl_tw.tween_property(escape_mesh, "scale", Vector3.ZERO, 1.5).set_ease(Tween.EASE_IN)
		swirl_tw.set_parallel(false)
		swirl_tw.tween_callback(func():
			if is_instance_valid(escape_mesh):
				escape_mesh.queue_free()
		)
	else:
		boss_mesh = null

	# Show "ESCAPED!" text
	var lbl = Label3D.new()
	lbl.text = "ESCAPED!"
	lbl.font_size = 80
	if font_bold:
		lbl.font = font_bold
	lbl.modulate = Color(1.0, 0.4, 0.1, 1.0)
	lbl.outline_modulate = Color(1.0, 0.4, 0.1, 0.6)
	lbl.outline_size = 6
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.no_depth_test = true
	lbl.position = Vector3(0, BOSS_INVADER_HEIGHT, 2.0)
	add_child(lbl)
	var txt_tw = create_tween()
	txt_tw.tween_property(lbl, "position:y", BOSS_INVADER_HEIGHT + 1.5, 0.8).set_ease(Tween.EASE_OUT)
	txt_tw.tween_interval(0.5)
	txt_tw.tween_property(lbl, "modulate:a", 0.0, 0.4)
	txt_tw.parallel().tween_property(lbl, "outline_modulate:a", 0.0, 0.4)
	txt_tw.tween_callback(lbl.queue_free)

	# End boss mode after swirl animation completes
	get_tree().create_timer(2.0).timeout.connect(func():
		if not is_inside_tree():
			return
		# Tilt back
		var flip_base = PI if world_flipped else 0.0
		var untilt = create_tween()
		untilt.tween_property(world_group, "rotation:x", flip_base, 0.8).set_ease(Tween.EASE_IN_OUT)
		untilt.tween_callback(func(): world_group.rotation.x = flip_base)

		_restore_background_tint()
		if core_sphere:
			core_sphere.visible = true
		switch_bgm("ambient")

		is_boss_mode = false
		boss_hp = 0
		boss_material = null

		# Check deferred level complete
		if _level_complete_deferred or level_hits >= hits_required:
			_level_complete_deferred = false
			get_tree().create_timer(0.5).timeout.connect(func():
				if current_state == GameState.PLAYING and is_inside_tree():
					trigger_level_complete()
			)
	)

func _show_boss_warning_text() -> void:
	var lbl = Label3D.new()
	lbl.text = "BOSS INCOMING"
	lbl.font_size = 96
	if font_bold:
		lbl.font = font_bold
	lbl.modulate = Color(1.0, 0.2, 0.0, 1.0)
	lbl.outline_modulate = Color(1.0, 0.2, 0.0, 0.6)
	lbl.outline_size = 6
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.no_depth_test = true
	lbl.position = Vector3(0, 0, 2.0)
	lbl.scale = Vector3(0.5, 0.5, 0.5)
	add_child(lbl)
	var t = create_tween()
	t.set_parallel(true)
	t.tween_property(lbl, "scale", Vector3(1.2, 1.2, 1.2), 0.4).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	t.tween_property(lbl, "position:y", 1.0, 0.4).set_ease(Tween.EASE_OUT)
	t.set_parallel(false)
	t.tween_interval(0.6)
	t.tween_property(lbl, "modulate:a", 0.0, 0.3)
	t.tween_callback(lbl.queue_free)

func _tint_background_boss() -> void:
	if bg_material:
		boss_original_bg_top = bg_material.get_shader_parameter("color_top")
		boss_original_bg_bottom = bg_material.get_shader_parameter("color_bottom")
		var tw = create_tween()
		tw.set_parallel(true)
		tw.tween_method(func(v): bg_material.set_shader_parameter("color_top", v), boss_original_bg_top, Vector3(0.3, 0.05, 0.05), 1.0)
		tw.tween_method(func(v): bg_material.set_shader_parameter("color_bottom", v), boss_original_bg_bottom, Vector3(0.08, 0.02, 0.02), 1.0)

func _restore_background_tint() -> void:
	if bg_material:
		var tw = create_tween()
		tw.set_parallel(true)
		tw.tween_method(func(v): bg_material.set_shader_parameter("color_top", v), bg_material.get_shader_parameter("color_top"), boss_original_bg_top, 0.8)
		tw.tween_method(func(v): bg_material.set_shader_parameter("color_bottom", v), bg_material.get_shader_parameter("color_bottom"), boss_original_bg_bottom, 0.8)

func _activate_boss_mode() -> void:
	if is_boss_mode:
		return
	is_boss_mode = true

	# Escalating difficulty
	boss_max_hp_current = BOSS_MAX_HP + boss_encounters * 2
	if boss_max_hp_current > 14:
		boss_max_hp_current = 14
	boss_hp = boss_max_hp_current
	boss_drift_speed = 0.5 + boss_encounters * 0.15
	boss_bomb_timer = BOSS_BOMB_INTERVAL
	boss_timer = BOSS_TIME_LIMIT
	_boss_defeated = false
	_boss_escaped = false

	# Warning text + siren
	_show_boss_warning_text()
	if sfx_boss_siren and not sound_muted:
		sfx_boss_siren.play()

	# Tint background red
	_tint_background_boss()

	# Switch to boss music
	switch_bgm("boss")

	# Hide core sphere during boss mode
	if core_sphere:
		core_sphere.visible = false

	# Tilt world 45 degrees away from the player (delayed to sync with warning)
	# Store the exact target so we can enforce it
	_boss_tilt_target = (PI if world_flipped else 0.0) + BOSS_TILT_ANGLE
	get_tree().create_timer(0.4).timeout.connect(func():
		if not is_boss_mode or not is_inside_tree():
			return
		var tilt_tween = create_tween()
		tilt_tween.tween_property(world_group, "rotation:x", _boss_tilt_target, 1.0).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	)

	# Spawn boss invader (delayed after warning)
	get_tree().create_timer(0.8).timeout.connect(func():
		if not is_boss_mode or not is_inside_tree():
			return
		var boss_info = _get_boss_for_encounter()
		# Set up animation frames if this boss has them
		boss_anim_frames = boss_info.get("anim_frames", [])
		boss_anim_frame = 0
		boss_anim_timer = 0.0
		boss_mesh = MeshInstance3D.new()
		boss_mesh.name = "BossInvader"
		boss_mesh.mesh = _get_boss_mesh_for_level()
		boss_material = StandardMaterial3D.new()
		var bc = boss_info["color"]
		boss_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		boss_material.cull_mode = BaseMaterial3D.CULL_DISABLED
		boss_material.albedo_color = bc
		boss_mesh.material_override = boss_material
		boss_mesh.position = Vector3(0, BOSS_INVADER_HEIGHT, 0)
		boss_mesh.scale = Vector3.ZERO
		add_child(boss_mesh)

		# Dramatic entrance: scale up with bounce
		var enter_tween = create_tween()
		enter_tween.tween_property(boss_mesh, "scale", Vector3(2.5, 2.5, 2.5), 0.8).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		enter_tween.tween_callback(func():
			if not is_boss_mode or not is_inside_tree():
				return
			# Build shield after entrance
			_build_boss_shield()
			# Build HP bar
			_build_boss_hp_bar()
		)
	)

func _fire_boss_bullet(on_hit: Callable = Callable(), is_perfect: bool = false) -> void:
	# Shoot a bullet from the hit target toward the boss
	# Perfect hits: gold/orange bullet, larger, 2x damage
	if not boss_mesh or not is_instance_valid(boss_mesh):
		return

	# Play bullet fire sound
	if sfx_boss_bullet and not sound_muted:
		sfx_boss_bullet.play()

	var mid_r = (CORE_RADIUS + active_radius) / 2.0
	var cx = cos(cursor_angle + PI / 2.0) * mid_r
	var cy = sin(cursor_angle + PI / 2.0) * mid_r
	var start_pos = Vector3(cx, cy, 0.1)
	var target_pos = boss_mesh.position

	var bullet = MeshInstance3D.new()
	bullet.name = "BossBullet"
	var sphere = SphereMesh.new()
	sphere.radius = 0.22 if is_perfect else 0.16
	sphere.height = sphere.radius * 2
	sphere.radial_segments = 12
	sphere.rings = 6
	bullet.mesh = sphere

	var bullet_color = Color(1.0, 0.84, 0.0) if is_perfect else Color(1.0, 1.0, 1.0)
	var mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = bullet_color
	mat.emission_enabled = true
	mat.emission = bullet_color
	mat.emission_energy_multiplier = 2.5 if is_perfect else 2.0
	bullet.material_override = mat
	bullet.position = start_pos
	add_child(bullet)

	# Fly toward boss position
	var fly_time = 0.3
	var tw = create_tween()
	tw.tween_property(bullet, "position", target_pos, fly_time).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.tween_callback(func():
		if is_instance_valid(bullet):
			_spawn_boss_sparks(6)
			bullet.queue_free()
		# Apply damage on bullet arrival
		if on_hit.is_valid():
			on_hit.call()
	)

func _flash_boss_hit() -> void:
	if not boss_mesh or not is_instance_valid(boss_mesh) or not boss_material:
		return
	var original_color = boss_material.albedo_color
	boss_material.albedo_color = Color.WHITE
	var tween = create_tween()
	tween.tween_property(boss_material, "albedo_color", original_color, 0.2)

	# Shake the invader (offset from current drift position)
	var base_pos = boss_mesh.position
	var shake_tween = create_tween()
	shake_tween.tween_property(boss_mesh, "position", base_pos + Vector3(randf_range(-0.15, 0.15), randf_range(-0.1, 0.1), 0), 0.05)
	shake_tween.tween_property(boss_mesh, "position", base_pos + Vector3(randf_range(-0.15, 0.15), randf_range(-0.1, 0.1), 0), 0.05)
	shake_tween.tween_property(boss_mesh, "position", base_pos, 0.05)

	# Impact sparks
	_spawn_boss_sparks(8)

func _explode_boss_into_pixels() -> void:
	# Death animation: break invader mesh into individual pixel pieces
	if not boss_mesh or not is_instance_valid(boss_mesh):
		return
	var pos = boss_mesh.global_position
	var boss_scale = boss_mesh.scale
	var mesh = boss_mesh.mesh as ArrayMesh
	if not mesh or mesh.get_surface_count() == 0:
		return
	var arrays = mesh.surface_get_arrays(0)
	var verts = arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
	if verts.size() < 8:
		return
	# Every 8 vertices = 1 pixel cell (4 line edges)
	var piece_count = 0
	var i = 0
	while i < verts.size() - 7 and piece_count < 60:
		# Average the 8 vertices to get cell center
		var center = Vector3.ZERO
		for v in range(8):
			center += verts[i + v]
		center /= 8.0
		# Transform to world space
		var world_pos = pos + center * boss_scale.x
		var piece = MeshInstance3D.new()
		var box = BoxMesh.new()
		box.size = Vector3(0.1, 0.1, 0.02) * boss_scale.x
		piece.mesh = box
		var mat = StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = boss_material.albedo_color if boss_material else Color(1.0, 0.2, 0.2)
		if current_ui_theme == "vectrex":
			mat.emission_enabled = true
			mat.emission = mat.albedo_color
		piece.material_override = mat
		add_child(piece)
		piece.global_position = world_pos
		# Scatter outward with gravity
		var dir = (center.normalized() + Vector3(randf_range(-0.3, 0.3), randf_range(0.2, 0.8), randf_range(-0.2, 0.2))).normalized()
		var velocity = dir * randf_range(1.5, 4.0)
		var end_pos = piece.position + velocity
		end_pos.y -= 2.0  # Gravity pull
		var tw = create_tween()
		tw.set_parallel(true)
		tw.tween_property(piece, "position", end_pos, 1.0).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		tw.tween_property(piece, "rotation", Vector3(randf_range(-8, 8), randf_range(-8, 8), randf_range(-8, 8)), 1.0)
		tw.tween_property(piece, "scale", Vector3.ZERO, 1.0).set_ease(Tween.EASE_IN)
		tw.tween_property(mat, "albedo_color:a", 0.0, 1.0)
		tw.set_parallel(false)
		tw.tween_callback(piece.queue_free)
		piece_count += 1
		i += 8

func _open_clamshell(duration: float = 0.6) -> void:
	# Flatten the sphere vertically to simulate opening
	if not core_sphere or not is_instance_valid(core_sphere):
		return
	core_sphere.visible = true
	var tw = create_tween()
	tw.tween_property(core_sphere, "scale", Vector3(1.3, 0.3, 1.3), duration).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)

func _close_clamshell(duration: float = 0.4) -> void:
	# Restore sphere to normal
	if not core_sphere or not is_instance_valid(core_sphere):
		return
	var tw = create_tween()
	tw.tween_property(core_sphere, "scale", Vector3.ONE, duration).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)

func _defeat_boss() -> void:
	if not is_boss_mode or _boss_defeated or _boss_escaped:
		return
	is_boss_mode = false
	_boss_defeated = true

	# Clean up shield, HP bar, bombs immediately
	if boss_shield_mesh and is_instance_valid(boss_shield_mesh):
		boss_shield_mesh.queue_free()
		boss_shield_mesh = null
	boss_shield_material = null
	_clear_boss_hp_bar()
	_clear_boss_bombs()

	# Play tractor beam sound
	if sfx_tractor_beam and not sound_muted:
		sfx_tractor_beam.play()

	# Open the clamshell sphere to receive the boss
	_open_clamshell(0.6)

	# --- Tractor Beam: parabolic funnel mesh with animated scrolling rings shader ---
	var beam_node = Node3D.new()
	beam_node.name = "TractorBeam"
	add_child(beam_node)

	var boss_y = BOSS_INVADER_HEIGHT if not boss_mesh or not is_instance_valid(boss_mesh) else boss_mesh.position.y

	# Build gravity well mesh: wide flat disc at top curving into narrow stem
	var funnel = MeshInstance3D.new()
	funnel.name = "FunnelMesh"
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var funnel_segments = 40
	var funnel_rings_count = 30
	var well_radius = 4.0       # Wide flat disc radius
	var stem_radius = 0.15      # Narrow bottom
	var well_depth = boss_y     # Total depth
	for ri in range(funnel_rings_count):
		var t0 = float(ri) / float(funnel_rings_count)
		var t1 = float(ri + 1) / float(funnel_rings_count)
		# Gravity well profile: steep vertical walls at bottom, flat horizontal at top
		# Like 1/r potential: y drops sharply as r approaches 0
		# Parametric with t=0 at top (wide), t=1 at bottom (narrow):
		# Radius stays wide for most of the range, then plunges near t=1
		# r(t) = well_radius / (1 + k*t^2) — hyperbolic-like profile
		var k = 25.0  # Steepness: higher = steeper walls, flatter top
		var r0 = well_radius / (1.0 + k * t0 * t0) + stem_radius
		var r1 = well_radius / (1.0 + k * t1 * t1) + stem_radius
		# Height drops steeply near the stem
		var y0 = well_depth * (1.0 - t0 * t0)
		var y1 = well_depth * (1.0 - t1 * t1)
		for si in range(funnel_segments):
			var a0 = TAU * float(si) / float(funnel_segments)
			var a1 = TAU * float(si + 1) / float(funnel_segments)
			var uv00 = Vector2(float(si) / float(funnel_segments), t0)
			var uv10 = Vector2(float(si + 1) / float(funnel_segments), t0)
			var uv01 = Vector2(float(si) / float(funnel_segments), t1)
			var uv11 = Vector2(float(si + 1) / float(funnel_segments), t1)
			var v00 = Vector3(cos(a0) * r0, y0, sin(a0) * r0)
			var v10 = Vector3(cos(a1) * r0, y0, sin(a1) * r0)
			var v01 = Vector3(cos(a0) * r1, y1, sin(a0) * r1)
			var v11 = Vector3(cos(a1) * r1, y1, sin(a1) * r1)
			var n = -(v00 - Vector3(0, y0, 0)).normalized()
			st.set_normal(n); st.set_uv(uv00); st.add_vertex(v00)
			st.set_normal(n); st.set_uv(uv01); st.add_vertex(v01)
			st.set_normal(n); st.set_uv(uv11); st.add_vertex(v11)
			st.set_normal(n); st.set_uv(uv00); st.add_vertex(v00)
			st.set_normal(n); st.set_uv(uv11); st.add_vertex(v11)
			st.set_normal(n); st.set_uv(uv10); st.add_vertex(v10)
	funnel.mesh = st.commit()
	# Tilt for 3D perspective view (like the reference image)
	beam_node.rotation.x = deg_to_rad(-25)

	# Animated shader: scrolling ring bands down the funnel
	var funnel_shader = Shader.new()
	funnel_shader.code = """
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled;
uniform float ring_speed : hint_range(0.0, 10.0) = 3.0;
uniform float ring_spacing : hint_range(0.01, 1.0) = 0.12;
uniform float ring_width : hint_range(0.001, 0.1) = 0.04;
uniform vec3 color1 : source_color = vec3(0.0, 1.0, 1.0);
uniform vec3 color2 : source_color = vec3(0.1, 0.3, 1.0);
uniform vec3 color3 : source_color = vec3(0.85, 0.1, 0.85);
uniform float base_alpha : hint_range(0.0, 1.0) = 0.7;
void fragment() {
	float scroll = UV.y + TIME * ring_speed;
	float ring = abs(fract(scroll / ring_spacing) - 0.5) * 2.0;
	float ring_mask = smoothstep(1.0 - ring_width / ring_spacing, 1.0, ring);
	// Cycle through 3 colors based on ring index
	float ring_idx = floor(scroll / ring_spacing);
	int color_idx = int(mod(ring_idx, 3.0));
	vec3 col = color1;
	if (color_idx == 1) col = color2;
	else if (color_idx == 2) col = color3;
	// Fade at edges (top and bottom of funnel)
	float edge_fade = smoothstep(0.0, 0.1, UV.y) * smoothstep(0.0, 0.1, 1.0 - UV.y);
	ALBEDO = col;
	ALPHA = ring_mask * base_alpha * edge_fade;
}
"""
	var funnel_mat = ShaderMaterial.new()
	funnel_mat.shader = funnel_shader
	funnel_mat.set_shader_parameter("ring_speed", 3.0)
	funnel_mat.set_shader_parameter("ring_spacing", 0.12)
	funnel_mat.set_shader_parameter("ring_width", 0.04)
	funnel_mat.set_shader_parameter("color1", Vector3(0.0, 1.0, 1.0))
	funnel_mat.set_shader_parameter("color2", Vector3(0.1, 0.3, 1.0))
	funnel_mat.set_shader_parameter("color3", Vector3(0.85, 0.1, 0.85))
	funnel_mat.set_shader_parameter("base_alpha", 0.0)  # Start invisible
	funnel.material_override = funnel_mat
	beam_node.add_child(funnel)

	# PHASE 1: Fade funnel in (grows from hub upward)
	funnel.scale = Vector3(0.01, 0.01, 0.01)
	var grow_tw = create_tween()
	grow_tw.set_parallel(true)
	grow_tw.tween_property(funnel, "scale", Vector3(1.0, 1.0, 1.0), 0.8).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	grow_tw.tween_method(func(v): funnel_mat.set_shader_parameter("base_alpha", v), 0.0, 0.75, 0.8)

	# PHASE 2: Pull boss down through funnel
	var form_time = 0.8
	if boss_mesh and is_instance_valid(boss_mesh):
		var pull_mesh = boss_mesh  # Capture reference for callback
		var pull_tw = create_tween()
		pull_tw.tween_interval(form_time)
		pull_tw.tween_property(pull_mesh, "position", Vector3(0, 0, 0), 1.8).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		pull_tw.parallel().tween_property(pull_mesh, "scale", Vector3.ZERO, 1.8).set_ease(Tween.EASE_IN)
		pull_tw.parallel().tween_property(pull_mesh, "rotation:y", pull_mesh.rotation.y + TAU * 3, 1.8)
		# Free immediately when pull completes — no lingering tiny boss
		pull_tw.tween_callback(func():
			if is_instance_valid(pull_mesh):
				pull_mesh.queue_free()
			if boss_mesh == pull_mesh:
				boss_mesh = null
		)

	# PHASE 3: Capture complete — flash, shrink funnel, clean up
	var capture_time = form_time + 1.8
	get_tree().create_timer(capture_time).timeout.connect(func():
		if not is_inside_tree():
			return

		if core_material:
			var oc = core_material.albedo_color
			core_material.albedo_color = Color.WHITE
			create_tween().tween_property(core_material, "albedo_color", oc, 0.4)

		spawn_ring_burst(Vector3.ZERO, Color(0.0, 1.0, 1.0))
		get_tree().create_timer(0.1).timeout.connect(func():
			if is_inside_tree(): spawn_ring_burst(Vector3.ZERO, Color(0.1, 0.3, 1.0))
		)
		get_tree().create_timer(0.2).timeout.connect(func():
			if is_inside_tree(): spawn_ring_burst(Vector3.ZERO, Color(0.85, 0.1, 0.85))
		)

		if boss_mesh and is_instance_valid(boss_mesh):
			boss_mesh.queue_free()
			boss_mesh = null
		haptic_heavy()

		# Close the clamshell sphere
		_close_clamshell(0.4)

		# Shrink funnel back into hub
		if is_instance_valid(beam_node):
			var collapse = create_tween()
			collapse.set_parallel(true)
			collapse.tween_property(funnel, "scale", Vector3(0.01, 0.01, 0.01), 0.5).set_ease(Tween.EASE_IN)
			collapse.tween_method(func(v): funnel_mat.set_shader_parameter("base_alpha", v), 0.75, 0.0, 0.5)
			collapse.set_parallel(false)
			collapse.tween_callback(beam_node.queue_free)
	)

	# 4. After everything settles, do the post-capture (tilt back, awards, etc.)
	var post_capture_delay = capture_time + 0.8
	get_tree().create_timer(post_capture_delay).timeout.connect(func():
		if not is_inside_tree():
			return

		# Tilt world back
		var flip_base = PI if world_flipped else 0.0
		var untilt_tween = create_tween()
		untilt_tween.tween_property(world_group, "rotation:x", flip_base, 1.0).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		untilt_tween.tween_callback(func():
			world_group.rotation.x = flip_base
		)

		# Restore background
		_restore_background_tint()

		# Show core sphere again
		if core_sphere:
			core_sphere.visible = true

		# Switch back to ambient music
		switch_bgm("ambient")

		# Increment encounter count
		boss_encounters += 1

		# Award trophy + always show captured message
		var boss_info = _get_boss_for_encounter()
		var trophy_key = boss_info["key"]
		if not trophies_unlocked.get(trophy_key, false):
			trophies_unlocked[trophy_key] = true
			_save_settings()
		_show_trophy_unlocked_text(boss_info["name"])

		# Frenzy grace
		boss_frenzy_grace = 5

		# End boss mode
		is_boss_mode = false
		boss_hp = 0
		boss_material = null

		# Check if level was complete before or during boss fight
		if _level_complete_deferred or level_hits >= hits_required:
			_level_complete_deferred = false
			get_tree().create_timer(0.5).timeout.connect(func():
				if current_state == GameState.PLAYING and is_inside_tree():
					trigger_level_complete()
			)
		else:
			# Bonus ring (only if level isn't ending)
			if ring_count < MAX_RINGS:
				get_tree().create_timer(1.2).timeout.connect(func():
					if current_state == GameState.PLAYING and is_inside_tree():
						is_expand_target = true
						do_expand()
				)
	)

func _end_boss_mode() -> void:
	# Clean exit without fanfare (game over / level complete)
	if not is_boss_mode:
		return
	is_boss_mode = false
	boss_hp = 0

	if boss_mesh and is_instance_valid(boss_mesh):
		boss_mesh.queue_free()
		boss_mesh = null
	boss_material = null
	if boss_shield_mesh and is_instance_valid(boss_shield_mesh):
		boss_shield_mesh.queue_free()
		boss_shield_mesh = null
	boss_shield_material = null
	_clear_boss_hp_bar()
	_clear_boss_bombs()

	# Tilt world back to zero (or PI if flipped)
	var flip_base = PI if world_flipped else 0.0
	var untilt = create_tween()
	untilt.tween_property(world_group, "rotation:x", flip_base, 0.5).set_ease(Tween.EASE_IN_OUT)
	untilt.tween_callback(func():
		world_group.rotation.x = flip_base
	)

	# Restore background
	_restore_background_tint()

	# Show core sphere again
	if core_sphere:
		core_sphere.visible = true

	# Switch back to ambient
	switch_bgm("ambient")

func _create_arc_mesh(start_angle: float, end_angle: float, inner_r: float, outer_r: float, segments: int = 32) -> ArrayMesh:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var depth = 0.15  # Thin in Z
	var hd = depth / 2.0
	for i in range(segments):
		var a0 = start_angle + (end_angle - start_angle) * float(i) / float(segments)
		var a1 = start_angle + (end_angle - start_angle) * float(i + 1) / float(segments)
		var cos0 = cos(a0)
		var sin0 = sin(a0)
		var cos1 = cos(a1)
		var sin1 = sin(a1)
		# Outer edge vertices
		var o0 = Vector3(cos0 * outer_r, sin0 * outer_r, 0)
		var o1 = Vector3(cos1 * outer_r, sin1 * outer_r, 0)
		# Inner edge vertices
		var i0 = Vector3(cos0 * inner_r, sin0 * inner_r, 0)
		var i1 = Vector3(cos1 * inner_r, sin1 * inner_r, 0)
		# Front face (Z+)
		st.set_normal(Vector3(0, 0, 1))
		st.add_vertex(Vector3(i0.x, i0.y, hd))
		st.add_vertex(Vector3(o0.x, o0.y, hd))
		st.add_vertex(Vector3(o1.x, o1.y, hd))
		st.add_vertex(Vector3(i0.x, i0.y, hd))
		st.add_vertex(Vector3(o1.x, o1.y, hd))
		st.add_vertex(Vector3(i1.x, i1.y, hd))
		# Back face (Z-)
		st.set_normal(Vector3(0, 0, -1))
		st.add_vertex(Vector3(i0.x, i0.y, -hd))
		st.add_vertex(Vector3(o1.x, o1.y, -hd))
		st.add_vertex(Vector3(o0.x, o0.y, -hd))
		st.add_vertex(Vector3(i0.x, i0.y, -hd))
		st.add_vertex(Vector3(i1.x, i1.y, -hd))
		st.add_vertex(Vector3(o1.x, o1.y, -hd))
	return st.commit()

func _build_streak_arcs() -> void:
	# Remove old arcs
	for arc in streak_arcs:
		if is_instance_valid(arc):
			arc.queue_free()
	streak_arcs.clear()
	streak_arc_materials.clear()

	var gap_angle = deg_to_rad(6)  # Gap between segments
	var total_arc = TAU - FRENZY_THRESHOLD * gap_angle
	var segment_arc = total_arc / FRENZY_THRESHOLD
	var inner_r = CORE_RADIUS + 0.04
	var outer_r = CORE_RADIUS + 0.12

	for i in range(FRENZY_THRESHOLD):
		var start_a = (TAU / FRENZY_THRESHOLD) * i + gap_angle / 2.0 - PI / 2.0
		var end_a = start_a + segment_arc
		var arc_mesh_inst = MeshInstance3D.new()
		arc_mesh_inst.name = "StreakArc%d" % i
		arc_mesh_inst.mesh = _create_arc_mesh(start_a, end_a, inner_r, outer_r)
		var mat = StandardMaterial3D.new()
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(1, 1, 1, 0.08)  # Gray/dim by default
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.no_depth_test = true
		mat.render_priority = 5
		arc_mesh_inst.material_override = mat
		add_child(arc_mesh_inst)
		streak_arcs.append(arc_mesh_inst)
		streak_arc_materials.append(mat)

func _update_streak_bar() -> void:
	if streak_arc_materials.size() < FRENZY_THRESHOLD:
		return
	var gray = Color(1, 1, 1, 0.08)
	var gold = Color(1.0, 0.84, 0.0, 0.7)
	for i in range(FRENZY_THRESHOLD):
		if frenzy_streak > i:
			streak_arc_materials[i].albedo_color = gold
		else:
			streak_arc_materials[i].albedo_color = gray

func _spawn_streak_bubble(bonus_hits: int = 0) -> void:
	if frenzy_streak < 2:
		# Still apply bonus immediately if no bubble
		if bonus_hits > 0:
			_apply_bonus_hits(bonus_hits)
		return

	# --- Build circular bubble with "×N" text ---
	var container = Node3D.new()
	container.name = "StreakBubble"
	add_child(container)
	container.global_position = target_mesh.global_position + Vector3(0, 0, 0.5)

	# Determine bubble color based on theme
	var tc = _theme_colors(current_ui_theme, current_hue)
	var bubble_color: Color
	if current_ui_theme == "vectrex":
		bubble_color = tc["accent"]
	elif is_frenzy_active:
		bubble_color = Color(1.0, 0.84, 0.0)
	else:
		bubble_color = Color.WHITE

	# Circle background (disc mesh) — compact
	var disc = MeshInstance3D.new()
	var disc_mesh = SphereMesh.new()
	disc_mesh.radius = 0.1
	disc_mesh.height = 0.03
	disc_mesh.radial_segments = 24
	disc_mesh.rings = 4
	disc.mesh = disc_mesh
	var disc_mat = StandardMaterial3D.new()
	disc_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	disc_mat.albedo_color = Color(0.05, 0.05, 0.08, 0.9)  # Dark background
	disc_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if current_ui_theme == "vectrex":
		disc_mat.emission_enabled = true
		disc_mat.emission = Color(bubble_color.r * 0.5, bubble_color.g * 0.5, bubble_color.b * 0.5)
		disc_mat.emission_energy_multiplier = 1.0
	disc.material_override = disc_mat
	disc_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	container.add_child(disc)

	# Ring border around the disc — compact
	var ring = MeshInstance3D.new()
	var ring_mesh = TorusMesh.new()
	ring_mesh.inner_radius = 0.09
	ring_mesh.outer_radius = 0.11
	ring_mesh.rings = 24
	ring_mesh.ring_segments = 8
	ring.mesh = ring_mesh
	var ring_mat = StandardMaterial3D.new()
	ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_mat.albedo_color = Color(1.0, 1.0, 1.0, 0.95)  # White border
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if current_ui_theme == "vectrex":
		ring_mat.emission_enabled = true
		ring_mat.emission = Color(bubble_color.r * 1.2, bubble_color.g * 1.2, bubble_color.b * 1.2)
		ring_mat.emission_energy_multiplier = 1.2
	ring.material_override = ring_mat
	ring_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	container.add_child(ring)

	# Text label
	var lbl = Label3D.new()
	lbl.text = "×%d" % frenzy_streak
	lbl.font_size = 48
	lbl.pixel_size = 0.008
	if font_bold:
		lbl.font = font_bold
	lbl.modulate = bubble_color
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.no_depth_test = true
	lbl.render_priority = 16
	lbl.position = Vector3(0, 0, 0.05)
	container.add_child(lbl)

	# --- Animate: float to hub center ---
	var destination = Vector3(0, 0, 0.5)
	var fly_duration = 0.5
	var tween = container.create_tween()
	tween.set_parallel(true)
	# Move to center
	tween.tween_property(container, "global_position", destination, fly_duration).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	# Pop up then shrink as it approaches
	tween.tween_property(container, "scale", Vector3(1.2, 1.2, 1.2), 0.1).set_ease(Tween.EASE_OUT)
	tween.chain().tween_property(container, "scale", Vector3(0.4, 0.4, 0.4), fly_duration - 0.1).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)

	# --- On arrival: apply bonus hits + flash + cleanup ---
	tween.set_parallel(false)
	tween.tween_callback(func():
		if not is_instance_valid(self):
			return
		# Apply the deferred bonus hits
		if bonus_hits > 0:
			_apply_bonus_hits(bonus_hits)
		# Flash the core to show impact
		_flash_core_white()
	)
	# Quick fade out after impact
	tween.tween_property(container, "scale", Vector3(0.01, 0.01, 0.01), 0.15).set_ease(Tween.EASE_IN)
	tween.tween_callback(container.queue_free)

func _apply_bonus_hits(count: int) -> void:
	# Don't apply bonus hits during boss mode — counter is frozen
	if is_boss_mode:
		return
	level_hits = mini(level_hits + count, hits_required)
	score = maxi(hits_required - level_hits, 0)
	_pump_score(str(score))
	if progress_label:
		progress_label.text = str(level_hits) + " / " + str(hits_required)
	update_progress_ring()
	if level_hits >= hits_required and current_state == GameState.PLAYING:
		if frenzy_streak > 0 and frenzy_streak < BOSS_TRIGGER_STREAK:
			_level_complete_deferred = true
		else:
			trigger_level_complete()

func _flash_core_white() -> void:
	if not core_material:
		return
	var original_color = core_material.albedo_color
	var white = Color(1.0, 1.0, 1.0, 0.9)
	core_material.albedo_color = white
	var tween = create_tween()
	tween.tween_property(core_material, "albedo_color", original_color, 0.1)

func _show_miss_text(text: String = "MISSED!") -> void:
	var lbl = Label3D.new()
	lbl.text = text
	lbl.font_size = 64
	if font_bold:
		lbl.font = font_bold
	lbl.modulate = Color(COLOR_CURSOR.r, COLOR_CURSOR.g, COLOR_CURSOR.b, 1.0)
	lbl.outline_modulate = Color(COLOR_CURSOR.r, COLOR_CURSOR.g, COLOR_CURSOR.b, 0.6)
	lbl.outline_size = 4
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.no_depth_test = true
	lbl.position = Vector3(0, -(active_radius + 0.6), 1.0)
	world_group.add_child(lbl)
	var t = create_tween()
	t.set_parallel(true)
	t.tween_property(lbl, "position:y", -(active_radius + 1.2), 0.6).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	t.tween_property(lbl, "modulate:a", 0.0, 0.6).set_ease(Tween.EASE_IN)
	t.tween_property(lbl, "outline_modulate:a", 0.0, 0.6).set_ease(Tween.EASE_IN)
	t.chain().tween_callback(lbl.queue_free)

func _show_ring_added_text() -> void:
	var lbl = Label3D.new()
	lbl.text = "RING ADDED!"
	lbl.font_size = 64
	if font_bold:
		lbl.font = font_bold
	lbl.modulate = Color(COLOR_TARGET_EXPAND.r, COLOR_TARGET_EXPAND.g, COLOR_TARGET_EXPAND.b, 1.0)
	lbl.outline_modulate = Color(COLOR_TARGET_EXPAND.r, COLOR_TARGET_EXPAND.g, COLOR_TARGET_EXPAND.b, 0.6)
	lbl.outline_size = 4
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.no_depth_test = true
	lbl.position = Vector3(0, active_radius + 0.6, 1.0)
	world_group.add_child(lbl)
	var t = create_tween()
	t.set_parallel(true)
	t.tween_property(lbl, "position:y", active_radius + 1.2, 0.6).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	t.tween_property(lbl, "modulate:a", 0.0, 0.6).set_ease(Tween.EASE_IN)
	t.tween_property(lbl, "outline_modulate:a", 0.0, 0.6).set_ease(Tween.EASE_IN)
	t.chain().tween_callback(lbl.queue_free)

func _show_perfect_text() -> void:
	var lbl = Label3D.new()
	lbl.text = "PERFECT"
	lbl.font_size = 64
	if font_bold:
		lbl.font = font_bold
	lbl.modulate = Color(1.0, 0.84, 0.0, 1.0)
	lbl.outline_modulate = Color(1.0, 0.84, 0.0, 0.6)
	lbl.outline_size = 4
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.no_depth_test = true
	lbl.position = Vector3(0, active_radius + 0.6, 1.0)
	world_group.add_child(lbl)
	var t = create_tween()
	t.set_parallel(true)
	t.tween_property(lbl, "position:y", active_radius + 1.2, 0.6).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	t.tween_property(lbl, "modulate:a", 0.0, 0.6).set_ease(Tween.EASE_IN)
	t.tween_property(lbl, "outline_modulate:a", 0.0, 0.6).set_ease(Tween.EASE_IN)
	t.chain().tween_callback(lbl.queue_free)

# Score counter — punch scale animation
# Number stays in place, punches big then snaps back on each change
var _score_tween: Tween = null

func _pump_score(new_text: String) -> void:
	if not score_label:
		return
	if new_text.begins_with("-"):
		new_text = "0"
	if score_label.text == new_text:
		return

	# Kill any in-progress animation
	if _score_tween and _score_tween.is_valid():
		_score_tween.kill()

	# Reset
	score_label.scale = Vector3.ONE
	score_label.modulate.a = 1.0
	score_label.position.y = 0.0

	# Set new text immediately
	score_label.text = new_text

	# Punch scale: pop up big then snap back
	_score_tween = create_tween()
	_score_tween.tween_property(score_label, "scale", Vector3(1.4, 1.4, 1.4), 0.08).set_ease(Tween.EASE_OUT)
	_score_tween.tween_property(score_label, "scale", Vector3.ONE, 0.15).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_BACK)

# Odometer effect for level label (2D Label) — old slides up + fades, new slides in from below
var _level_odo_tween: Tween = null

func _pump_level(new_text: String) -> void:
	if not level_label:
		return
	level_label.text = new_text

# ===== DAILY CHALLENGE =====

func get_daily_seed() -> int:
	return star_manager._get_today_string().hash() if star_manager else Time.get_unix_time_from_system() as int

func start_daily_challenge() -> void:
	is_daily_challenge = true
	current_level = 10  # Fixed difficulty
	level_hits = 0
	start_game()

# ===== AUDIO SYSTEM =====

func build_audio() -> void:
	# Match start - ascending two-tone chime (orbital launch feel)
	sfx_start = AudioStreamPlayer.new()
	sfx_start.stream = _gen_dual_tone(330.0, 660.0, 0.1, 0.08, 0.9)
	sfx_start.volume_db = 0
	add_child(sfx_start)

	# Target hit - crisp metallic ping with harmonic overtone
	sfx_hit = AudioStreamPlayer.new()
	sfx_hit.stream = _gen_harmonic_ping(587.0, 0.15, 0.85)
	sfx_hit.volume_db = 0
	add_child(sfx_hit)

	# Miss / game over - descending wobble (detuned low tone)
	sfx_miss = AudioStreamPlayer.new()
	sfx_miss.stream = _gen_wobble_down(220.0, 110.0, 0.4, 0.9)
	sfx_miss.volume_db = 0
	add_child(sfx_miss)

	# Flip - whooshing phase sweep (two detuned sweeps crossing)
	sfx_flip = AudioStreamPlayer.new()
	sfx_flip.stream = _gen_phase_whoosh(350.0, 700.0, 0.35, 0.85)
	sfx_flip.volume_db = 0
	add_child(sfx_flip)

	# Ring expand - deep resonant boom with rising shimmer
	sfx_expand = AudioStreamPlayer.new()
	sfx_expand.stream = _gen_boom_shimmer(130.0, 520.0, 0.45, 0.9)
	sfx_expand.volume_db = 0
	add_child(sfx_expand)

	# Level complete - bright major arpeggio with shimmer
	sfx_level_complete = AudioStreamPlayer.new()
	sfx_level_complete.stream = _gen_victory_arp([523.0, 659.0, 784.0, 1047.0], 0.14, 0.9)
	sfx_level_complete.volume_db = 2
	add_child(sfx_level_complete)

	# Perfect hit - 880Hz crystal chime with shimmer
	sfx_perfect_hit = AudioStreamPlayer.new()
	sfx_perfect_hit.stream = _gen_crystal_chime(880.0, 0.1, 0.85)
	sfx_perfect_hit.volume_db = 1
	add_child(sfx_perfect_hit)

	# Pre-generate rising streak chimes (10 semitone steps + shimmer chord)
	_streak_chimes.clear()
	for i in range(10):
		var freq = 880.0 * pow(1.05946, float(i))
		_streak_chimes.append(_gen_crystal_chime(freq, 0.1, 0.85))
	_streak_chimes.append(_gen_shimmer_chord(0.15, 0.85))

	# Boss siren
	sfx_boss_siren = AudioStreamPlayer.new()
	sfx_boss_siren.stream = _gen_boss_siren(1.2, 0.7)
	sfx_boss_siren.volume_db = 0
	add_child(sfx_boss_siren)

	# Boss bullet fire sound (short laser zap)
	sfx_boss_bullet = AudioStreamPlayer.new()
	sfx_boss_bullet.stream = _gen_bullet_zap(0.1, 0.7)
	sfx_boss_bullet.volume_db = 0
	add_child(sfx_boss_bullet)

	# Boss escape sound (sad descending melody)
	sfx_boss_escape = AudioStreamPlayer.new()
	sfx_boss_escape.stream = _gen_boss_escape(0.8, 0.7)
	sfx_boss_escape.volume_db = 0
	add_child(sfx_boss_escape)

	# Tractor beam capture sound
	sfx_tractor_beam = AudioStreamPlayer.new()
	sfx_tractor_beam.stream = _gen_tractor_beam(2.0, 0.6)
	sfx_tractor_beam.volume_db = 1
	add_child(sfx_tractor_beam)

	# Background music - pre-generate both tracks
	bgm_ambient = _gen_ambient_loop(25.0, 0.35)
	bgm_ambient.loop_mode = AudioStreamWAV.LOOP_FORWARD
	bgm_ambient.loop_end = int(sample_rate * 25.0)
	bgm_boss = _gen_boss_loop(25.0, 0.4)
	bgm_boss.loop_mode = AudioStreamWAV.LOOP_FORWARD
	bgm_boss.loop_end = int(sample_rate * 25.0)
	bgm_player = AudioStreamPlayer.new()
	bgm_player.stream = bgm_ambient
	bgm_player.volume_db = -6
	add_child(bgm_player)
	bgm_player.play()

func toggle_mute() -> void:
	sound_muted = not sound_muted
	if bgm_player:
		if sound_muted:
			bgm_player.stop()
		else:
			bgm_player.play()

func switch_bgm(track_name: String) -> void:
	current_bgm = track_name
	if not bgm_player:
		return
	var was_playing = bgm_player.playing
	bgm_player.stop()
	match track_name:
		"ambient":
			bgm_player.stream = bgm_ambient
		"boss":
			bgm_player.stream = bgm_boss
	if was_playing and not sound_muted:
		bgm_player.play()

func play_start_sound() -> void:
	if sound_muted or not sfx_start:
		return
	sfx_start.play()

func play_hit_sound() -> void:
	if sound_muted or not sfx_hit:
		return
	sfx_hit.play()

func play_perfect_hit_sound() -> void:
	if sound_muted or not sfx_perfect_hit:
		return
	if _streak_chimes.size() > 0:
		var idx = clampi(frenzy_streak, 0, _streak_chimes.size() - 1)
		sfx_perfect_hit.stream = _streak_chimes[idx]
	sfx_perfect_hit.play()

func play_miss_sound() -> void:
	if sound_muted or not sfx_miss:
		return
	sfx_miss.play()

func play_flip_sound() -> void:
	if sound_muted or not sfx_flip:
		return
	sfx_flip.play()

func play_expand_sound() -> void:
	if sound_muted or not sfx_expand:
		return
	sfx_expand.play()

func play_level_complete_sound() -> void:
	if sound_muted or not sfx_level_complete:
		return
	sfx_level_complete.play()

# ===== SOUND GENERATORS =====
# Uses CubePlanet's proven pattern: t * freq * TAU for phase calculation

func _gen_dual_tone(freq1: float, freq2: float, dur1: float, dur2: float, vol: float) -> AudioStreamWAV:
	var total = dur1 + dur2
	var samples = int(sample_rate * total)
	var data = PackedByteArray()
	data.resize(samples * 2)
	for i in range(samples):
		var t = float(i) / sample_rate
		var progress = float(i) / float(samples)
		var freq: float
		var local_progress: float
		if t < dur1:
			freq = freq1
			local_progress = t / dur1
		else:
			freq = freq2
			local_progress = (t - dur1) / dur2
		var envelope = exp(-local_progress * 8.0)
		var sample_value = sin(t * freq * TAU) * 0.6 + sin(t * freq * 2.0 * TAU) * 0.3 + sin(t * freq * 3.0 * TAU) * 0.1
		sample_value *= envelope * vol
		var sample_int = int(clamp(sample_value * 32767.0, -32768.0, 32767.0))
		data[i * 2] = sample_int & 0xFF
		data[i * 2 + 1] = (sample_int >> 8) & 0xFF
	return _make_wav(data)

func _gen_harmonic_ping(freq: float, duration: float, vol: float) -> AudioStreamWAV:
	# Metallic bell/anvil sound using inharmonic partials for metallic timbre
	var samples = int(sample_rate * duration)
	var data = PackedByteArray()
	data.resize(samples * 2)
	# Inharmonic ratios give metallic quality (like a struck bell or anvil)
	var ratios = [1.0, 2.76, 4.07, 5.93, 8.15]
	var amps = [0.40, 0.25, 0.18, 0.10, 0.07]
	# Slight detuning per partial for shimmer
	var detune = [0.0, 1.003, 0.997, 1.005, 0.998]
	# Each partial decays at a different rate (higher partials decay faster)
	var decay_rates = [6.0, 9.0, 12.0, 16.0, 20.0]
	for i in range(samples):
		var t = float(i) / sample_rate
		var progress = float(i) / float(samples)
		# Sharp attack envelope (instant on, ringing decay)
		var attack = min(progress * 200.0, 1.0)  # ~5ms attack
		var sample_value = 0.0
		for p in range(ratios.size()):
			var partial_freq = freq * ratios[p] * detune[p]
			var partial_env = exp(-progress * decay_rates[p])
			sample_value += sin(t * partial_freq * TAU) * amps[p] * partial_env
		sample_value *= attack * vol
		var sample_int = int(clamp(sample_value * 32767.0, -32768.0, 32767.0))
		data[i * 2] = sample_int & 0xFF
		data[i * 2 + 1] = (sample_int >> 8) & 0xFF
	return _make_wav(data)

func _gen_wobble_down(start_freq: float, end_freq: float, duration: float, vol: float) -> AudioStreamWAV:
	var samples = int(sample_rate * duration)
	var data = PackedByteArray()
	data.resize(samples * 2)
	for i in range(samples):
		var t = float(i) / sample_rate
		var progress = float(i) / float(samples)
		var freq = lerp(start_freq, end_freq, progress)
		var vibrato = sin(t * 28.0) * freq * 0.05 * progress
		freq += vibrato
		var envelope = exp(-progress * 4.0)
		var sample_value = sin(t * freq * TAU) * 0.6 + sin(t * freq * 0.5 * TAU) * 0.4
		sample_value *= envelope * vol
		var sample_int = int(clamp(sample_value * 32767.0, -32768.0, 32767.0))
		data[i * 2] = sample_int & 0xFF
		data[i * 2 + 1] = (sample_int >> 8) & 0xFF
	return _make_wav(data)

func _gen_phase_whoosh(start_freq: float, end_freq: float, duration: float, vol: float) -> AudioStreamWAV:
	var samples = int(sample_rate * duration)
	var data = PackedByteArray()
	data.resize(samples * 2)
	for i in range(samples):
		var t = float(i) / sample_rate
		var progress = float(i) / float(samples)
		var freq1 = lerp(start_freq, end_freq, progress)
		var freq2 = lerp(end_freq, start_freq, progress)
		var s1 = sin(t * freq1 * TAU)
		var s2 = sin(t * freq2 * TAU) * 0.6
		var sample_value = (s1 + s2) * 0.5
		var envelope = sin(progress * PI)
		sample_value *= envelope * vol
		var sample_int = int(clamp(sample_value * 32767.0, -32768.0, 32767.0))
		data[i * 2] = sample_int & 0xFF
		data[i * 2 + 1] = (sample_int >> 8) & 0xFF
	return _make_wav(data)

func _gen_boom_shimmer(low_freq: float, high_freq: float, duration: float, vol: float) -> AudioStreamWAV:
	var samples = int(sample_rate * duration)
	var data = PackedByteArray()
	data.resize(samples * 2)
	for i in range(samples):
		var t = float(i) / sample_rate
		var progress = float(i) / float(samples)
		var boom = sin(t * low_freq * TAU) * exp(-progress * 10.0)
		var shimmer_freq = lerp(high_freq * 0.5, high_freq, progress * progress)
		var shimmer = sin(t * shimmer_freq * TAU) * 0.5 + sin(t * shimmer_freq * 2.0 * TAU) * 0.2
		shimmer *= progress * (1.0 - progress * 0.5)
		var sample_value = (boom * 0.6 + shimmer * 0.4) * vol
		var sample_int = int(clamp(sample_value * 32767.0, -32768.0, 32767.0))
		data[i * 2] = sample_int & 0xFF
		data[i * 2 + 1] = (sample_int >> 8) & 0xFF
	return _make_wav(data)

func _gen_victory_arp(frequencies: Array, note_dur: float, vol: float) -> AudioStreamWAV:
	var total = note_dur * frequencies.size()
	var samples = int(sample_rate * total)
	var samp_per_note = int(sample_rate * note_dur)
	var data = PackedByteArray()
	data.resize(samples * 2)
	for i in range(samples):
		var t = float(i) / sample_rate
		var note_idx = mini(i / samp_per_note, frequencies.size() - 1)
		var freq = frequencies[note_idx]
		var t_in_note = float(i % samp_per_note) / sample_rate
		var prog = t_in_note / note_dur
		var envelope = exp(-prog * 6.0)
		var sample_value = sin(t * freq * TAU) * 0.5 + sin(t * freq * 2.0 * TAU) * 0.25 + sin(t * freq * 1.5 * TAU) * 0.15
		sample_value += sin(t * freq * 4.0 * TAU) * 0.1 * exp(-prog * 12.0)
		sample_value *= envelope * vol
		var sample_int = int(clamp(sample_value * 32767.0, -32768.0, 32767.0))
		data[i * 2] = sample_int & 0xFF
		data[i * 2 + 1] = (sample_int >> 8) & 0xFF
	return _make_wav(data)

func _gen_crystal_chime(freq: float, duration: float, vol: float) -> AudioStreamWAV:
	# Crystal chime with shimmer (detuned second oscillator)
	var samples = int(sample_rate * duration)
	var data = PackedByteArray()
	data.resize(samples * 2)
	var freq2 = freq * 1.003  # Slight detune for shimmer
	for i in range(samples):
		var t = float(i) / sample_rate
		var progress = float(i) / float(samples)
		var attack = min(progress * 200.0, 1.0)  # ~5ms attack
		var envelope = exp(-progress * 12.0)
		var s1 = sin(t * freq * TAU) * 0.5
		var s2 = sin(t * freq2 * TAU) * 0.3
		var s3 = sin(t * freq * 2.0 * TAU) * 0.15  # Octave overtone
		var s4 = sin(t * freq * 3.0 * TAU) * 0.05  # Higher overtone
		var sample_value = (s1 + s2 + s3 + s4) * attack * envelope * vol
		var sample_int = int(clamp(sample_value * 32767.0, -32768.0, 32767.0))
		data[i * 2] = sample_int & 0xFF
		data[i * 2 + 1] = (sample_int >> 8) & 0xFF
	return _make_wav(data)

func _gen_shimmer_chord(duration: float, vol: float) -> AudioStreamWAV:
	# Multi-frequency major triad chord (C6, E6, G6, C7) with detuned shimmer
	var freqs = [1047.0, 1319.0, 1568.0, 2093.0]
	var detune = [1.003, 0.997, 1.005, 0.998]
	var samples = int(sample_rate * duration)
	var data = PackedByteArray()
	data.resize(samples * 2)
	for i in range(samples):
		var t = float(i) / sample_rate
		var progress = float(i) / float(samples)
		var attack = min(progress * 200.0, 1.0)
		var envelope = exp(-progress * 8.0)
		var sample_value = 0.0
		for f_idx in range(freqs.size()):
			var f = freqs[f_idx]
			sample_value += sin(t * f * TAU) * 0.25
			sample_value += sin(t * f * detune[f_idx] * TAU) * 0.15
		sample_value *= attack * envelope * vol
		var sample_int = int(clamp(sample_value * 32767.0, -32768.0, 32767.0))
		data[i * 2] = sample_int & 0xFF
		data[i * 2 + 1] = (sample_int >> 8) & 0xFF
	return _make_wav(data)

func _gen_ambient_loop(duration: float, vol: float) -> AudioStreamWAV:
	# Ambient pad: layered detuned sine drones with slow LFO modulation
	# Chord progression over 25s: Am9 -> Fmaj7 -> Cmaj7 -> Em7 (dreamy, chill)
	var samples = int(sample_rate * duration)
	var data = PackedByteArray()
	data.resize(samples * 2)

	# Four chord voicings (frequencies in Hz) - low register for warmth
	# Am9:   A2, C3, E3, G3, B3
	# Fmaj7: F2, A2, C3, E3
	# Cmaj7: C2, E2, G2, B2
	# Em7:   E2, G2, B2, D3
	var chords: Array = [
		[110.0, 130.81, 164.81, 196.0, 246.94],
		[87.31, 110.0, 130.81, 164.81],
		[65.41, 82.41, 98.0, 123.47],
		[82.41, 98.0, 123.47, 146.83],
	]
	var chord_count = chords.size()
	var chord_dur = duration / float(chord_count)
	var crossfade = 2.0  # seconds of crossfade between chords

	for i in range(samples):
		var t = float(i) / sample_rate
		var progress = t / duration

		# Determine current and next chord with crossfade
		var chord_pos = t / chord_dur
		var chord_idx = int(chord_pos) % chord_count
		var next_idx = (chord_idx + 1) % chord_count
		var chord_t = fmod(t, chord_dur)
		var blend = 0.0
		if chord_t > chord_dur - crossfade:
			blend = (chord_t - (chord_dur - crossfade)) / crossfade

		# Generate pad sound for a chord
		var sample_value = 0.0
		var current_chord = chords[chord_idx]
		var next_chord = chords[next_idx]

		# Current chord voices
		for f_idx in range(current_chord.size()):
			var f = current_chord[f_idx]
			# Slow LFO detune for movement (each voice has different rate)
			var lfo = sin(t * (0.1 + f_idx * 0.07)) * 0.003
			var voice_f = f * (1.0 + lfo)
			# Sine + soft triangle-ish harmonic
			var s = sin(t * voice_f * TAU) * 0.6
			s += sin(t * voice_f * 2.0 * TAU) * 0.15  # Soft octave
			s += sin(t * voice_f * 3.0 * TAU) * 0.05  # Fifth harmonic (quiet)
			# Gentle amplitude LFO (breathing)
			var amp_lfo = 0.85 + 0.15 * sin(t * (0.2 + f_idx * 0.05))
			sample_value += s * amp_lfo * (1.0 - blend) / float(current_chord.size())

		# Next chord voices (crossfade in)
		if blend > 0.0:
			for f_idx in range(next_chord.size()):
				var f = next_chord[f_idx]
				var lfo = sin(t * (0.1 + f_idx * 0.07)) * 0.003
				var voice_f = f * (1.0 + lfo)
				var s = sin(t * voice_f * TAU) * 0.6
				s += sin(t * voice_f * 2.0 * TAU) * 0.15
				s += sin(t * voice_f * 3.0 * TAU) * 0.05
				var amp_lfo = 0.85 + 0.15 * sin(t * (0.2 + f_idx * 0.05))
				sample_value += s * amp_lfo * blend / float(next_chord.size())

		# Add a sub-bass drone (root follows chord, very low)
		var bass_freq = chords[chord_idx][0] * 0.5
		if blend > 0.0:
			bass_freq = lerp(bass_freq, chords[next_idx][0] * 0.5, blend)
		sample_value += sin(t * bass_freq * TAU) * 0.2

		# High shimmer layer - very quiet, adds air
		var shimmer_f = chords[chord_idx][0] * 4.0
		var shimmer = sin(t * shimmer_f * TAU) * 0.03
		shimmer += sin(t * shimmer_f * 1.003 * TAU) * 0.03  # Detuned for chorus
		shimmer *= 0.5 + 0.5 * sin(t * 0.15 * TAU)  # Slow fade in/out
		sample_value += shimmer

		# Global envelope: fade in first 2s, fade out last 2s for seamless loop
		var env = 1.0
		if t < 2.0:
			env = t / 2.0
		elif t > duration - 2.0:
			env = (duration - t) / 2.0
		sample_value *= env * vol

		var sample_int = int(clamp(sample_value * 32767.0, -32768.0, 32767.0))
		data[i * 2] = sample_int & 0xFF
		data[i * 2 + 1] = (sample_int >> 8) & 0xFF
	return _make_wav(data)

func _gen_bullet_zap(duration: float, vol: float) -> AudioStreamWAV:
	# Short ascending zap — laser bullet firing
	var samples = int(sample_rate * duration)
	var data = PackedByteArray()
	data.resize(samples * 2)
	for i in range(samples):
		var t = float(i) / sample_rate
		var progress = t / duration
		var freq = lerp(400.0, 1200.0, progress)
		var env = (1.0 - progress) * (1.0 - progress)
		var raw = sin(t * freq * TAU) * 0.5 + clamp(sin(t * freq * TAU) * 2.0, -1.0, 1.0) * 0.3
		var sample_value = raw * env * vol
		var sample_int = int(clamp(sample_value * 32767.0, -32768.0, 32767.0))
		data[i * 2] = sample_int & 0xFF
		data[i * 2 + 1] = (sample_int >> 8) & 0xFF
	return _make_wav(data)

func _gen_boss_escape(duration: float, vol: float) -> AudioStreamWAV:
	# Sad descending 3-note melody (like losing a prize)
	var samples = int(sample_rate * duration)
	var data = PackedByteArray()
	data.resize(samples * 2)
	var notes = [440.0, 370.0, 311.0]  # A4, F#4, Eb4 — descending minor
	var note_dur = duration / 3.0
	for i in range(samples):
		var t = float(i) / sample_rate
		var note_idx = mini(int(t / note_dur), 2)
		var freq = notes[note_idx]
		var t_in_note = fmod(t, note_dur)
		var env = exp(-t_in_note / note_dur * 4.0)
		var sample_value = sin(t * freq * TAU) * 0.5 + sin(t * freq * 2.0 * TAU) * 0.2
		sample_value *= env * vol
		var sample_int = int(clamp(sample_value * 32767.0, -32768.0, 32767.0))
		data[i * 2] = sample_int & 0xFF
		data[i * 2 + 1] = (sample_int >> 8) & 0xFF
	return _make_wav(data)

func _gen_tractor_beam(duration: float, vol: float) -> AudioStreamWAV:
	# Descending warbling beam sound — oscillating pitch dropping down
	var samples = int(sample_rate * duration)
	var data = PackedByteArray()
	data.resize(samples * 2)
	for i in range(samples):
		var t = float(i) / sample_rate
		var progress = t / duration
		# Base frequency descends from 800Hz to 200Hz
		var base_freq = lerp(800.0, 200.0, progress)
		# Warble: fast oscillation of pitch (like Galaga beam)
		var warble = sin(t * 12.0 * TAU) * 80.0 * (1.0 - progress * 0.5)
		var freq = base_freq + warble
		# Mix sine + slight square for that retro buzzy quality
		var raw = sin(t * freq * TAU) * 0.6
		raw += clamp(sin(t * freq * TAU) * 2.0, -1.0, 1.0) * 0.2  # Soft square
		raw += sin(t * freq * 2.0 * TAU) * 0.15  # Octave harmonic
		# Pulsing amplitude (beam flicker)
		var pulse = 0.7 + 0.3 * sin(t * 8.0 * TAU)
		# Envelope: quick attack, sustain, fade at end
		var env = min(progress * 10.0, 1.0) * (1.0 - max(0.0, (progress - 0.8) / 0.2))
		var sample_value = raw * pulse * env * vol
		var sample_int = int(clamp(sample_value * 32767.0, -32768.0, 32767.0))
		data[i * 2] = sample_int & 0xFF
		data[i * 2 + 1] = (sample_int >> 8) & 0xFF
	return _make_wav(data)

func _gen_boss_siren(duration: float, vol: float) -> AudioStreamWAV:
	# Two-tone alternating alarm siren
	var samples = int(sample_rate * duration)
	var data = PackedByteArray()
	data.resize(samples * 2)
	var freq_lo = 600.0
	var freq_hi = 900.0
	var oscillate_rate = 4.0  # switches per second
	for i in range(samples):
		var t = float(i) / sample_rate
		var progress = float(i) / float(samples)
		# Alternate between two tones
		var blend = (sin(t * oscillate_rate * TAU) + 1.0) / 2.0
		var freq = lerp(freq_lo, freq_hi, blend)
		# Square-ish wave for alarm quality
		var raw = sin(t * freq * TAU)
		raw = clamp(raw * 3.0, -1.0, 1.0)  # Soft clip into square
		raw += sin(t * freq * 2.0 * TAU) * 0.2  # Harmonic edge
		# Envelope: quick attack, sustain, fade at end
		var env = min(progress * 20.0, 1.0) * (1.0 - max(0.0, (progress - 0.7) / 0.3))
		var sample_value = raw * env * vol * 0.5
		var sample_int = int(clamp(sample_value * 32767.0, -32768.0, 32767.0))
		data[i * 2] = sample_int & 0xFF
		data[i * 2 + 1] = (sample_int >> 8) & 0xFF
	return _make_wav(data)

func _gen_boss_loop(duration: float, vol: float) -> AudioStreamWAV:
	# Upbeat, serious boss track: driving bass, tense arpeggios, minor key
	# Tempo: 140 BPM, key of E minor
	var samples = int(sample_rate * duration)
	var data = PackedByteArray()
	data.resize(samples * 2)
	var bpm = 140.0
	var beat_dur = 60.0 / bpm  # ~0.4286s per beat
	var sixteenth = beat_dur / 4.0

	# Bass pattern: E1, E1, G1, A1 (repeats every bar = 4 beats)
	var bass_notes = [41.2, 41.2, 49.0, 55.0]
	# Arp notes: Em chord tones cycling (E3, G3, B3, E4, B3, G3)
	var arp_notes = [164.81, 196.0, 246.94, 329.63, 246.94, 196.0]
	# Tension chord pads (change every 2 bars)
	# Em -> Cmaj -> Am -> B7
	var pad_chords: Array = [
		[82.41, 123.47, 164.81, 246.94],
		[65.41, 98.0, 130.81, 196.0],
		[55.0, 82.41, 110.0, 164.81],
		[61.74, 92.50, 123.47, 185.0],
	]
	var bar_dur = beat_dur * 4.0
	var two_bar = bar_dur * 2.0

	for i in range(samples):
		var t = float(i) / sample_rate
		var sample_value = 0.0

		# --- Driving bass (plays on each beat, short punchy envelope) ---
		var beat_in_bar = fmod(t, bar_dur) / beat_dur
		var beat_idx = int(beat_in_bar) % bass_notes.size()
		var bass_freq = bass_notes[beat_idx]
		var t_in_beat = fmod(t, beat_dur)
		var bass_env = exp(-t_in_beat / beat_dur * 6.0)
		# Distorted sine for grit
		var bass_raw = sin(t * bass_freq * TAU) + 0.3 * sin(t * bass_freq * 2.0 * TAU)
		bass_raw = clamp(bass_raw * 1.5, -1.0, 1.0)  # Soft clip
		sample_value += bass_raw * bass_env * 0.35

		# --- Sixteenth-note arpeggio (tense, relentless) ---
		var sixteenth_pos = fmod(t, sixteenth)
		var arp_idx = int(fmod(t, bar_dur) / sixteenth) % arp_notes.size()
		var arp_freq = arp_notes[arp_idx]
		var arp_env = exp(-sixteenth_pos / sixteenth * 8.0)
		# Sharp attack sawtooth-ish tone
		var arp_phase = fmod(t * arp_freq, 1.0)
		var arp_raw = (arp_phase * 2.0 - 1.0) * 0.4  # Sawtooth
		arp_raw += sin(t * arp_freq * TAU) * 0.4  # Mix with sine for body
		arp_raw += sin(t * arp_freq * 3.0 * TAU) * 0.1  # Fifth harmonic edge
		sample_value += arp_raw * arp_env * 0.2

		# --- Tension pad (sustained, slow attack, changes every 2 bars) ---
		var pad_idx = int(fmod(t, two_bar * pad_chords.size()) / two_bar) % pad_chords.size()
		var pad_chord = pad_chords[pad_idx]
		var t_in_pad = fmod(t, two_bar)
		# Slow attack, sustained, slight fade at end
		var pad_attack = min(t_in_pad / 0.8, 1.0)
		var pad_release = 1.0
		if t_in_pad > two_bar - 0.5:
			pad_release = (two_bar - t_in_pad) / 0.5
		var pad_env = pad_attack * pad_release
		var pad_val = 0.0
		for p_idx in range(pad_chord.size()):
			var pf = pad_chord[p_idx]
			# Slow vibrato per voice
			var vib = sin(t * (0.15 + p_idx * 0.08)) * 0.004
			pad_val += sin(t * pf * (1.0 + vib) * TAU) * 0.25
			pad_val += sin(t * pf * (1.002 + vib) * TAU) * 0.15  # Detune
		pad_val /= float(pad_chord.size())
		sample_value += pad_val * pad_env * 0.25

		# --- Kick drum on beats 1 and 3 ---
		var beat_in_bar_f = fmod(t, bar_dur)
		var kick_val = 0.0
		for kick_beat in [0.0, beat_dur * 2.0]:
			var kick_t = beat_in_bar_f - kick_beat
			if kick_t >= 0.0 and kick_t < 0.15:
				var kick_freq = lerp(150.0, 40.0, kick_t / 0.15)
				var kick_env = exp(-kick_t * 30.0)
				kick_val += sin(kick_t * kick_freq * TAU) * kick_env
		sample_value += kick_val * 0.3

		# --- Hi-hat on every sixteenth (noise burst) ---
		var hat_t = fmod(t, sixteenth)
		if hat_t < 0.01:
			var hat_env = exp(-hat_t * 800.0)
			# Pseudo-noise from high frequency sines
			var noise = sin(t * 7919.0) * 0.3 + sin(t * 12553.0) * 0.3 + sin(t * 17389.0) * 0.2
			sample_value += noise * hat_env * 0.08

		# Loop-friendly envelope: fade first/last 0.5s
		var env = 1.0
		if t < 0.5:
			env = t / 0.5
		elif t > duration - 0.5:
			env = (duration - t) / 0.5
		sample_value *= env * vol

		var sample_int = int(clamp(sample_value * 32767.0, -32768.0, 32767.0))
		data[i * 2] = sample_int & 0xFF
		data[i * 2 + 1] = (sample_int >> 8) & 0xFF
	return _make_wav(data)

func _make_wav(data: PackedByteArray) -> AudioStreamWAV:
	var wav = AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = int(sample_rate)
	wav.stereo = false
	wav.data = data
	return wav
