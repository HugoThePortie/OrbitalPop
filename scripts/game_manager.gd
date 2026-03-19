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

# Dynamic color state
var current_hue: float = 0.45  # Start at teal green
var bg_material: ShaderMaterial
var core_material: StandardMaterial3D
var ring_material: StandardMaterial3D

# Gameplay settings
const DEFAULT_ORBIT_RADIUS: float = 2.0  # Reference for reset
const BASE_SPEED: float = 3.75  # radians per second
const START_SPEED: float = 1.75  # Starting speed
const HIT_THRESHOLD: float = 0.4  # radians (~23 degrees) - more forgiving for mobile
const FLIP_CHANCE: float = 0.25
const FLIP_DURATION: float = 1.5

# Speed milestones
const SPEED_MILESTONE_1: int = 10
const SPEED_MILESTONE_2: int = 20
const SPEED_MILESTONE_3: int = 30

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
const TARGET_HEIGHT: float = 0.58

# Animation durations
const EXPAND_DURATION: float = 0.8
const RESTORE_DURATION: float = 0.6
const GROW_DURATION: float = 0.2

# Grace periods
const GRACE_AFTER_FLIP: float = 3.0
const GRACE_AFTER_EXPAND: float = 2.0
const GRACE_AFTER_SPAWN: float = 0.8
const INPUT_BLOCK_DURATION: float = 0.5

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

# Timeout safeguards (in case timer callbacks don't fire on mobile)
var grace_end_time: float = 0.0
var flip_end_time: float = 0.0
var expand_end_time: float = 0.0
var input_block_end_time: float = 0.0
var extra_life_end_time: float = 0.0
var ring_count: int = 1  # Current number of rings (max 4)
var hits_since_last_special: int = 0
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
var levels_button: Button

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

# Settings & Dev Mode
var dev_mode_enabled: bool = true  # Default ON for development
var settings_layer: CanvasLayer = null
var settings_button: Button = null
var _state_before_pause: GameState = GameState.MENU  # Saved state when pausing

# Create a chamfer box mesh (box with beveled edges)
func create_chamfer_box(width: float, height: float, depth: float, chamfer: float) -> ArrayMesh:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var hw = width / 2.0   # half width (X)
	var hh = height / 2.0  # half height (Y)
	var hd = depth / 2.0   # half depth (Z)
	var c = chamfer        # chamfer size

	# Clamp chamfer to reasonable size
	c = min(c, min(hw, min(hh, hd)) * 0.5)

	# Define the 24 vertices of a chamfer box
	# Front face (Z+) - 8 vertices forming octagon
	var front_verts = [
		Vector3(-hw + c, -hh, hd),      # 0: bottom-left
		Vector3(hw - c, -hh, hd),       # 1: bottom-right
		Vector3(hw, -hh + c, hd),       # 2: right-bottom
		Vector3(hw, hh - c, hd),        # 3: right-top
		Vector3(hw - c, hh, hd),        # 4: top-right
		Vector3(-hw + c, hh, hd),       # 5: top-left
		Vector3(-hw, hh - c, hd),       # 6: left-top
		Vector3(-hw, -hh + c, hd),      # 7: left-bottom
	]

	# Back face (Z-) - 8 vertices
	var back_verts = [
		Vector3(hw - c, -hh, -hd),      # 0: bottom-right (mirrored)
		Vector3(-hw + c, -hh, -hd),     # 1: bottom-left
		Vector3(-hw, -hh + c, -hd),     # 2: left-bottom
		Vector3(-hw, hh - c, -hd),      # 3: left-top
		Vector3(-hw + c, hh, -hd),      # 4: top-left
		Vector3(hw - c, hh, -hd),       # 5: top-right
		Vector3(hw, hh - c, -hd),       # 6: right-top
		Vector3(hw, -hh + c, -hd),      # 7: right-bottom
	]

	# Front face (octagon)
	var front_center = Vector3(0, 0, hd)
	for i in range(8):
		var next = (i + 1) % 8
		st.set_normal(Vector3(0, 0, 1))
		st.add_vertex(front_center)
		st.add_vertex(front_verts[i])
		st.add_vertex(front_verts[next])

	# Back face (octagon)
	var back_center = Vector3(0, 0, -hd)
	for i in range(8):
		var next = (i + 1) % 8
		st.set_normal(Vector3(0, 0, -1))
		st.add_vertex(back_center)
		st.add_vertex(back_verts[i])
		st.add_vertex(back_verts[next])

	# Side faces - connect front and back octagons
	# Bottom face
	st.set_normal(Vector3(0, -1, 0))
	st.add_vertex(front_verts[0])
	st.add_vertex(back_verts[1])
	st.add_vertex(back_verts[0])
	st.add_vertex(front_verts[0])
	st.add_vertex(front_verts[1])
	st.add_vertex(back_verts[0])

	# Right face
	st.set_normal(Vector3(1, 0, 0))
	st.add_vertex(front_verts[2])
	st.add_vertex(back_verts[7])
	st.add_vertex(back_verts[6])
	st.add_vertex(front_verts[2])
	st.add_vertex(back_verts[6])
	st.add_vertex(front_verts[3])

	# Top face
	st.set_normal(Vector3(0, 1, 0))
	st.add_vertex(front_verts[4])
	st.add_vertex(back_verts[5])
	st.add_vertex(back_verts[4])
	st.add_vertex(front_verts[4])
	st.add_vertex(front_verts[5])
	st.add_vertex(back_verts[5])

	# Left face
	st.set_normal(Vector3(-1, 0, 0))
	st.add_vertex(front_verts[6])
	st.add_vertex(back_verts[3])
	st.add_vertex(back_verts[2])
	st.add_vertex(front_verts[6])
	st.add_vertex(back_verts[2])
	st.add_vertex(front_verts[7])

	# Chamfer edges (8 beveled strips)
	# Bottom-right chamfer
	st.set_normal(Vector3(0.707, -0.707, 0))
	st.add_vertex(front_verts[1])
	st.add_vertex(back_verts[0])
	st.add_vertex(back_verts[7])
	st.add_vertex(front_verts[1])
	st.add_vertex(back_verts[7])
	st.add_vertex(front_verts[2])

	# Right-top chamfer
	st.set_normal(Vector3(0.707, 0.707, 0))
	st.add_vertex(front_verts[3])
	st.add_vertex(back_verts[6])
	st.add_vertex(back_verts[5])
	st.add_vertex(front_verts[3])
	st.add_vertex(back_verts[5])
	st.add_vertex(front_verts[4])

	# Top-left chamfer
	st.set_normal(Vector3(-0.707, 0.707, 0))
	st.add_vertex(front_verts[5])
	st.add_vertex(back_verts[4])
	st.add_vertex(back_verts[3])
	st.add_vertex(front_verts[5])
	st.add_vertex(back_verts[3])
	st.add_vertex(front_verts[6])

	# Left-bottom chamfer
	st.set_normal(Vector3(-0.707, -0.707, 0))
	st.add_vertex(front_verts[7])
	st.add_vertex(back_verts[2])
	st.add_vertex(back_verts[1])
	st.add_vertex(front_verts[7])
	st.add_vertex(back_verts[1])
	st.add_vertex(front_verts[0])

	return st.commit()

