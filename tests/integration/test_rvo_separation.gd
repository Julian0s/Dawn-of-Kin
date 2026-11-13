extends TestCase
## Integration & regression tests for T1.9 (RVO dynamic avoidance + occupied destination separation):
## Tests A-G covering head-on/diagonal crossings, sequential & rapid same-destination orders,
## group separation & mid-move replacement, WallGap/Ramp/Plateau ledge safety,
## stationary IDLE protection, cancellation, ClosedEnclosure unreachable, stuck blocker, spam,
## and invariance under lateral offsets & issuance ordering.

const MAIN_SCENE: PackedScene = preload("res://src/main/main.tscn")
const MAX_NAV_WAIT_FRAMES: int = 120
const MAX_MOVE_FRAMES: int = 600 # 10 seconds at 60 Hz
const CONTACT_DIAMETER_M: float = 0.80
const FINAL_MIN_SEPARATION_M: float = 1.00
const ARRIVAL_TOLERANCE_M: float = 0.50


func _spawn_main_scene() -> Dictionary:
	var main_root: MainScene = MAIN_SCENE.instantiate() as MainScene
	add_test_child(main_root)

	var test_map: TestMap = main_root.get_node_or_null("TestMap") as TestMap
	var nav: WorldNavigation = test_map.get_navigation() if test_map != null else null
	if nav != null:
		var wait_frames: int = 0
		while not nav.is_navigation_ready() and wait_frames < MAX_NAV_WAIT_FRAMES:
			await wait_physics_frames(1)
			wait_frames += 1

	await wait_process_frames(4)
	await wait_physics_frames(4)

	var rig: RtsCameraRig = main_root.get_node_or_null("RtsCameraRig") as RtsCameraRig
	if rig != null:
		rig.edge_pan_enabled = false

	var leader_a: Unit = null
	var leader_b: Unit = null
	for unit: Unit in main_root.get_units():
		if unit.get_character_id() == &"leader_a":
			leader_a = unit
		elif unit.get_character_id() == &"leader_b":
			leader_b = unit

	return {
		"main": main_root,
		"test_map": test_map,
		"nav": nav,
		"rig": rig,
		"selection_manager": main_root.get_selection_manager(),
		"command_controller": main_root.get_command_controller(),
		"destination_marker": main_root.get_destination_marker(),
		"leader_a": leader_a,
		"leader_b": leader_b,
	}


func _reset_unit_at(unit: Unit, pos: Vector3) -> void:
	unit.cancel_current_order()
	unit.velocity = Vector3.ZERO
	unit.global_position = pos


func _dist_xz(a: Vector3, b: Vector3) -> float:
	var dx: float = a.x - b.x
	var dz: float = a.z - b.z
	return sqrt(dx * dx + dz * dz)


func _track_pair_until_idle(
	unit_a: Unit,
	unit_b: Unit,
	max_frames: int = MAX_MOVE_FRAMES
) -> Dictionary:
	var min_dist: float = INF
	var flip_a: int = 0
	var flip_b: int = 0
	var prev_yaw_a: float = NAN
	var prev_yaw_b: float = NAN
	var prev_delta_a: float = 0.0
	var prev_delta_b: float = 0.0
	var min_y_a: float = INF
	var min_y_b: float = INF
	var frames: int = 0

	while frames < max_frames:
		var dist: float = _dist_xz(unit_a.global_position, unit_b.global_position)
		if dist < min_dist:
			min_dist = dist
		min_y_a = minf(min_y_a, unit_a.global_position.y)
		min_y_b = minf(min_y_b, unit_b.global_position.y)

		var yaw_a: float = unit_a.rotation.y
		if not is_nan(prev_yaw_a):
			var d_a: float = wrapf(yaw_a - prev_yaw_a, -PI, PI)
			if absf(d_a) > 0.35 and absf(prev_delta_a) > 0.35 and signf(d_a) != signf(prev_delta_a):
				flip_a += 1
			if absf(d_a) > 0.01:
				prev_delta_a = d_a
		prev_yaw_a = yaw_a

		var yaw_b: float = unit_b.rotation.y
		if not is_nan(prev_yaw_b):
			var d_b: float = wrapf(yaw_b - prev_yaw_b, -PI, PI)
			if absf(d_b) > 0.35 and absf(prev_delta_b) > 0.35 and signf(d_b) != signf(prev_delta_b):
				flip_b += 1
			if absf(d_b) > 0.01:
				prev_delta_b = d_b
		prev_yaw_b = yaw_b

		if unit_a.get_state() == Unit.State.IDLE and unit_b.get_state() == Unit.State.IDLE:
			break
		await wait_physics_frames(1)
		frames += 1

	return {
		"frames": frames,
		"min_dist_xz": min_dist,
		"final_dist_xz": _dist_xz(unit_a.global_position, unit_b.global_position),
		"flip_a": flip_a,
		"flip_b": flip_b,
		"min_y_a": min_y_a,
		"min_y_b": min_y_b,
	}


