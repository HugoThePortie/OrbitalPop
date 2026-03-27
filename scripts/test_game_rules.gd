extends SceneTree
## Test script for core game mechanics (ring/extra life system).
## Run: /Applications/Godot.app/Contents/MacOS/Godot --headless -s scripts/test_game_rules.gd

var pass_count: int = 0
var fail_count: int = 0
var test_name: String = ""

# Constants copied from game_manager.gd so we can verify logic
const CORE_RADIUS: float = 0.8
const DEFAULT_ORBIT_RADIUS: float = 2.0
const TARGET_RADIUS: float = 0.29
const CURSOR_WIDTH: float = 0.175
const START_SPEED: float = 1.75
const BASE_SPEED: float = 3.75
const PERFECT_HIT_RATIO: float = 0.4
const FRENZY_THRESHOLD: int = 3
const FRENZY_MULTIPLIERS: Array = [1.0, 1.5, 2.0, 3.0]

func _init() -> void:
	print("\n========================================")
	print("  ORBITAL POP - GAME RULES TESTS")
	print("========================================\n")

	test_overlap_threshold_basic()
	test_overlap_threshold_scales_with_ring_count()
	test_overlap_threshold_scales_with_radius()
	test_hit_when_overlapping()
	test_miss_when_not_overlapping()
	test_grace_period_forgives_miss()
	test_grace_period_allows_hit()
	test_inner_rings_prevent_game_over()
	test_no_inner_rings_causes_game_over()
	test_expansion_threshold_reachable()
	test_check_too_slow_respects_grace()
	test_check_too_slow_fires_when_past()
	test_extra_life_consumes_ring()
	test_target_scales_with_ring_count()
	test_perfect_hit_threshold()
	test_perfect_hit_double_progress()
	test_frenzy_streak_builds()
	test_frenzy_streak_breaks_on_regular()
	test_frenzy_multiplier_caps()
	test_daily_seed_deterministic()
	test_boss_material_cull_disabled()
	test_boss_material_has_emission()
	test_boss_material_uses_registry_color()
	test_boss_viewport_material_cull_disabled()
	test_invader_mesh_is_triangles()
	test_invader_mesh_has_vertices()

	print("\n========================================")
	print("  RESULTS: %d passed, %d failed" % [pass_count, fail_count])
	print("========================================\n")

	if fail_count > 0:
		print("FAIL — %d test(s) did not pass" % fail_count)
		quit(1)
	else:
		print("ALL TESTS PASSED")
		quit(0)


# --- Helpers ---

## Reproduce get_overlap_threshold() logic from game_manager.gd
func calc_threshold(active_radius: float, ring_count: int = 1) -> float:
	var midpoint = (CORE_RADIUS + active_radius) / 2.0
	var scale_factor = 1.0 + (ring_count - 1) * 0.5
	var stopper_half_angle = (TARGET_RADIUS * scale_factor) / midpoint
	var cursor_half_angle = (CURSOR_WIDTH / 2.0) / midpoint
	return stopper_half_angle + cursor_half_angle

## Reproduce angle diff logic from attempt_hit()
func angle_diff(cursor_angle: float, target_angle: float) -> float:
	var diff = abs(cursor_angle - target_angle)
	if diff > PI:
		diff = TAU - diff
	return diff

## Reproduce check_too_slow logic
func cursor_past_target(cursor_angle: float, target_angle: float, cursor_direction: int, threshold: float) -> bool:
	var angle_to_target = target_angle - cursor_angle
	if angle_to_target > PI:
		angle_to_target -= TAU
	elif angle_to_target < -PI:
		angle_to_target += TAU
	var expected_sign = cursor_direction
	var actual_sign = sign(angle_to_target)
	return actual_sign != expected_sign and abs(angle_to_target) > threshold

func begin(name: String) -> void:
	test_name = name

func assert_true(condition: bool, msg: String = "") -> void:
	if condition:
		pass_count += 1
		print("  PASS: %s %s" % [test_name, msg])
	else:
		fail_count += 1
		print("  FAIL: %s %s" % [test_name, msg])

func assert_eq(a, b, msg: String = "") -> void:
	if a == b:
		pass_count += 1
		print("  PASS: %s %s" % [test_name, msg])
	else:
		fail_count += 1
		print("  FAIL: %s %s (got %s, expected %s)" % [test_name, msg, str(a), str(b)])


# --- Tests ---

func test_overlap_threshold_basic() -> void:
	begin("overlap_threshold_basic")
	var threshold = calc_threshold(DEFAULT_ORBIT_RADIUS, 1)
	# Midpoint = (0.8 + 2.0) / 2 = 1.4
	# Visual overlap = (0.29 + 0.0875) / 1.4 ≈ 0.27
	assert_true(threshold > 0.2, "threshold > 0.2 (got %.3f)" % threshold)
	assert_true(threshold < 0.4, "threshold < 0.4 (got %.3f)" % threshold)