# Update target appearance based on target type (expand, flip, regular)
func update_target_appearance() -> void:
	if not target_mesh:
		return

	target_mesh.visible = true
	target_mesh.position = Vector3(0, (CORE_RADIUS + active_radius) / 2.0, 0)

	# Scale target proportionally to the gap between core and ring
	var gap_ratio = (active_radius - CORE_RADIUS) / (DEFAULT_ORBIT_RADIUS - CORE_RADIUS)
	var base_scale = Vector3(gap_ratio, gap_ratio, gap_ratio)

	var mat = target_mesh.material_override as StandardMaterial3D
	var target_scale: Vector3

	if mat:
		if is_expand_target:
			mat.albedo_color = COLOR_TARGET_EXPAND
			target_scale = base_scale * 1.3
		elif is_flip_target:
			mat.albedo_color = COLOR_TARGET_FLIP
			target_scale = base_scale * 1.2
		else:
			mat.albedo_color = COLOR_TARGET
			target_scale = base_scale

	# Grow animation
	target_mesh.scale = target_scale * 0.25
	var grow_tween = create_tween()
	grow_tween.tween_property(target_mesh, "scale", target_scale, GROW_DURATION).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)

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

func _ready() -> void:
	current_state = GameState.MENU

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

	update_ui()

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
	ALBEDO = mix(color_bottom, color_top, gradient);
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

	# Core sphere at center (dynamic color, shaded, slightly transparent)
	core_sphere = MeshInstance3D.new()
	core_sphere.name = "CoreSphere"
	var core_mesh = SphereMesh.new()
	core_mesh.radius = CORE_RADIUS
	core_mesh.height = CORE_RADIUS * 2
	core_mesh.radial_segments = 64
	core_mesh.rings = 32
	core_sphere.mesh = core_mesh
	core_material = StandardMaterial3D.new()
	core_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var core_color = Color.from_hsv(current_hue, 0.4, 0.85)
	core_color.a = 0.85  # Slightly transparent
	core_material.albedo_color = core_color
	core_material.metallic = 0.0
	core_material.roughness = 1.0  # Fully matte
	core_sphere.material_override = core_material
	add_child(core_sphere)

	# Score label in center of core sphere
	score_label = Label3D.new()
	score_label.name = "ScoreLabel"
	score_label.text = "0"
	score_label.font_size = 160
	score_label.position = Vector3(0, 0, 1.0)  # Further in front of sphere
	score_label.modulate = Color.WHITE
	score_label.outline_modulate = Color.WHITE
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
	ring_mesh.rings = 64
	ring_mesh.ring_segments = 24
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
	floating_particles.amount = 20
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
	high_score_label = Label.new()
	high_score_label.name = "HighScoreLabel"
	high_score_label.text = "BEST: 0"
	high_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	high_score_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	high_score_label.anchor_left = 0.5
	high_score_label.anchor_right = 0.5
	high_score_label.offset_left = -100
	high_score_label.offset_right = 100
	high_score_label.offset_top = 160
	high_score_label.offset_bottom = 200
	high_score_label.add_theme_font_size_override("font_size", 24)
	high_score_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
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
	fail_label.add_theme_color_override("font_color", COLOR_CURSOR)
	hud.add_child(fail_label)

	# Level label (top left)
	level_label = Label.new()
	level_label.name = "LevelLabel"
	level_label.text = "LEVEL 1"
	level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	level_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	level_label.offset_left = 20
	level_label.offset_right = 150
	level_label.offset_top = 60
	level_label.offset_bottom = 90
	level_label.add_theme_font_size_override("font_size", 22)
	level_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.8))
	hud.add_child(level_label)

	# Progress label (below level label)
	progress_label = Label.new()
	progress_label.name = "ProgressLabel"
	progress_label.text = "0 / 10"
	progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	progress_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	progress_label.offset_left = 20
	progress_label.offset_right = 150
	progress_label.offset_top = 90
	progress_label.offset_bottom = 120
	progress_label.add_theme_font_size_override("font_size", 18)
	progress_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
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
	levels_button.pressed.connect(func(): show_level_select())
	levels_button.visible = true
	hud.add_child(levels_button)

	# Star display (top right, below high score)
	var star_container = HBoxContainer.new()
	star_container.name = "StarContainer"
	star_container.anchor_left = 1.0
	star_container.anchor_right = 1.0
	star_container.offset_left = -90
	star_container.offset_right = -20
	star_container.offset_top = 105
	star_container.offset_bottom = 135
	hud.add_child(star_container)

	var star_icon = Label.new()
	star_icon.text = "★"
	star_icon.add_theme_font_size_override("font_size", 24)
	star_icon.add_theme_color_override("font_color", Color(1.0, 0.84, 0.0))
	star_container.add_child(star_icon)

	star_label = Label.new()
	star_label.name = "StarLabel"
	star_label.text = str(star_manager.stars) if star_manager else "3"
	star_label.add_theme_font_size_override("font_size", 24)
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

		# Check if cursor passed target (too slow)
		if not is_flipping and not is_expanding and not is_using_extra_life:
			check_too_slow()