func _command_single(
	selection: SelectionManager,
	cmd: CommandController,
	unit: Unit,
	target: Vector3
) -> MoveOrder:
	selection.select_single(unit)
	cmd.command_at(PickResult.from_ground(target, Vector3.UP))
	return unit.get_current_order() as MoveOrder


## Test A: Collinear head-on crossing on individual orders avoids interpenetration without flips or deadlock.
func test_01_head_on_crossing_avoids_interpenetration() -> void:
	var ctx: Dictionary = await _spawn_main_scene()
	var unit_a: Unit = ctx["leader_a"] as Unit
	var unit_b: Unit = ctx["leader_b"] as Unit
	assert_not_null(unit_a)
	assert_not_null(unit_b)

	_reset_unit_at(unit_a, Vector3(-5.0, 0.0, 0.0))
	_reset_unit_at(unit_b, Vector3(5.0, 0.0, 0.0))
	await wait_physics_frames(2)

	var a_finished: Array[UnitOrder] = []
	var b_finished: Array[UnitOrder] = []
	unit_a.order_finished.connect(func(order: UnitOrder) -> void: a_finished.append(order))
	unit_b.order_finished.connect(func(order: UnitOrder) -> void: b_finished.append(order))

	var target_a := Vector3(5.0, 0.0, 0.0)
	var target_b := Vector3(-5.0, 0.0, 0.0)
	unit_a.issue_order(MoveOrder.new(target_a))
	unit_b.issue_order(MoveOrder.new(target_b))

	var metrics: Dictionary = await _track_pair_until_idle(unit_a, unit_b)
	assert_lt(float(metrics["frames"]), float(MAX_MOVE_FRAMES), "Head-on crossing must not deadlock")
	assert_true(
		float(metrics["min_dist_xz"]) >= CONTACT_DIAMETER_M,
		"Head-on units must remain >= %.2fm apart (got %.3fm)" % [CONTACT_DIAMETER_M, float(metrics["min_dist_xz"])]
	)
	assert_eq(int(metrics["flip_a"]), 0, "LeaderA yaw must not oscillate during head-on avoidance")
	assert_eq(int(metrics["flip_b"]), 0, "LeaderB yaw must not oscillate during head-on avoidance")
	assert_eq(unit_a.get_state(), Unit.State.IDLE)
	assert_eq(unit_b.get_state(), Unit.State.IDLE)
	assert_eq(a_finished.size(), 1)
	assert_eq(b_finished.size(), 1)
	assert_eq(a_finished[0].status, UnitOrder.Status.SUCCEEDED)
	assert_eq(b_finished[0].status, UnitOrder.Status.SUCCEEDED)
	assert_true(_dist_xz(unit_a.global_position, target_a) <= ARRIVAL_TOLERANCE_M)
	assert_true(_dist_xz(unit_b.global_position, target_b) <= ARRIVAL_TOLERANCE_M)