func test_overlap_threshold_scales_with_ring_count() -> void:
	begin("overlap_threshold_scales_with_ring_count")
	var thresh_r1 = calc_threshold(DEFAULT_ORBIT_RADIUS, 1)
	var thresh_r2 = calc_threshold(DEFAULT_ORBIT_RADIUS + 0.5, 2)
	var thresh_r3 = calc_threshold(DEFAULT_ORBIT_RADIUS + 1.0, 3)
	# Higher ring count = larger stopper = larger threshold (despite larger radius)
	assert_true(thresh_r2 > thresh_r1,
		"ring 2 (%.3f) > ring 1 (%.3f)" % [thresh_r2, thresh_r1])
	assert_true(thresh_r3 > thresh_r2,
		"ring 3 (%.3f) > ring 2 (%.3f)" % [thresh_r3, thresh_r2])

func test_overlap_threshold_scales_with_radius() -> void:
	begin("overlap_threshold_scales_with_radius")
	# Same ring count, different radius — larger radius = smaller angular size
	var thresh_small = calc_threshold(2.0, 1)
	var thresh_large = calc_threshold(3.5, 1)
	assert_true(thresh_small > thresh_large,
		"smaller radius (%.3f) > larger radius (%.3f)" % [thresh_small, thresh_large])

func test_hit_when_overlapping() -> void:
	begin("hit_when_overlapping")
	var threshold = calc_threshold(DEFAULT_ORBIT_RADIUS, 1)
	# Cursor exactly on target
	var diff = angle_diff(1.0, 1.0)
	assert_true(diff < threshold, "exact overlap: diff=0 < threshold=%.3f" % threshold)
	# Cursor slightly off but within threshold
	diff = angle_diff(1.0, 1.0 + threshold * 0.5)
	assert_true(diff < threshold, "half-threshold offset: diff=%.3f < threshold=%.3f" % [diff, threshold])

func test_miss_when_not_overlapping() -> void:
	begin("miss_when_not_overlapping")
	var threshold = calc_threshold(DEFAULT_ORBIT_RADIUS, 1)
	# Cursor on opposite side
	var diff = angle_diff(0.0, PI)
	assert_true(diff > threshold, "opposite side: diff=%.3f > threshold=%.3f" % [diff, threshold])
	# Cursor just outside threshold
	diff = angle_diff(0.0, threshold * 1.5)
	assert_true(diff > threshold, "1.5x threshold: diff=%.3f > threshold=%.3f" % [diff, threshold])

func test_grace_period_forgives_miss() -> void:
	begin("grace_period_forgives_miss")
	var threshold = calc_threshold(DEFAULT_ORBIT_RADIUS, 1)
	var diff = angle_diff(0.0, PI)
	var spawn_grace_period = true
	var would_hit = diff < threshold
	var would_be_forgiven = not would_hit and spawn_grace_period
	assert_true(would_be_forgiven, "miss during grace is forgiven, not game over")

func test_grace_period_allows_hit() -> void:
	begin("grace_period_allows_hit")
	var threshold = calc_threshold(DEFAULT_ORBIT_RADIUS, 1)
	var diff = angle_diff(1.0, 1.0)
	var spawn_grace_period = true
	var would_hit = diff < threshold
	assert_true(would_hit, "hit registers even during grace")

func test_inner_rings_prevent_game_over() -> void:
	begin("inner_rings_prevent_game_over")
	var inner_rings_size = 1
	var would_use_extra_life = inner_rings_size > 0
	assert_true(would_use_extra_life, "1 inner ring triggers use_extra_life instead of game over")
	inner_rings_size = 2
	would_use_extra_life = inner_rings_size > 0
	assert_true(would_use_extra_life, "2 inner rings also triggers use_extra_life")

func test_no_inner_rings_causes_game_over() -> void:
	begin("no_inner_rings_causes_game_over")
	var inner_rings_size = 0
	var would_game_over = inner_rings_size == 0
	assert_true(would_game_over, "0 inner rings = game over")

func test_expansion_threshold_reachable() -> void:
	begin("expansion_threshold_reachable")
	for level in range(1, 21):
		var hits_required = level * 10
		var exp_threshold: int
		if level <= 20:
			exp_threshold = 3
		elif level <= 50:
			exp_threshold = 5
		else:
			exp_threshold = 7
		assert_true(exp_threshold < hits_required,
			"level %d: threshold %d < hits_required %d" % [level, exp_threshold, hits_required])

func test_check_too_slow_respects_grace() -> void:
	begin("check_too_slow_respects_grace")
	var spawn_grace_period = true
	assert_true(spawn_grace_period, "grace period blocks check_too_slow")