func _input(event: InputEvent) -> void:
	if input_blocked:
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
	hits_required = level * 5  # Level 1 = 5 hits, Level 2 = 10 hits, etc.

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

	# Target size (PRD section 3.3)
	level_target_scale = 1.0 if level < 50 else 0.8

	# Expansion rarity - more rare at higher levels
	if level <= 20:
		expansion_hit_threshold = 7
	elif level <= 50:
		expansion_hit_threshold = 12
	else:
		expansion_hit_threshold = 18

	cursor_speed = level_base_speed

func start_game() -> void:
	# Setup level configuration
	setup_level(current_level)
	score = level_hits  # Show hits as score
	cursor_direction = 1
	cursor_angle = -PI / 2  # Start at bottom (6 o'clock)
	is_flipping = false

	# Reset expansion state
	is_expand_target = false
	is_expanding = false
	is_using_extra_life = false
	hits_since_last_special = 0
	active_radius = DEFAULT_ORBIT_RADIUS

	# Clean up extra rings if they exist
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

	# Reset cursor size and position for default radius
	update_cursor_mesh()
	if cursor_mesh:
		cursor_mesh.visible = true

	# Reset theme colors
	update_theme_colors()

	# Reset world rotation
	world_group.rotation.x = 0

	# Reset camera zoom and position (smooth zoom out from miss view)
	if camera:
		var cam_tween = create_tween()
		cam_tween.set_parallel(true)
		cam_tween.tween_property(camera, "size", 9.0, 0.4).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		cam_tween.tween_property(camera, "position", Vector3(0, 0, 10), 0.4).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)

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
	if score_label:
		score_label.text = "3"
	update_ui()

	# Countdown sequence: 3 -> 2 -> 1 -> GO
	get_tree().create_timer(1.0).timeout.connect(func():
		if current_state != GameState.COUNTDOWN:
			return
		if score_label:
			score_label.text = "2"
			pulse_score()
	)
	get_tree().create_timer(2.0).timeout.connect(func():
		if current_state != GameState.COUNTDOWN:
			return
		if score_label:
			score_label.text = "1"
			pulse_score()
	)
	get_tree().create_timer(3.0).timeout.connect(func():
		if current_state != GameState.COUNTDOWN:
			return
		# Transition to playing
		current_state = GameState.PLAYING
		input_blocked = false
		if score_label:
			score_label.text = str(level_hits)
		update_ui()
		score_changed.emit(score)
	)

func spawn_target(after_flip: bool = false, grace_override: float = 0.0) -> void:
	# Normalize cursor angle first
	var normalized_cursor = fmod(cursor_angle, TAU)
	if normalized_cursor < 0:
		normalized_cursor += TAU

	# Determine spawn distance based on context
	var ahead_angle: float
	if after_flip:
		ahead_angle = randf_range(PI * 0.25, PI * 0.5)  # 45-90 degrees
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
	is_flip_target = false
	is_expand_target = false
	if ring_count < MAX_RINGS and hits_since_last_special >= expansion_hit_threshold:
		is_expand_target = true
	elif randf() < level_flip_chance:
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

func attempt_hit() -> void:
	if is_flipping or is_expanding or is_using_extra_life:
		return

	# Calculate angle difference
	var diff = abs(cursor_angle - target_angle)
	if diff > PI:
		diff = TAU - diff

	if diff < HIT_THRESHOLD:
		# HIT!
		on_target_hit()
	elif not spawn_grace_period:
		# MISS! (only count misses outside grace period)
		end_game("MISSED!")