## Test B: Diagonal X-crossing avoids interpenetration cleanly.
func test_02_diagonal_crossing_avoids_interpenetration() -> void:
	var ctx: Dictionary = await _spawn_main_scene()
	var unit_a: Unit = ctx["leader_a"] as Unit
	var unit_b: Unit = ctx["leader_b"] as Unit

	_reset_unit_at(unit_a, Vector3(-4.5, 0.0, -4.5))
	_reset_unit_at(unit_b, Vector3(4.5, 0.0, -4.5))
	await wait_physics_frames(2)

	var a_finished: Array[UnitOrder] = []
	var b_finished: Array[UnitOrder] = []
	unit_a.order_finished.connect(func(order: UnitOrder) -> void: a_finished.append(order))
	unit_b.order_finished.connect(func(order: UnitOrder) -> void: b_finished.append(order))

	var target_a := Vector3(4.5, 0.0, 4.5)
	var target_b := Vector3(-4.5, 0.0, 4.5)
	unit_a.issue_order(MoveOrder.new(target_a))
	unit_b.issue_order(MoveOrder.new(target_b))

	var metrics: Dictionary = await _track_pair_until_idle(unit_a, unit_b)
	assert_lt(float(metrics["frames"]), float(MAX_MOVE_FRAMES))
	assert_true(
		float(metrics["min_dist_xz"]) >= CONTACT_DIAMETER_M,
		"Diagonal crossing units must remain >= %.2fm apart (got %.3fm)" % [CONTACT_DIAMETER_M, float(metrics["min_dist_xz"])]
	)
	assert_eq(int(metrics["flip_a"]), 0)
	assert_eq(int(metrics["flip_b"]), 0)
	assert_eq(unit_a.get_state(), Unit.State.IDLE)
	assert_eq(unit_b.get_state(), Unit.State.IDLE)
	assert_eq(a_finished[0].status, UnitOrder.Status.SUCCEEDED)
	assert_eq(b_finished[0].status, UnitOrder.Status.SUCCEEDED)
	assert_true(_dist_xz(unit_a.global_position, target_a) <= ARRIVAL_TOLERANCE_M)
	assert_true(_dist_xz(unit_b.global_position, target_b) <= ARRIVAL_TOLERANCE_M)