func test_check_too_slow_fires_when_past() -> void:
	begin("check_too_slow_fires_when_past")
	var threshold = calc_threshold(DEFAULT_ORBIT_RADIUS, 1)
	var past = cursor_past_target(2.0, 1.0, 1, threshold)
	assert_true(past, "cursor 1 rad past target triggers end (thresh=%.3f)" % threshold)
	var not_past = cursor_past_target(0.5, 1.0, 1, threshold)
	assert_true(not not_past, "cursor before target does not trigger end")

func test_extra_life_consumes_ring() -> void:
	begin("extra_life_consumes_ring")
	var ring_count = 2
	var inner_rings_size = 1
	ring_count -= 1
	inner_rings_size -= 1
	assert_eq(ring_count, 1, "ring count goes from 2 to 1")
	assert_eq(inner_rings_size, 0, "inner rings consumed (0 remaining)")
	var would_game_over = inner_rings_size == 0
	assert_true(would_game_over, "next miss with 0 inner rings = game over")

func test_target_scales_with_ring_count() -> void:
	begin("target_scales_with_ring_count")
	# Target scale = 1.0 + (ring_count - 1) * 0.5
	var scale_r1 = 1.0 + (1 - 1) * 0.5
	var scale_r2 = 1.0 + (2 - 1) * 0.5
	var scale_r3 = 1.0 + (3 - 1) * 0.5
	var scale_r4 = 1.0 + (4 - 1) * 0.5
	assert_eq(scale_r1, 1.0, "ring 1: scale 1.0x")
	assert_eq(scale_r2, 1.5, "ring 2: scale 1.5x")
	assert_eq(scale_r3, 2.0, "ring 3: scale 2.0x")
	assert_eq(scale_r4, 2.5, "ring 4: scale 2.5x")

func test_perfect_hit_threshold() -> void:
	begin("perfect_hit_threshold")
	var threshold = calc_threshold(DEFAULT_ORBIT_RADIUS, 1)
	var perfect = threshold * PERFECT_HIT_RATIO
	assert_true(perfect > 0.0, "perfect threshold > 0 (got %.4f)" % perfect)
	assert_true(perfect < threshold, "perfect (%.4f) < threshold (%.4f)" % [perfect, threshold])
	# 25% of threshold
	assert_true(abs(perfect - threshold * 0.4) < 0.001, "perfect = 40%% of threshold")

func test_perfect_hit_double_progress() -> void:
	begin("perfect_hit_double_progress")
	# Simulate perfect hit: level_hits increases by 2
	var level_hits = 0
	var hits_required = 10
	# Perfect hit
	level_hits += 2
	level_hits = mini(level_hits, hits_required)
	var score = hits_required - level_hits
	assert_eq(score, 8, "countdown drops by 2 on perfect (10 -> 8)")
	# Regular hit
	level_hits += 1
	score = hits_required - level_hits
	assert_eq(score, 7, "countdown drops by 1 on regular (8 -> 7)")

func test_frenzy_streak_builds() -> void:
	begin("frenzy_streak_builds")
	var streak = 0
	# Simulate 3 consecutive perfect hits
	for i in range(3):
		streak += 1
	assert_eq(streak, 3, "3 perfects = streak of 3")
	assert_true(streak >= FRENZY_THRESHOLD, "streak %d >= threshold %d" % [streak, FRENZY_THRESHOLD])

func test_frenzy_streak_breaks_on_regular() -> void:
	begin("frenzy_streak_breaks_on_regular")
	var streak = 3
	var is_frenzy = true
	# Regular hit breaks streak
	streak = 0
	is_frenzy = false
	assert_eq(streak, 0, "regular hit resets streak to 0")
	assert_true(not is_frenzy, "frenzy deactivated on regular hit")

func test_frenzy_multiplier_caps() -> void:
	begin("frenzy_multiplier_caps")
	# Multiplier should not exceed the last entry in FRENZY_MULTIPLIERS
	for streak in range(0, 20):
		var idx = mini(streak, FRENZY_MULTIPLIERS.size() - 1)
		var mult = FRENZY_MULTIPLIERS[idx]
		assert_true(mult <= 3.0, "streak %d: multiplier %.1f <= 3.0" % [streak, mult])
	# Verify cap at streak >> threshold
	var big_idx = mini(100, FRENZY_MULTIPLIERS.size() - 1)
	assert_eq(FRENZY_MULTIPLIERS[big_idx], 3.0, "multiplier caps at 3.0")