func check_too_slow() -> void:
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

	# If we've passed the target by more than threshold
	if actual_sign != expected_sign and abs(angle_to_target) > HIT_THRESHOLD * 0.5:
		end_game("TOO SLOW!")

func on_target_hit() -> void:
	# Play hit sound
	play_hit_sound()

	# Level progress
	level_hits += 1
	score = level_hits  # Display hits as score
	hits_since_last_special += 1
	score_changed.emit(score)

	# Update progress ring (do this before level complete check so it shows 100%)
	update_progress_ring()

	# Check level completion
	if level_hits >= hits_required:
		trigger_level_complete()
		return

	# Update theme colors
	update_theme_colors()

	# Pulse score
	pulse_score()

	# Speed increase within level (gradual ramp to level_base_speed * 1.5)
	var progress = float(level_hits) / float(hits_required)
	cursor_speed = level_base_speed * (1.0 + progress * 0.5)

	# Spawn explosion effect
	spawn_explosion(target_mesh.global_position)

	# Handle expand, flip, or reverse direction
	if is_expand_target:
		do_expand()  # Will spawn target after expansion completes
	elif is_flip_target:
		do_flip()  # Will spawn target after flip completes
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
		# Toggle flipped state
		world_flipped = not world_flipped
		# DON'T change cursor_direction - cursor continues same direction

		# Wait then spawn target ahead
		get_tree().create_timer(0.5).timeout.connect(func():
			is_flipping = false
			spawn_target(true)  # after_flip = true
		)
	)

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
	outer_ring_mesh.rings = 64
	outer_ring_mesh.ring_segments = 24
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

	# Animate all inner rings to concentric positions around center sphere
	var shrink_tween = create_tween()
	shrink_tween.set_parallel(true)
	var num_inner = inner_rings.size()
	for i in range(num_inner):
		var ring = inner_rings[i]
		var mat = inner_ring_materials[i]
		# Fixed spacing from core - each ring gets its own slot
		# Ring 0 (oldest) is closest to core
		var target_radius = CORE_RADIUS + RING_SPACING * (i + 1)
		var original_radius = DEFAULT_ORBIT_RADIUS  # All rings started at this radius
		var target_scale = target_radius / original_radius
		shrink_tween.tween_property(ring, "scale", Vector3(target_scale, target_scale, target_scale), 0.8).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		# Fade inner rings (older rings more faded)
		if mat:
			var faded_color = mat.albedo_color
			var alpha = 0.15 + (0.1 * i)  # 0.15 to 0.45 alpha based on index
			faded_color.a = min(alpha, 0.5)
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
		is_expanding = false
		spawn_target(false, GRACE_AFTER_EXPAND)  # Use longer grace period after expansion
	)

func trigger_level_complete() -> void:
	play_level_complete_sound()
	current_state = GameState.LEVEL_COMPLETE

	# Unlock next level
	if current_level < 100:
		max_unlocked_level = max(max_unlocked_level, current_level + 1)

	save_progress()

	# Hide target
	if target_mesh:
		target_mesh.visible = false

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

	# Show level complete text
	if fail_label:
		fail_label.text = "LEVEL " + str(current_level) + " COMPLETE!"
		fail_label.add_theme_color_override("font_color", Color(1.0, 0.84, 0.0))  # Gold
		fail_label.visible = true

	if instruction_label:
		instruction_label.text = "TAP TO CONTINUE"
		instruction_label.visible = true

	# Wait for user tap to continue (no auto-advance)

func advance_to_next_level() -> void:
	if current_level < 100:
		current_level += 1

	# Reset fail label color
	if fail_label:
		fail_label.add_theme_color_override("font_color", COLOR_CURSOR)
		fail_label.visible = false

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
		var progress = float(level_hits) / float(hits_required)
		progress_ring_material.set_shader_parameter("progress", progress)