## Test C: Sequential and rapid individual commands to the same/occupied destination separate cleanly
## without altering selection or misclassifying reachable occupancy adjustment as unreachable.
func test_03_sequential_and_rapid_same_destination_commands_separate_cleanly() -> void:
	var ctx: Dictionary = await _spawn_main_scene()
	var unit_a: Unit = ctx["leader_a"] as Unit
	var unit_b: Unit = ctx["leader_b"] as Unit
	var selection: SelectionManager = ctx["selection_manager"] as SelectionManager
	var cmd: CommandController = ctx["command_controller"] as CommandController

	# Subcase C1: LeaderA parked IDLE at (0,0,0); order LeaderB to exact (0,0,0)
	_reset_unit_at(unit_a, Vector3(0.0, 0.0, 0.0))
	_reset_unit_at(unit_b, Vector3(-6.0, 0.0, 0.0))
	await wait_physics_frames(2)

	var a_start: Vector3 = unit_a.global_position
	var b_order_c1: MoveOrder = _command_single(selection, cmd, unit_b, Vector3(0.0, 0.0, 0.0))
	assert_not_null(b_order_c1)
	assert_true(b_order_c1.adjusted_for_occupancy, "Command onto IDLE ally must mark adjusted_for_occupancy=true")
	assert_false(b_order_c1.is_partial_unreachable, "Reachable occupied slot adjustment must not be partial_unreachable")
	assert_true(selection.is_selected(unit_b) and selection.get_selection_count() == 1, "Command must preserve selection")

	var metrics_c1: Dictionary = await _track_pair_until_idle(unit_a, unit_b)
	assert_lt(float(metrics_c1["frames"]), float(MAX_MOVE_FRAMES))
	assert_true(float(metrics_c1["min_dist_xz"]) >= CONTACT_DIAMETER_M)
	assert_true(
		float(metrics_c1["final_dist_xz"]) >= FINAL_MIN_SEPARATION_M,
		"Parked + arriving unit final spacing must be >= %.2fm (got %.3fm)" % [FINAL_MIN_SEPARATION_M, float(metrics_c1["final_dist_xz"])]
	)
	assert_vec3_near(unit_a.global_position, a_start, 0.01, "IDLE ally must remain stationary")
	assert_eq(b_order_c1.status, UnitOrder.Status.SUCCEEDED)

	# Subcase C2: Rapid sequential commands (1 physics frame apart) targeting exact (0, 0, 5)
	_reset_unit_at(unit_a, Vector3(-6.0, 0.0, 3.0))
	_reset_unit_at(unit_b, Vector3(6.0, 0.0, 3.0))
	await wait_physics_frames(2)

	var shared_target := Vector3(0.0, 0.0, 5.0)
	var a_order_c2: MoveOrder = _command_single(selection, cmd, unit_a, shared_target)
	assert_not_null(a_order_c2)
	assert_false(a_order_c2.adjusted_for_occupancy)
	await wait_physics_frames(1)

	var b_order_c2: MoveOrder = _command_single(selection, cmd, unit_b, shared_target)
	assert_not_null(b_order_c2)
	assert_true(b_order_c2.adjusted_for_occupancy, "Second sequential command to reserved target must adjust slot")
	assert_false(b_order_c2.is_partial_unreachable)

	var metrics_c2: Dictionary = await _track_pair_until_idle(unit_a, unit_b)
	assert_lt(float(metrics_c2["frames"]), float(MAX_MOVE_FRAMES))
	assert_true(float(metrics_c2["min_dist_xz"]) >= CONTACT_DIAMETER_M)
	assert_true(
		float(metrics_c2["final_dist_xz"]) >= FINAL_MIN_SEPARATION_M,
		"Rapid sequential targets must finish >= %.2fm apart (got %.3fm)" % [FINAL_MIN_SEPARATION_M, float(metrics_c2["final_dist_xz"])]
	)
	assert_eq(a_order_c2.status, UnitOrder.Status.SUCCEEDED)
	assert_eq(b_order_c2.status, UnitOrder.Status.SUCCEEDED)

	# Subcase C3: Contextual right-click directly onto ally unit collider
	_reset_unit_at(unit_a, Vector3(-4.0, 0.0, -1.0))
	_reset_unit_at(unit_b, Vector3(2.0, 0.0, -1.0))
	await wait_physics_frames(2)

	selection.select_single(unit_a)
	var handled_unit_pick: bool = cmd.command_at(
		PickResult.from_unit(unit_b, unit_b.global_position, Vector3.UP, unit_b)
	)
	assert_true(handled_unit_pick)
	assert_true(selection.is_selected(unit_a) and selection.get_selection_count() == 1)
	var a_order_c3: MoveOrder = unit_a.get_current_order() as MoveOrder
	assert_not_null(a_order_c3)
	assert_true(a_order_c3.adjusted_for_occupancy)

	var metrics_c3: Dictionary = await _track_pair_until_idle(unit_a, unit_b)
	assert_true(float(metrics_c3["min_dist_xz"]) >= CONTACT_DIAMETER_M)
	assert_true(float(metrics_c3["final_dist_xz"]) >= FINAL_MIN_SEPARATION_M)
	assert_eq(a_order_c3.status, UnitOrder.Status.SUCCEEDED)