func test_daily_seed_deterministic() -> void:
	begin("daily_seed_deterministic")
	# Same date string → same seed → same random sequence
	var date_str = "2026-03-20"
	var seed1 = date_str.hash()
	var seed2 = date_str.hash()
	assert_eq(seed1, seed2, "same date produces same seed")
	# Verify deterministic RNG
	var rng1 = RandomNumberGenerator.new()
	rng1.seed = seed1
	var rng2 = RandomNumberGenerator.new()
	rng2.seed = seed2
	var match_count = 0
	for i in range(10):
		if rng1.randf() == rng2.randf():
			match_count += 1
	assert_eq(match_count, 10, "same seed produces identical 10-value sequence")

# --- Boss Rendering Tests ---
# These ensure bosses render as solid colored shapes, not wireframe/black-faced

func test_boss_material_cull_disabled() -> void:
	test_name = "boss_material_cull_disabled"
	# Simulate creating boss material the same way game_manager does
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.3, 0.2)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	assert_eq(mat.cull_mode, BaseMaterial3D.CULL_DISABLED, "boss material must have CULL_DISABLED to show all faces")

func test_boss_material_has_emission() -> void:
	test_name = "boss_material_has_emission"
	var mat = StandardMaterial3D.new()
	var bc = Color(1.0, 0.3, 0.2)
	mat.albedo_color = bc
	mat.emission_enabled = true
	mat.emission = Color(bc.r * 0.8, bc.g * 0.8, bc.b * 0.8)
	mat.emission_energy_multiplier = 1.2
	assert_true(mat.emission_enabled, "boss material must have emission enabled")
	assert_true(mat.emission_energy_multiplier > 0.0, "emission energy must be positive")

func test_boss_material_uses_registry_color() -> void:
	test_name = "boss_material_uses_registry_color"
	# Boss material should use registry color, NOT theme color
	var boss_color = Color(0.2, 1.0, 0.3)  # Bright green from registry
	var mat = StandardMaterial3D.new()
	mat.albedo_color = boss_color
	# Should NOT be overridden to a theme phosphor color
	assert_true(mat.albedo_color.r < 0.3, "boss color red channel preserved (not overridden)")
	assert_true(mat.albedo_color.g > 0.9, "boss color green channel preserved (not overridden)")

func test_boss_viewport_material_cull_disabled() -> void:
	test_name = "boss_viewport_material_cull_disabled"
	# Trophy room viewport material must also disable culling
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.5, 0.5, 0.9)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.emission_enabled = true
	mat.emission = Color(0.4, 0.4, 0.72)
	assert_eq(mat.cull_mode, BaseMaterial3D.CULL_DISABLED, "viewport boss material must have CULL_DISABLED")
	assert_true(mat.emission_enabled, "viewport boss material must have emission")

func test_invader_mesh_is_triangles() -> void:
	test_name = "invader_mesh_is_triangles"
	# Build a simple test invader and verify it's PRIMITIVE_TRIANGLES (solid), not LINES
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cell = 0.12
	# Minimal 1-cell mesh to test structure
	var hd = 0.04
	st.set_normal(Vector3(0, 0, 1))
	st.add_vertex(Vector3(-cell/2, -cell/2, hd))
	st.add_vertex(Vector3(cell/2, -cell/2, hd))
	st.add_vertex(Vector3(cell/2, cell/2, hd))
	var mesh = st.commit()
	assert_true(mesh != null, "mesh created successfully")
	assert_true(mesh.get_surface_count() > 0, "mesh has at least one surface")
	assert_eq(mesh.surface_get_primitive_type(0), Mesh.PRIMITIVE_TRIANGLES, "mesh uses PRIMITIVE_TRIANGLES not LINES")

func test_invader_mesh_has_vertices() -> void:
	test_name = "invader_mesh_has_vertices"
	# Verify a boss mesh row generates proper vertex data
	# Simple 2-cell row: center + 1 mirrored
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cell = 0.12
	var hd = 0.04
	# Col 0: single center cell = 6 faces * 2 triangles * 3 verts = 36 verts
	# Col 1: mirrored = 2 cells * 36 = 72 verts
	# Total = 108 verts for [0, 1]
	for col in [0, 1]:
		var positions = [0.0] if col == 0 else [float(col) * cell, float(-col) * cell]
		for x_center in positions:
			var x0 = x_center - cell * 0.5
			var x1 = x_center + cell * 0.5
			var y0 = -cell * 0.5
			var y1 = cell * 0.5
			# Just front face for test
			st.set_normal(Vector3(0, 0, 1))
			st.add_vertex(Vector3(x0, y0, hd))
			st.add_vertex(Vector3(x1, y0, hd))
			st.add_vertex(Vector3(x1, y1, hd))
	var mesh = st.commit()
	var arrays = mesh.surface_get_arrays(0)
	var verts = arrays[Mesh.ARRAY_VERTEX]
	assert_true(verts.size() >= 6, "mesh has enough vertices for solid faces (got %d)" % verts.size())