func create_progress_ring() -> void:
	# Create progress ring mesh around core sphere
	progress_ring = MeshInstance3D.new()
	progress_ring.name = "ProgressRing"
	var ring_mesh = TorusMesh.new()
	ring_mesh.inner_radius = CORE_RADIUS + 0.02
	ring_mesh.outer_radius = CORE_RADIUS + 0.12
	ring_mesh.rings = 64
	ring_mesh.ring_segments = 16
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
	torus.rings = 32
	torus.ring_segments = 16
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
	# Block input and checks during transition
	is_using_extra_life = true
	extra_life_end_time = Time.get_ticks_msec() / 1000.0 + RESTORE_DURATION + 2.0
	input_blocked = true
	input_block_end_time = Time.get_ticks_msec() / 1000.0 + RESTORE_DURATION + 2.0

	# Hide the missed target
	if target_mesh:
		target_mesh.visible = false

	# Explode the current outer ring
	spawn_ring_explosion()

	# Remove the current active (outer) ring
	orbit_ring.queue_free()

	# Get the first (original) inner ring — collapse back to single ring
	var restored_ring = inner_rings[0]
	var restored_material = inner_ring_materials[0]

	# Remove all other inner rings (everything except the first)
	for i in range(1, inner_rings.size()):
		inner_rings[i].queue_free()
	inner_rings.clear()
	inner_ring_materials.clear()

	# Make the original ring the active ring again
	orbit_ring = restored_ring
	ring_material = restored_material
	ring_count = 1

	# Restore to default radius
	active_radius = DEFAULT_ORBIT_RADIUS

	# Animate ring zooming back to full active size
	var restore_tween = create_tween()
	restore_tween.set_parallel(true)

	restore_tween.tween_property(orbit_ring, "scale", Vector3.ONE, 0.6).set_ease(Tween.EASE_OUT)

	if ring_material:
		var full_color = ring_material.albedo_color
		full_color.a = 0.8
		restore_tween.tween_property(ring_material, "albedo_color", full_color, 0.6)

	# Zoom camera back to default
	restore_tween.tween_property(camera, "size", 9.0, 0.6).set_ease(Tween.EASE_OUT)

	# Resize cursor for restored radius
	var new_cursor_pos = Vector3(0, (CORE_RADIUS + active_radius) / 2.0, 0)
	update_cursor_mesh()

	restore_tween.tween_property(cursor_mesh, "position", new_cursor_pos, RESTORE_DURATION)

	# After animation, spawn new target and resume
	restore_tween.set_parallel(false)
	restore_tween.tween_callback(func():
		cursor_direction *= -1
		spawn_target(false, GRACE_AFTER_EXPAND)
		input_blocked = false
		is_using_extra_life = false
	)

func end_game(reason: String) -> void:
	# Check if we have extra lives (inner rings)
	if inner_rings.size() > 0:
		use_extra_life()
		return

	# Play miss sound
	play_miss_sound()

	current_state = GameState.GAME_OVER

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

	# Zoom into the miss area (400% zoom)
	zoom_to_miss()

	# Show fail reason
	if fail_label:
		fail_label.text = reason
		fail_label.visible = true

	# Consume a star on game over (skip in free play)
	if not _is_free_play() and star_manager:
		star_manager.consume_star()
		_update_star_display()

	# Screen shake
	shake_camera()

	update_ui()
	game_over.emit(reason)

func zoom_to_miss() -> void:
	if not camera or not target_mesh:
		return
	# Get the actual position of the visible stopper
	var target_pos = target_mesh.global_position
	# Zoom camera and center on the missed stopper (400% = size / 4)
	var zoom_tween = create_tween()
	zoom_tween.set_parallel(true)
	zoom_tween.tween_property(camera, "size", 6.0 / 3.0, 1.2).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	zoom_tween.tween_property(camera, "position:x", target_pos.x, 1.2).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	zoom_tween.tween_property(camera, "position:y", target_pos.y, 1.2).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)

func shake_camera() -> void:
	if not camera:
		return
	var original_pos = camera.position
	var tween = create_tween()
	for i in range(6):
		var offset = Vector3(randf_range(-0.15, 0.15), randf_range(-0.15, 0.15), 0)
		tween.tween_property(camera, "position", original_pos + offset, 0.05)
	tween.tween_property(camera, "position", original_pos, 0.05)

func restart_game() -> void:
	if fail_label:
		fail_label.visible = false
	start_game()

func update_ui() -> void:
	match current_state:
		GameState.MENU:
			if instruction_label:
				instruction_label.text = "TAP TO START"
				instruction_label.visible = true
			if score_label:
				score_label.text = "0"
			if fail_label:
				fail_label.visible = false
			if level_label:
				level_label.text = "LEVEL " + str(current_level)
				level_label.visible = true
			if progress_label:
				progress_label.visible = false
			if levels_button:
				levels_button.visible = true
		GameState.LEVEL_SELECT:
			if levels_button:
				levels_button.visible = false
		GameState.COUNTDOWN:
			if instruction_label:
				instruction_label.visible = false
			if fail_label:
				fail_label.visible = false
			if level_label:
				level_label.text = "LEVEL " + str(current_level)
				level_label.visible = true
			if progress_label:
				progress_label.text = "0 / " + str(hits_required)
				progress_label.visible = true
			if levels_button:
				levels_button.visible = false
		GameState.PLAYING:
			if instruction_label:
				instruction_label.visible = false
			if score_label:
				score_label.text = str(level_hits)
			if fail_label:
				fail_label.visible = false
			if level_label:
				level_label.text = "LEVEL " + str(current_level)
				level_label.visible = true
			if progress_label:
				progress_label.text = str(level_hits) + " / " + str(hits_required)
				progress_label.visible = true
			if levels_button:
				levels_button.visible = false
		GameState.LEVEL_COMPLETE:
			if level_label:
				level_label.visible = true
			if progress_label:
				progress_label.text = str(hits_required) + " / " + str(hits_required)
				progress_label.visible = true
			if levels_button:
				levels_button.visible = false
		GameState.GAME_OVER:
			if instruction_label:
				if star_manager and star_manager.has_stars():
					instruction_label.text = "TAP TO RETRY"
				else:
					instruction_label.text = ""
				instruction_label.visible = true
			if score_label:
				score_label.text = str(level_hits)
			if level_label:
				level_label.visible = true
			if progress_label:
				progress_label.visible = true
			if levels_button:
				levels_button.visible = false

	# Always update high score display
	if high_score_label:
		high_score_label.text = "BEST: " + str(high_score)