## Test D: Group movement preserves ~2m slot separation and supports mid-move replacement cleanly.
func test_04_group_movement_preserves_separation_and_order_replacement() -> void:
	var ctx: Dictionary = await _spawn_main_scene()
	var unit_a: Unit = ctx["leader_a"] as Unit
	var unit_b: Unit = ctx["leader_b"] as Unit
	var selection: SelectionManager = ctx["selection_manager"] as SelectionManager
	var cmd: CommandController = ctx["command_controller"] as CommandController

	_reset_unit_at(unit_a, Vector3(-5.0, 0.0, 2.0))
	_reset_unit_at(unit_b, Vector3(-3.0, 0.0, 2.0))
	await wait_physics_frames(2)

	selection.set_selection([unit_a, unit_b])
	assert_true(cmd.command_at(PickResult.from_ground(Vector3(5.0, 0.0, 2.0), Vector3.UP)))
	await wait_physics_frames(18)

	# Mid-move order replacement while moving in formation
	assert_true(cmd.command_at(PickResult.from_ground(Vector3(-2.0, 0.0, 12.0), Vector3.UP)))

	var metrics: Dictionary = await _track_pair_until_idle(unit_a, unit_b)
	assert_lt(float(metrics["frames"]), float(MAX_MOVE_FRAMES))
	assert_true(
		float(metrics["min_dist_xz"]) >= CONTACT_DIAMETER_M,
		"Group + mid-move replacement must preserve separation (got %.3fm)" % float(metrics["min_dist_xz"])
	)
	assert_true(
		float(metrics["final_dist_xz"]) >= FINAL_MIN_SEPARATION_M,
		"Group final arrival spacing must stay >= %.2fm (got %.3fm)" % [FINAL_MIN_SEPARATION_M, float(metrics["final_dist_xz"])]
	)
	assert_eq(unit_a.get_state(), Unit.State.IDLE)
	assert_eq(unit_b.get_state(), Unit.State.IDLE)


## Test E: Bottlenecks & ledges — WallGap crossing, Ramp climb/descent, and Plateau crossing without falling off.
func test_05_bottlenecks_wall_gap_ramp_and_plateau_safety() -> void:
	var ctx: Dictionary = await _spawn_main_scene()
	var unit_a: Unit = ctx["leader_a"] as Unit
	var unit_b: Unit = ctx["leader_b"] as Unit
	var selection: SelectionManager = ctx["selection_manager"] as SelectionManager
	var cmd: CommandController = ctx["command_controller"] as CommandController

	# E1: Opposite crossing through WallGap (gap at x in [-2, +2], z = -6)
	_reset_unit_at(unit_a, Vector3(0.0, 0.0, -2.0))
	_reset_unit_at(unit_b, Vector3(0.0, 0.0, -10.0))
	await wait_physics_frames(2)

	var a_e1: MoveOrder = _command_single(selection, cmd, unit_a, Vector3(0.0, 0.0, -10.0))
	var b_e1: MoveOrder = _command_single(selection, cmd, unit_b, Vector3(0.0, 0.0, -2.0))
	var m_e1: Dictionary = await _track_pair_until_idle(unit_a, unit_b)
	assert_lt(float(m_e1["frames"]), float(MAX_MOVE_FRAMES))
	assert_true(
		float(m_e1["min_dist_xz"]) >= CONTACT_DIAMETER_M,
		"WallGap crossing must avoid overlap (got %.3fm)" % float(m_e1["min_dist_xz"])
	)
	assert_eq(a_e1.status, UnitOrder.Status.SUCCEEDED)
	assert_eq(b_e1.status, UnitOrder.Status.SUCCEEDED)

	# E2: Opposite crossing across Ramp/Plateau (Ramp x=5..13, z=-14; Plateau x=13..23, y=2.0, z=-14)
	_reset_unit_at(unit_a, Vector3(3.0, 0.0, -14.0))
	_reset_unit_at(unit_b, Vector3(17.5, 2.0, -14.0))
	await wait_physics_frames(4)

	var a_e2: MoveOrder = _command_single(selection, cmd, unit_a, Vector3(17.5, 2.0, -14.0))
	var b_e2: MoveOrder = _command_single(selection, cmd, unit_b, Vector3(3.0, 0.0, -14.0))
	var m_e2: Dictionary = await _track_pair_until_idle(unit_a, unit_b, 800)
	assert_lt(float(m_e2["frames"]), 800.0)
	assert_true(
		float(m_e2["min_dist_xz"]) >= CONTACT_DIAMETER_M,
		"Ramp/Plateau crossing must maintain >= %.2fm separation (got %.3fm)" % [CONTACT_DIAMETER_M, float(m_e2["min_dist_xz"])]
	)
	assert_true(float(m_e2["min_y_a"]) >= -0.15, "LeaderA must never drop below ground/ramp surface")
	assert_true(float(m_e2["min_y_b"]) >= -0.15, "LeaderB must never drop below ground/ramp surface")
	assert_true(unit_a.global_position.y >= 1.85, "LeaderA must reach elevated plateau (~2.0m)")
	assert_true(unit_b.global_position.y <= 0.25, "LeaderB must descend safely to ground level")
	assert_eq(a_e2.status, UnitOrder.Status.SUCCEEDED)
	assert_eq(b_e2.status, UnitOrder.Status.SUCCEEDED)

	# E3: Group move along narrow plateau edge near cliff (z=-17.5) keeps both safely on plateau
	selection.set_selection([unit_a, unit_b])
	_reset_unit_at(unit_a, Vector3(14.5, 2.0, -14.0))
	_reset_unit_at(unit_b, Vector3(14.5, 2.0, -16.0))
	await wait_physics_frames(4)
	assert_true(cmd.command_at(PickResult.from_ground(Vector3(21.0, 2.0, -16.0), Vector3.UP)))
	var m_e3: Dictionary = await _track_pair_until_idle(unit_a, unit_b)
	assert_lt(float(m_e3["frames"]), float(MAX_MOVE_FRAMES))
	assert_true(float(m_e3["min_dist_xz"]) >= CONTACT_DIAMETER_M)
	assert_true(unit_a.global_position.y >= 1.85 and unit_b.global_position.y >= 1.85, "Plateau edge avoidance must not shove unit off ledge")