func update_theme_colors() -> void:
	# Shift hue based on score
	current_hue = fmod(0.45 + (score * HUE_SHIFT_PER_POINT), 1.0)

	# Update background gradient colors
	if bg_material:
		var top_color = Color.from_hsv(current_hue, 0.35, 0.45)
		var bottom_color = Color.from_hsv(current_hue, 0.5, 0.08)
		bg_material.set_shader_parameter("color_top", Vector3(top_color.r, top_color.g, top_color.b))
		bg_material.set_shader_parameter("color_bottom", Vector3(bottom_color.r, bottom_color.g, bottom_color.b))

	# Update core sphere color (preserve transparency)
	if core_material:
		var core_color = Color.from_hsv(current_hue, 0.4, 0.85)
		core_color.a = 0.85
		core_material.albedo_color = core_color

	# Update ring color (preserve transparency)
	if ring_material:
		var ring_color = Color.from_hsv(current_hue, 0.35, 0.55)
		ring_color.a = 0.8
		ring_material.albedo_color = ring_color

	# Update all inner ring colors (fainter)
	for mat in inner_ring_materials:
		if mat:
			var inner_color = Color.from_hsv(current_hue, 0.25, 0.45)
			inner_color.a = 0.3
			mat.albedo_color = inner_color

	# Update floor grid colors
	if floor_grid_material:
		var near_col = Color.from_hsv(current_hue, 0.8, 1.0)
		var far_col = Color.from_hsv(fmod(current_hue + 0.3, 1.0), 0.8, 0.8)
		floor_grid_material.set_shader_parameter("near_color", Vector3(near_col.r, near_col.g, near_col.b))
		floor_grid_material.set_shader_parameter("far_color", Vector3(far_col.r, far_col.g, far_col.b))
		var glow_col = Color.from_hsv(current_hue, 0.6, 1.0)
		floor_grid_material.set_shader_parameter("glow_color", Vector3(glow_col.r, glow_col.g, glow_col.b))

	# Update grid pulse overlay color
	if grid_pulse_material:
		var accent = Color.from_hsv(current_hue, 0.7, 1.0)
		grid_pulse_material.set_shader_parameter("line_color", Vector3(accent.r, accent.g, accent.b))

	# Update radial glow color
	if radial_glow_material:
		var accent = Color.from_hsv(current_hue, 0.7, 1.0)
		radial_glow_material.set_shader_parameter("glow_color", Vector3(accent.r, accent.g, accent.b))

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

	# Background panel
	var bg = ColorRect.new()
	bg.color = Color(0.1, 0.1, 0.15, 0.95)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	level_select_layer.add_child(bg)

	# Title
	var title = Label.new()
	title.text = "SELECT LEVEL"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.anchor_left = 0.5
	title.anchor_right = 0.5
	title.offset_left = -150
	title.offset_right = 150
	title.offset_top = 60
	title.offset_bottom = 100
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", Color.WHITE)
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
		btn.add_theme_font_size_override("font_size", 24)
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
	nav_container.offset_left = -100
	nav_container.offset_right = 100
	nav_container.offset_top = -120
	nav_container.offset_bottom = -70
	nav_container.alignment = BoxContainer.ALIGNMENT_CENTER
	nav_container.add_theme_constant_override("separation", 20)
	level_select_layer.add_child(nav_container)

	var prev_btn = Button.new()
	prev_btn.text = "<"
	prev_btn.custom_minimum_size = Vector2(50, 40)
	prev_btn.add_theme_font_size_override("font_size", 24)
	prev_btn.pressed.connect(func(): change_level_page(-1))
	nav_container.add_child(prev_btn)

	var page_label = Label.new()
	page_label.name = "PageLabel"
	page_label.text = "1 / 5"
	page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	page_label.custom_minimum_size = Vector2(60, 40)
	page_label.add_theme_font_size_override("font_size", 20)
	nav_container.add_child(page_label)

	var next_btn = Button.new()
	next_btn.text = ">"
	next_btn.custom_minimum_size = Vector2(50, 40)
	next_btn.add_theme_font_size_override("font_size", 24)
	next_btn.pressed.connect(func(): change_level_page(1))
	nav_container.add_child(next_btn)

	# Back button
	var back_btn = Button.new()
	back_btn.text = "BACK"
	back_btn.anchor_left = 0.5
	back_btn.anchor_right = 0.5
	back_btn.anchor_top = 1.0
	back_btn.offset_left = -60
	back_btn.offset_right = 60
	back_btn.offset_top = -60
	back_btn.offset_bottom = -20
	back_btn.add_theme_font_size_override("font_size", 20)
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
			if level < max_unlocked_level:
				# Completed level - gold
				btn.add_theme_color_override("font_color", Color(1.0, 0.84, 0.0))
			else:
				# Current unlocked level - white
				btn.add_theme_color_override("font_color", Color.WHITE)
		else:
			# Locked level
			btn.disabled = true
			btn.text = "🔒"
			btn.add_theme_color_override("font_color", Color(0.4, 0.4, 0.4))

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