## Test F: Preserves stationary IDLE units, mid-avoidance cancellation, ClosedEnclosure unreachable,
## dynamic stuck detection, and rapid command spam.
func test_06_rvo_preserves_idle_units_cancellation_unreachable_stuck_and_spam() -> void:
	var ctx: Dictionary = await _spawn_main_scene()
	var unit_a: Unit = ctx["leader_a"] as Unit
	var unit_b: Unit = ctx["leader_b"] as Unit
	var selection: SelectionManager = ctx["selection_manager"] as SelectionManager
	var cmd: CommandController = ctx["command_controller"] as CommandController
	var main_root: MainScene = ctx["main"] as MainScene

	# F1: Moving unit dodges IDLE partner while IDLE partner remains completely stationary
	_reset_unit_at(unit_a, Vector3(-5.0, 0.0, 0.0))
	_reset_unit_at(unit_b, Vector3(0.0, 0.0, 0.0))
	await wait_physics_frames(2)

	var idle_start: Vector3 = unit_b.global_position
	var a_f1: MoveOrder = _command_single(selection, cmd, unit_a, Vector3(5.0, 0.0, 0.0))
	var m_f1: Dictionary = await _track_pair_until_idle(unit_a, unit_b)
	assert_lt(float(m_f1["frames"]), float(MAX_MOVE_FRAMES))
	assert_true(float(m_f1["min_dist_xz"]) >= CONTACT_DIAMETER_M)
	assert_vec3_near(unit_b.global_position, idle_start, 0.01, "IDLE unit must not be displaced by passing ally")
	assert_eq(a_f1.status, UnitOrder.Status.SUCCEEDED)

	# F2: Cancel order mid-avoidance cleanly halts movement
	_reset_unit_at(unit_a, Vector3(-4.0, 0.0, 0.0))
	_reset_unit_at(unit_b, Vector3(4.0, 0.0, 0.0))
	await wait_physics_frames(2)
	var a_cancel: MoveOrder = _command_single(selection, cmd, unit_a, Vector3(4.0, 0.0, 0.0))
	var _b_cancel: MoveOrder = _command_single(selection, cmd, unit_b, Vector3(-4.0, 0.0, 0.0))
	await wait_physics_frames(20)
	unit_a.cancel_current_order()
	await wait_physics_frames(2)
	assert_eq(unit_a.get_state(), Unit.State.IDLE)
	assert_eq(a_cancel.status, UnitOrder.Status.CANCELLED)

	# F3: ClosedEnclosure unreachable ground target preserves FAILED/unreachable contract (not adjusted_for_occupancy)
	_reset_unit_at(unit_a, Vector3(-6.0, 0.0, 12.0))
	_reset_unit_at(unit_b, Vector3(-16.0, 0.0, 12.0)) # even with an entity inside enclosure
	await wait_physics_frames(2)
	var a_unreach: MoveOrder = _command_single(selection, cmd, unit_a, Vector3(-16.0, 0.0, 12.0))
	assert_not_null(a_unreach)
	assert_false(a_unreach.adjusted_for_occupancy, "ClosedEnclosure unreachable target must not set adjusted_for_occupancy")
	assert_true(a_unreach.is_partial_unreachable)
	var f3_frames: int = 0
	while unit_a.get_state() != Unit.State.IDLE and f3_frames < MAX_MOVE_FRAMES:
		await wait_physics_frames(1)
		f3_frames += 1
	assert_lt(float(f3_frames), float(MAX_MOVE_FRAMES))
	assert_eq(a_unreach.status, UnitOrder.Status.FAILED)

	# F4: Unbaked dynamic obstacle blocker triggers stuck failure cleanly without breaking RVO
	_reset_unit_at(unit_a, Vector3(-6.0, 0.0, -2.0))
	_reset_unit_at(unit_b, Vector3(12.0, 0.0, 12.0))
	var blocker := StaticBody3D.new()
	blocker.collision_layer = CollisionLayers.MASK_OBSTACLES
	blocker.collision_mask = 0
	var shape_node := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.5, 2.5, 16.0)
	shape_node.shape = box
	blocker.add_child(shape_node)
	main_root.add_child(blocker)
	blocker.global_position = Vector3(-2.0, 1.25, -2.0)
	await wait_physics_frames(2)

	var a_stuck := MoveOrder.new(Vector3(6.0, 0.0, -2.0))
	unit_a.issue_order(a_stuck)
	var f4_frames: int = 0
	while unit_a.get_state() != Unit.State.IDLE and f4_frames < MAX_MOVE_FRAMES:
		await wait_physics_frames(1)
		f4_frames += 1
	blocker.queue_free()
	await wait_physics_frames(2)
	assert_lt(float(f4_frames), float(MAX_MOVE_FRAMES))
	assert_eq(a_stuck.status, UnitOrder.Status.FAILED)
	assert_eq(a_stuck.failure_reason, "stuck")

	# F5: Rapid command spam converges cleanly to final target without overlap
	_reset_unit_at(unit_a, Vector3(-5.0, 0.0, 6.0))
	_reset_unit_at(unit_b, Vector3(5.0, 0.0, 6.0))
	await wait_physics_frames(2)
	for i: int in range(6):
		var z_off: float = float(i % 3) * 1.5
		_command_single(selection, cmd, unit_a, Vector3(4.0, 0.0, 6.0 + z_off))
		_command_single(selection, cmd, unit_b, Vector3(-4.0, 0.0, 6.0 + z_off))
		await wait_physics_frames(2)
	var final_a: Vector3 = Vector3(3.0, 0.0, 8.0)
	var final_b: Vector3 = Vector3(-3.0, 0.0, 8.0)
	_command_single(selection, cmd, unit_a, final_a)
	_command_single(selection, cmd, unit_b, final_b)

	var m_f5: Dictionary = await _track_pair_until_idle(unit_a, unit_b)
	assert_lt(float(m_f5["frames"]), float(MAX_MOVE_FRAMES))
	assert_true(float(m_f5["min_dist_xz"]) >= CONTACT_DIAMETER_M)
	assert_true(_dist_xz(unit_a.global_position, final_a) <= ARRIVAL_TOLERANCE_M)
	assert_true(_dist_xz(unit_b.global_position, final_b) <= ARRIVAL_TOLERANCE_M)