func _save_settings() -> void:
	var config = ConfigFile.new()
	config.load("user://save.cfg")
	config.set_value("settings", "dev_mode", dev_mode_enabled)
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

	# Background
	var bg = ColorRect.new()
	bg.color = Color(0.05, 0.05, 0.1, 0.92)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	settings_layer.add_child(bg)

	# Container
	var container = VBoxContainer.new()
	container.anchor_left = 0.5
	container.anchor_right = 0.5
	container.anchor_top = 0.5
	container.anchor_bottom = 0.5
	container.offset_left = -140
	container.offset_right = 140
	container.offset_top = -220
	container.offset_bottom = 220
	container.alignment = BoxContainer.ALIGNMENT_CENTER
	container.add_theme_constant_override("separation", 16)
	settings_layer.add_child(container)

	# Title
	var title = Label.new()
	title.text = "PAUSED" if _state_before_pause == GameState.PLAYING or _state_before_pause == GameState.COUNTDOWN else "SETTINGS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", Color.WHITE)
	container.add_child(title)

	# Spacer
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 8)
	container.add_child(spacer)

	# Sound toggle
	var sound_btn = Button.new()
	sound_btn.text = "Sound: OFF" if sound_muted else "Sound: ON"
	sound_btn.custom_minimum_size = Vector2(240, 50)
	sound_btn.add_theme_font_size_override("font_size", 22)
	sound_btn.add_theme_color_override("font_color", Color(0.0, 0.94, 1.0))
	sound_btn.pressed.connect(func():
		toggle_mute()
		sound_btn.text = "Sound: OFF" if sound_muted else "Sound: ON"
	)
	container.add_child(sound_btn)

	# Dev Mode toggle
	var dev_btn = Button.new()
	dev_btn.text = "Dev Mode: ON" if dev_mode_enabled else "Dev Mode: OFF"
	dev_btn.custom_minimum_size = Vector2(240, 50)
	dev_btn.add_theme_font_size_override("font_size", 22)
	dev_btn.add_theme_color_override("font_color", Color(1.0, 0.84, 0.0))
	dev_btn.pressed.connect(func():
		dev_mode_enabled = not dev_mode_enabled
		_save_settings()
		dev_btn.text = "Dev Mode: ON" if dev_mode_enabled else "Dev Mode: OFF"
	)
	container.add_child(dev_btn)

	# Spacer
	var spacer2 = Control.new()
	spacer2.custom_minimum_size = Vector2(0, 4)
	container.add_child(spacer2)

	# Remove Ads / Ads Removed
	if iap_manager and iap_manager.is_ads_disabled():
		var removed_label = Label.new()
		removed_label.text = "✓ Ads Removed"
		removed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		removed_label.add_theme_font_size_override("font_size", 20)
		removed_label.add_theme_color_override("font_color", Color(0.22, 1.0, 0.08))
		container.add_child(removed_label)
	else:
		var price = iap_manager.get_remove_ads_price() if iap_manager else "$2.99"
		var iap_btn = Button.new()
		iap_btn.text = "Remove Ads - %s" % price
		iap_btn.custom_minimum_size = Vector2(240, 50)
		iap_btn.add_theme_font_size_override("font_size", 22)
		iap_btn.add_theme_color_override("font_color", Color(0.0, 0.94, 1.0))
		iap_btn.pressed.connect(func():
			if iap_manager:
				iap_btn.disabled = true
				iap_btn.text = "PURCHASING..."
				iap_manager.purchase_remove_ads()
		)
		container.add_child(iap_btn)

	# Restore Purchases
	var restore_btn = Button.new()
	restore_btn.text = "Restore Purchases"
	restore_btn.custom_minimum_size = Vector2(240, 40)
	restore_btn.flat = true
	restore_btn.add_theme_font_size_override("font_size", 16)
	restore_btn.add_theme_color_override("font_color", Color(1, 1, 1, 0.5))
	restore_btn.pressed.connect(func():
		if iap_manager:
			restore_btn.text = "Restoring..."
			iap_manager.restore_purchases()
	)
	container.add_child(restore_btn)

	# Spacer
	var spacer3 = Control.new()
	spacer3.custom_minimum_size = Vector2(0, 4)
	container.add_child(spacer3)

	# Return to Menu (only if playing or game over)
	if _state_before_pause in [GameState.PLAYING, GameState.COUNTDOWN, GameState.GAME_OVER]:
		var menu_btn = Button.new()
		menu_btn.text = "Return to Menu"
		menu_btn.custom_minimum_size = Vector2(240, 50)
		menu_btn.add_theme_font_size_override("font_size", 22)
		menu_btn.add_theme_color_override("font_color", Color(1.0, 0.0, 1.0))
		menu_btn.pressed.connect(func():
			_close_settings()
			_return_to_menu()
		)
		container.add_child(menu_btn)

	# Close button
	var close_btn = Button.new()
	close_btn.text = "CLOSE"
	close_btn.custom_minimum_size = Vector2(240, 50)
	close_btn.add_theme_font_size_override("font_size", 22)
	close_btn.add_theme_color_override("font_color", Color(1, 1, 1, 0.8))
	close_btn.pressed.connect(func(): _close_settings())
	container.add_child(close_btn)