## Test G: Robustness across initial lateral offset perturbations and swapped issuance ordering.
func test_07_robustness_across_offset_variations_and_issue_orders() -> void:
	var ctx: Dictionary = await _spawn_main_scene()
	var unit_a: Unit = ctx["leader_a"] as Unit
	var unit_b: Unit = ctx["leader_b"] as Unit
	var selection: SelectionManager = ctx["selection_manager"] as SelectionManager
	var cmd: CommandController = ctx["command_controller"] as CommandController

	var lateral_offsets: Array[float] = [-0.2, 0.0, 0.2]
	for offset_z: float in lateral_offsets:
		for swap_order: bool in [false, true]:
			_reset_unit_at(unit_a, Vector3(-4.5, 0.0, offset_z))
			_reset_unit_at(unit_b, Vector3(4.5, 0.0, -offset_z))
			await wait_physics_frames(2)

			var o_a: MoveOrder
			var o_b: MoveOrder
			if not swap_order:
				o_a = _command_single(selection, cmd, unit_a, Vector3(4.5, 0.0, offset_z))
				o_b = _command_single(selection, cmd, unit_b, Vector3(-4.5, 0.0, -offset_z))
			else:
				o_b = _command_single(selection, cmd, unit_b, Vector3(-4.5, 0.0, -offset_z))
				o_a = _command_single(selection, cmd, unit_a, Vector3(4.5, 0.0, offset_z))

			var metrics: Dictionary = await _track_pair_until_idle(unit_a, unit_b)
			assert_lt(float(metrics["frames"]), float(MAX_MOVE_FRAMES))
			assert_true(
				float(metrics["min_dist_xz"]) >= CONTACT_DIAMETER_M,
				"Offset=%.1f swap=%s must keep >= %.2fm (got %.3fm)" % [
					offset_z, str(swap_order), CONTACT_DIAMETER_M, float(metrics["min_dist_xz"])
				]
			)
			assert_eq(o_a.status, UnitOrder.Status.SUCCEEDED)
			assert_eq(o_b.status, UnitOrder.Status.SUCCEEDED)

	# Also verify swapped issuance order on rapid sequential same-target individual orders
	for swap_same: bool in [false, true]:
		_reset_unit_at(unit_a, Vector3(-4.5, 0.0, 2.0))
		_reset_unit_at(unit_b, Vector3(4.5, 0.0, 2.0))
		await wait_physics_frames(2)

		var target := Vector3(0.0, 0.0, 2.0)
		var first_order: MoveOrder
		var second_order: MoveOrder
		if not swap_same:
			first_order = _command_single(selection, cmd, unit_a, target)
			await wait_physics_frames(1)
			second_order = _command_single(selection, cmd, unit_b, target)
		else:
			first_order = _command_single(selection, cmd, unit_b, target)
			await wait_physics_frames(1)
			second_order = _command_single(selection, cmd, unit_a, target)

		assert_false(first_order.adjusted_for_occupancy)
		assert_true(second_order.adjusted_for_occupancy)
		var m_same: Dictionary = await _track_pair_until_idle(unit_a, unit_b)
		assert_lt(float(m_same["frames"]), float(MAX_MOVE_FRAMES))
		assert_true(float(m_same["min_dist_xz"]) >= CONTACT_DIAMETER_M)
		assert_true(float(m_same["final_dist_xz"]) >= FINAL_MIN_SEPARATION_M)
		assert_eq(first_order.status, UnitOrder.Status.SUCCEEDED)
		assert_eq(second_order.status, UnitOrder.Status.SUCCEEDED)