func _close_settings() -> void:
	if settings_layer:
		settings_layer.queue_free()
		settings_layer = null
	# Resume game if it was playing/countdown before pause
	if _state_before_pause == GameState.PLAYING or _state_before_pause == GameState.COUNTDOWN:
		current_state = _state_before_pause

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

	var bg = ColorRect.new()
	bg.color = Color(0.05, 0.05, 0.1, 0.92)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	out_of_stars_layer.add_child(bg)

	var container = VBoxContainer.new()
	container.anchor_left = 0.5
	container.anchor_right = 0.5
	container.anchor_top = 0.5
	container.anchor_bottom = 0.5
	container.offset_left = -150
	container.offset_right = 150
	container.offset_top = -200
	container.offset_bottom = 200
	container.alignment = BoxContainer.ALIGNMENT_CENTER
	container.add_theme_constant_override("separation", 16)
	out_of_stars_layer.add_child(container)

	var title = Label.new()
	title.text = "OUT OF STARS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 36)
	title.add_theme_color_override("font_color", Color.WHITE)
	container.add_child(title)

	var star_count = Label.new()
	star_count.text = "★ 0"
	star_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	star_count.add_theme_font_size_override("font_size", 48)
	star_count.add_theme_color_override("font_color", Color(1.0, 0.84, 0.0))
	container.add_child(star_count)

	var desc = Label.new()
	desc.name = "Description"
	desc.text = "Watch an ad to get 2 more stars!"
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.add_theme_font_size_override("font_size", 18)
	desc.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	container.add_child(desc)

	# Watch Ad button
	var ad_btn = Button.new()
	ad_btn.name = "WatchAdButton"
	ad_btn.text = "Watch Ad +2★"
	ad_btn.custom_minimum_size = Vector2(240, 50)
	ad_btn.add_theme_font_size_override("font_size", 22)
	ad_btn.add_theme_color_override("font_color", Color(0.22, 1.0, 0.08))
	ad_btn.pressed.connect(func(): _on_watch_ad_pressed(ad_btn, desc))
	container.add_child(ad_btn)

	# Remove Ads button
	var price = iap_manager.get_remove_ads_price() if iap_manager else "$2.99"
	var iap_btn = Button.new()
	iap_btn.text = "Remove Ads - %s" % price
	iap_btn.custom_minimum_size = Vector2(240, 50)
	iap_btn.add_theme_font_size_override("font_size", 22)
	iap_btn.add_theme_color_override("font_color", Color(0.0, 0.94, 1.0))
	iap_btn.pressed.connect(func():
		if iap_manager:
			iap_btn.disabled = true
			iap_btn.text = "PURCHASING..."
			iap_manager.purchase_remove_ads()
	)
	container.add_child(iap_btn)

	# Menu button
	var menu_btn = Button.new()
	menu_btn.text = "MENU"
	menu_btn.custom_minimum_size = Vector2(240, 50)
	menu_btn.add_theme_font_size_override("font_size", 22)
	menu_btn.add_theme_color_override("font_color", Color(1.0, 0.0, 1.0))
	menu_btn.pressed.connect(func(): _close_out_of_stars_modal())
	container.add_child(menu_btn)

# ----- Ad Callbacks -----

func _on_watch_ad_pressed(ad_btn: Button, desc_label: Label) -> void:
	if admob_manager:
		ad_btn.disabled = true
		ad_btn.text = "LOADING..."
		admob_manager.show_rewarded_ad()

func _on_ad_rewarded() -> void:
	print("[OrbitalPop] Ad reward earned - granting 2 stars")
	if star_manager:
		star_manager.grant_ad_reward_stars()
		_update_star_display()
	_close_out_of_stars_modal()
	start_game()

func _on_ad_closed() -> void:
	pass

func _on_ad_failed() -> void:
	print("[OrbitalPop] Ad failed to show")
	if out_of_stars_layer and out_of_stars_layer.visible:
		for child in out_of_stars_layer.get_children():
			if child is VBoxContainer:
				for sub in child.get_children():
					if sub.name == "Description":
						sub.text = "Ad not available. Please try again later."
					if sub.name == "WatchAdButton":
						sub.disabled = false
						sub.text = "Watch Ad +2★"

func _close_out_of_stars_modal() -> void:
	if out_of_stars_layer:
		out_of_stars_layer.queue_free()
		out_of_stars_layer = null

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

func toggle_mute() -> void:
	sound_muted = not sound_muted

func play_start_sound() -> void:
	if sound_muted or not sfx_start:
		return
	sfx_start.play()

func play_hit_sound() -> void:
	if sound_muted or not sfx_hit:
		return
	sfx_hit.play()

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
	var samples = int(sample_rate * duration)
	var data = PackedByteArray()
	data.resize(samples * 2)
	for i in range(samples):
		var t = float(i) / sample_rate
		var progress = float(i) / float(samples)
		var pitch = freq * (1.0 + progress * 0.12)
		var envelope = exp(-progress * 15.0)
		var sample_value = sin(t * pitch * TAU) * 0.5 + sin(t * pitch * 2.0 * TAU) * 0.3 + sin(t * pitch * 1.5 * TAU) * 0.2
		sample_value *= envelope * vol
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

func _make_wav(data: PackedByteArray) -> AudioStreamWAV:
	var wav = AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = int(sample_rate)
	wav.stereo = false
	wav.data = data
	return wav
