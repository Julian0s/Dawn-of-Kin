extends TestCase
## Integration tests for T1.5 Unit, UnitMovement, CharacterDefinition, and MoveOrder:
## simple movement + smooth rotation, wall-gap obstacle avoidance, ramp climb/descent,
## unreachable enclosure fallback, order replacement, stuck detection/recovery,
## pre-ready/invalid order handling, and Main scene protagonists.

const TEST_MAP_SCENE: PackedScene = preload("res://levels/test_map/test_map.tscn")
const MAIN_SCENE: PackedScene = preload("res://src/main/main.tscn")
const UNIT_SCENE: PackedScene = preload("res://src/units/unit.tscn")
const LEADER_A_DEF: CharacterDefinition = preload("res://data/characters/leader_a.tres")
const LEADER_B_DEF: CharacterDefinition = preload("res://data/characters/leader_b.tres")

const MAX_NAV_WAIT_FRAMES: int = 120
const MAX_MOVE_FRAMES: int = 600 # 10 seconds at 60 Hz physics


func _setup_map_and_unit(spawn_pos: Vector3, def: CharacterDefinition = LEADER_A_DEF) -> Dictionary:
	var test_map: TestMap = TEST_MAP_SCENE.instantiate() as TestMap
	add_test_child(test_map)
	var nav: WorldNavigation = test_map.get_navigation()
	assert_not_null(nav, "TestMap must expose WorldNavigation")
	if nav == null:
		return {}

	var ready_ok: bool = await _wait_for_navigation_ready(nav)
	assert_true(ready_ok, "WorldNavigation must become ready within bounded frames")
	if not ready_ok:
		return {}

	var unit: Unit = UNIT_SCENE.instantiate() as Unit
	unit.definition = def
	test_map.add_child(unit)
	unit.global_position = spawn_pos
	unit.set_world_navigation(nav)
	await wait_physics_frames(2)

	return {
		"map": test_map,
		"nav": nav,
		"unit": unit,
	}


func _wait_for_navigation_ready(nav: WorldNavigation) -> bool:
	var frames: int = 0
	while not nav.is_navigation_ready() and frames < MAX_NAV_WAIT_FRAMES:
		await wait_physics_frames(1)
		frames += 1
	return nav.is_navigation_ready()


func _distance_xz(a: Vector3, b: Vector3) -> float:
	var dx: float = a.x - b.x
	var dz: float = a.z - b.z
	return sqrt(dx * dx + dz * dz)


func _raycast_terrain_y(space_state: PhysicsDirectSpaceState3D, pos: Vector3) -> float:
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		Vector3(pos.x, pos.y + 3.0, pos.z),
		Vector3(pos.x, pos.y - 5.0, pos.z),
		CollisionLayers.MASK_TERRAIN
	)
	query.collide_with_bodies = true
	query.collide_with_areas = false
	var hit: Dictionary = space_state.intersect_ray(query)
	if hit.is_empty():
		return NAN
	return (hit["position"] as Vector3).y


func _segment_hits_obstacle(space_state: PhysicsDirectSpaceState3D, from_pos: Vector3, to_pos: Vector3) -> bool:
	var a: Vector3 = from_pos + Vector3(0.0, 0.8, 0.0)
	var b: Vector3 = to_pos + Vector3(0.0, 0.8, 0.0)
	if a.distance_squared_to(b) < 0.0001:
		return false
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(a, b, CollisionLayers.MASK_OBSTACLES)
	query.collide_with_bodies = true
	query.collide_with_areas = false
	return not space_state.intersect_ray(query).is_empty()


func test_01_simple_move_order_lifecycle_and_smooth_rotation() -> void:
	var ctx: Dictionary = await _setup_map_and_unit(Vector3(0.0, 0.0, 4.0), LEADER_A_DEF)
	if ctx.is_empty():
		return
	var unit: Unit = ctx["unit"] as Unit
	assert_eq(unit.get_state(), Unit.State.IDLE, "Unit must start in IDLE state")

	var transitions: Array[Array] = []
	unit.state_changed.connect(func(new_state: Unit.State, prev_state: Unit.State) -> void:
		transitions.append([prev_state, new_state])
	)
	var finished_orders: Array[UnitOrder] = []
	unit.order_finished.connect(func(done_order: UnitOrder) -> void:
		finished_orders.append(done_order)
	)

	var target: Vector3 = Vector3(10.0, 0.0, 4.0)
	var order: MoveOrder = MoveOrder.new(target)
	unit.issue_order(order)

	assert_eq(unit.get_state(), Unit.State.MOVING, "Unit must transition to MOVING after valid MoveOrder")
	assert_eq(order.status, UnitOrder.Status.RUNNING, "MoveOrder must report RUNNING while moving")

	await wait_physics_frames(1)
	var yaw_after_1_frame: float = unit.rotation.y
	assert_lt(yaw_after_1_frame, -0.01, "Unit must begin rotating toward East (-PI/2)")
	assert_gt(yaw_after_1_frame, -PI * 0.45, "Rotation must be smooth, not instant snap on frame 1")

	var frames: int = 1
	while order.is_active() and frames < MAX_MOVE_FRAMES:
		await wait_physics_frames(1)
		frames += 1

	assert_false(order.is_active(), "MoveOrder must finish within bounded frames")
	assert_eq(order.status, UnitOrder.Status.SUCCEEDED, "Simple unobstructed MoveOrder must succeed")
	assert_eq(order.failure_reason, "", "Succeeded order must have empty failure_reason")
	assert_eq(unit.get_state(), Unit.State.IDLE, "Unit must return to IDLE after arrival")
	assert_eq(finished_orders.size(), 1, "order_finished must emit once")
	if finished_orders.size() == 1:
		assert_eq(finished_orders[0], order)
	assert_eq(transitions.size(), 2, "state_changed must record IDLE->MOVING and MOVING->IDLE")
	if transitions.size() == 2:
		assert_eq(transitions[0], [Unit.State.IDLE, Unit.State.MOVING])
		assert_eq(transitions[1], [Unit.State.MOVING, Unit.State.IDLE])

	var final_xz_dist: float = _distance_xz(unit.global_position, target)
	assert_lt(final_xz_dist, 0.5, "Unit must arrive within 0.5 m of target (got %.3f m)" % final_xz_dist)
	assert_near(unit.global_position.y, 0.0, 0.05, "Unit must remain grounded on terrain")
	assert_near(angle_difference(unit.rotation.y, -PI * 0.5), 0.0, 0.15, "Unit must face travel direction (East)")
	print("  [Test A SimpleMove] frames=%d, final_xz_dist=%.3f m, pos=%s" % [frames, final_xz_dist, str(unit.global_position)])


func test_02_wall_gap_navigation_avoids_obstacles() -> void:
	var ctx: Dictionary = await _setup_map_and_unit(Vector3(-6.0, 0.0, -1.0), LEADER_A_DEF)
	if ctx.is_empty():
		return
	var test_map: TestMap = ctx["map"] as TestMap
	var unit: Unit = ctx["unit"] as Unit
	var space_state: PhysicsDirectSpaceState3D = test_map.get_world_3d().direct_space_state

	var target: Vector3 = Vector3(-6.0, 0.0, -12.0)
	var order: MoveOrder = MoveOrder.new(target)
	unit.issue_order(order)
	assert_eq(order.status, UnitOrder.Status.RUNNING)

	var prev_pos: Vector3 = unit.global_position
	var crossing_x: float = INF
	var pierced_obstacle: bool = false
	var frames: int = 0

	while order.is_active() and frames < MAX_MOVE_FRAMES:
		await wait_physics_frames(1)
		frames += 1
		var curr_pos: Vector3 = unit.global_position
		if (prev_pos.z >= -6.0 and curr_pos.z <= -6.0) or (prev_pos.z <= -6.0 and curr_pos.z >= -6.0):
			var t: float = 0.0 if is_equal_approx(curr_pos.z, prev_pos.z) else (-6.0 - prev_pos.z) / (curr_pos.z - prev_pos.z)
			crossing_x = lerpf(prev_pos.x, curr_pos.x, clampf(t, 0.0, 1.0))
		if _segment_hits_obstacle(space_state, prev_pos, curr_pos):
			pierced_obstacle = true
		prev_pos = curr_pos

	assert_eq(order.status, UnitOrder.Status.SUCCEEDED, "Wall-gap navigation order must succeed")
	assert_eq(unit.get_state(), Unit.State.IDLE)
	assert_false(pierced_obstacle, "Unit movement path must never pierce wall or obstacle colliders")
	assert_true(is_finite(crossing_x) and absf(crossing_x) < 2.0, "Unit must cross z=-6 through central 4m gap (x=%.3f)" % crossing_x)
	var dist_to_goal: float = _distance_xz(unit.global_position, target)
	assert_lt(dist_to_goal, 0.5, "Unit must reach destination beyond wall gap (dist=%.3f m)" % dist_to_goal)
	print("  [Test B WallGap] frames=%d, crossing_x=%.3f, final_dist=%.3f m" % [frames, crossing_x, dist_to_goal])


func test_03_ramp_climb_and_descent_terrain_alignment() -> void:
	var ctx: Dictionary = await _setup_map_and_unit(Vector3(1.0, 0.0, -14.0), LEADER_B_DEF)
	if ctx.is_empty():
		return
	var test_map: TestMap = ctx["map"] as TestMap
	var unit: Unit = ctx["unit"] as Unit
	var space_state: PhysicsDirectSpaceState3D = test_map.get_world_3d().direct_space_state

	var plateau_target: Vector3 = Vector3(18.0, 2.0, -14.0)
	var climb_order: MoveOrder = MoveOrder.new(plateau_target)
	unit.issue_order(climb_order)
	assert_eq(climb_order.status, UnitOrder.Status.RUNNING)

	var prev_pos: Vector3 = unit.global_position
	var max_step_dist: float = 0.0
	var max_vert_dev_up: float = 0.0
	var saw_ramp_mid: bool = false
	var frames_up: int = 0

	while climb_order.is_active() and frames_up < MAX_MOVE_FRAMES:
		await wait_physics_frames(1)
		frames_up += 1
		var curr_pos: Vector3 = unit.global_position
		max_step_dist = maxf(max_step_dist, prev_pos.distance_to(curr_pos))
		prev_pos = curr_pos

		var terrain_y: float = _raycast_terrain_y(space_state, curr_pos)
		assert_true(is_finite(terrain_y), "Terrain raycast underneath unit must always hit")
		if is_finite(terrain_y):
			max_vert_dev_up = maxf(max_vert_dev_up, absf(curr_pos.y - terrain_y))

		if curr_pos.x >= 6.0 and curr_pos.x <= 12.0 and curr_pos.y > 0.25 and curr_pos.y < 1.75:
			saw_ramp_mid = true

	assert_eq(climb_order.status, UnitOrder.Status.SUCCEEDED, "Ramp climb to plateau must succeed")
	assert_eq(unit.get_state(), Unit.State.IDLE)
	assert_true(saw_ramp_mid, "Unit must physically traverse the ramp elevation (y between 0.25 and 1.75)")
	assert_lt(max_step_dist, 0.25, "Per-frame displacement must be continuous without teleporting (max=%.3f m)" % max_step_dist)
	assert_true(max_vert_dev_up <= 0.1, "Vertical deviation from physical terrain climbing ramp must be <= 0.1 m (got %.4f m)" % max_vert_dev_up)
	assert_lt(_distance_xz(unit.global_position, plateau_target), 0.5)
	assert_near(unit.global_position.y, 2.0, 0.06, "Unit must rest on plateau surface (y=2.0)")

	var ground_target: Vector3 = Vector3(2.0, 0.0, -14.0)
	var descend_order: MoveOrder = MoveOrder.new(ground_target)
	unit.issue_order(descend_order)
	var max_vert_dev_down: float = 0.0
	var frames_down: int = 0

	while descend_order.is_active() and frames_down < MAX_MOVE_FRAMES:
		await wait_physics_frames(1)
		frames_down += 1
		var curr_pos: Vector3 = unit.global_position
		var terrain_y: float = _raycast_terrain_y(space_state, curr_pos)
		if is_finite(terrain_y):
			max_vert_dev_down = maxf(max_vert_dev_down, absf(curr_pos.y - terrain_y))

	assert_eq(descend_order.status, UnitOrder.Status.SUCCEEDED, "Ramp descent back to ground must succeed")
	assert_true(max_vert_dev_down <= 0.1, "Vertical deviation descending ramp must stay <= 0.1 m (got %.4f m)" % max_vert_dev_down)
	assert_near(unit.global_position.y, 0.0, 0.05, "Unit must return to main ground height (y=0.0)")
	print("  [Test C Ramp] up_frames=%d, down_frames=%d, max_dy_up=%.4f m, max_dy_down=%.4f m" % [
		frames_up, frames_down, max_vert_dev_up, max_vert_dev_down
	])


func test_04_closed_enclosure_unreachable_resolves_exterior_and_fails() -> void:
	var ctx: Dictionary = await _setup_map_and_unit(Vector3(-4.0, 0.0, 12.0), LEADER_A_DEF)
	if ctx.is_empty():
		return
	var unit: Unit = ctx["unit"] as Unit

	var enclosure_interior: Vector3 = Vector3(-16.0, 0.0, 12.0)
	var order: MoveOrder = MoveOrder.new(enclosure_interior)
	unit.issue_order(order)

	assert_true(order.is_partial_unreachable, "MoveOrder into closed enclosure must detect partial unreachability")
	assert_eq(order.status, UnitOrder.Status.RUNNING, "Unit should walk to exterior fallback before failing")

	var enclosure_bounds: Rect2 = Rect2(-20.0, 8.0, 8.0, 8.0)
	var resolved_xz: Vector2 = Vector2(order.resolved_target.x, order.resolved_target.z)
	assert_false(enclosure_bounds.has_point(resolved_xz), "Resolved fallback must lie outside closed enclosure")

	var frames: int = 0
	while order.is_active() and frames < MAX_MOVE_FRAMES:
		await wait_physics_frames(1)
		frames += 1

	assert_false(order.is_active(), "Unreachable order must terminate within bounded time without oscillating")
	assert_eq(order.status, UnitOrder.Status.FAILED, "Order to unreachable interior must finish as FAILED")
	assert_eq(order.failure_reason, UnitOrder.REASON_UNREACHABLE, "Failure reason must be 'unreachable'")
	assert_eq(unit.get_state(), Unit.State.IDLE, "Unit must return to IDLE after unreachable failure")

	var final_xz: Vector2 = Vector2(unit.global_position.x, unit.global_position.z)
	assert_false(enclosure_bounds.has_point(final_xz), "Unit must remain outside closed enclosure")
	assert_lt(_distance_xz(unit.global_position, order.resolved_target), 0.5, "Unit should reach exterior fallback point")

	var settled_pos: Vector3 = unit.global_position
	await wait_physics_frames(20)
	assert_lt(unit.global_position.distance_to(settled_pos), 0.02, "Unit must not oscillate or drift after settling")
	print("  [Test D Unreachable] frames=%d, resolved=%s, final=%s" % [frames, str(order.resolved_target), str(settled_pos)])


func test_05_order_replacement_cancels_previous_and_reaches_new_target() -> void:
	var ctx: Dictionary = await _setup_map_and_unit(Vector3(-10.0, 0.0, 2.0), LEADER_B_DEF)
	if ctx.is_empty():
		return
	var unit: Unit = ctx["unit"] as Unit

	var finished_orders: Array[UnitOrder] = []
	unit.order_finished.connect(func(done_order: UnitOrder) -> void:
		finished_orders.append(done_order)
	)

	var first_order: MoveOrder = MoveOrder.new(Vector3(16.0, 0.0, 2.0))
	unit.issue_order(first_order)
	assert_eq(first_order.status, UnitOrder.Status.RUNNING)

	await wait_physics_frames(60)
	assert_gt(unit.global_position.x, -7.0, "Unit should have progressed East during first order")
	assert_eq(first_order.status, UnitOrder.Status.RUNNING)

	var second_target: Vector3 = Vector3(-10.0, 0.0, -12.0)
	var second_order: MoveOrder = MoveOrder.new(second_target)
	unit.issue_order(second_order)

	assert_eq(first_order.status, UnitOrder.Status.CANCELLED, "Replaced order must transition cleanly to CANCELLED")
	assert_eq(first_order.failure_reason, UnitOrder.REASON_REPLACED)
	assert_eq(finished_orders.size(), 1, "order_finished must emit for replaced order")
	assert_eq(second_order.status, UnitOrder.Status.RUNNING, "New order must take over immediately")
	assert_eq(unit.get_current_order(), second_order)
	assert_eq(unit.get_state(), Unit.State.MOVING)

	var frames: int = 0
	while second_order.is_active() and frames < MAX_MOVE_FRAMES:
		await wait_physics_frames(1)
		frames += 1

	assert_eq(second_order.status, UnitOrder.Status.SUCCEEDED, "Replacement order must succeed")
	assert_eq(unit.get_state(), Unit.State.IDLE)
	assert_eq(finished_orders.size(), 2)
	var dist_to_new: float = _distance_xz(unit.global_position, second_target)
	assert_lt(dist_to_new, 0.5, "Unit must arrive at new destination (dist=%.3f m)" % dist_to_new)
	print("  [Test E Replacement] frames_second=%d, final_dist=%.3f m" % [frames, dist_to_new])


func test_06_controlled_stuck_recovery_and_failure() -> void:
	var ctx: Dictionary = await _setup_map_and_unit(Vector3(-4.0, 0.0, 2.0), LEADER_A_DEF)
	if ctx.is_empty():
		return
	var test_map: TestMap = ctx["map"] as TestMap
	var unit: Unit = ctx["unit"] as Unit

	# Place an unbaked physical obstacle across the path after WorldNavigation baked,
	# forcing continuous collision blocking so stuck detection and repath trigger deterministically.
	var blocker := StaticBody3D.new()
	blocker.collision_layer = CollisionLayers.MASK_OBSTACLES
	blocker.collision_mask = 0
	var blocker_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.8, 2.5, 10.0)
	blocker_shape.shape = box
	blocker.add_child(blocker_shape)
	test_map.add_child(blocker)
	blocker.global_position = Vector3(-1.5, 1.25, 2.0)
	await wait_physics_frames(2)

	var order: MoveOrder = MoveOrder.new(Vector3(8.0, 0.0, 2.0))
	unit.issue_order(order)
	assert_eq(order.status, UnitOrder.Status.RUNNING)

	var frames: int = 0
	var max_repaths_seen: int = 0
	while order.is_active() and frames < MAX_MOVE_FRAMES:
		await wait_physics_frames(1)
		frames += 1
		max_repaths_seen = maxi(max_repaths_seen, unit.get_movement().get_repath_attempts())

	assert_false(order.is_active(), "Stuck order must terminate within bounded frames")
	assert_eq(order.status, UnitOrder.Status.FAILED, "Blocked unit must fail with stuck status")
	assert_eq(order.failure_reason, UnitOrder.REASON_STUCK, "Failure reason must be 'stuck'")
	assert_eq(max_repaths_seen, UnitMovement.MAX_REPATH_ATTEMPTS, "Stuck recovery must perform exactly 1 controlled repath")
	assert_eq(unit.get_state(), Unit.State.IDLE, "Unit must return to IDLE after stuck failure")
	print("  [Test F Stuck] frames=%d, repaths=%d, pos=%s" % [frames, max_repaths_seen, str(unit.global_position)])


func test_07_pre_ready_invalid_orders_and_main_scene_protagonists() -> void:
	# 1. Pre-ready and invalid coordinate checks
	var test_map: TestMap = TEST_MAP_SCENE.instantiate() as TestMap
	add_test_child(test_map)
	var nav: WorldNavigation = test_map.get_navigation()
	assert_false(nav.is_navigation_ready(), "Pre-ready check expects navigation not ready yet")

	var test_unit: Unit = UNIT_SCENE.instantiate() as Unit
	test_unit.definition = LEADER_A_DEF
	test_map.add_child(test_unit)
	test_unit.global_position = Vector3(0.0, 0.0, 2.0)
	test_unit.set_world_navigation(nav)

	var pre_ready_order: MoveOrder = MoveOrder.new(Vector3(4.0, 0.0, 2.0))
	test_unit.issue_order(pre_ready_order)
	assert_eq(pre_ready_order.status, UnitOrder.Status.FAILED, "Order issued before navigation_ready must fail explicitly")
	assert_eq(pre_ready_order.failure_reason, UnitOrder.REASON_NAVIGATION_NOT_READY)
	assert_eq(test_unit.get_state(), Unit.State.IDLE)

	assert_true(await _wait_for_navigation_ready(nav))
	var invalid_order: MoveOrder = MoveOrder.new(Vector3(NAN, 0.0, 0.0))
	test_unit.issue_order(invalid_order)
	assert_eq(invalid_order.status, UnitOrder.Status.FAILED, "Non-finite target order must fail explicitly")
	assert_eq(invalid_order.failure_reason, UnitOrder.REASON_INVALID_TARGET)
	assert_eq(test_unit.get_state(), Unit.State.IDLE)

	# 2. Main scene protagonists composition and non-colliding crossing
	var main_root: MainScene = MAIN_SCENE.instantiate() as MainScene
	add_test_child(main_root)
	var main_map: TestMap = main_root.get_node_or_null("TestMap") as TestMap
	assert_not_null(main_map)
	var main_nav: WorldNavigation = main_map.get_navigation()
	assert_true(await _wait_for_navigation_ready(main_nav))

	var units: Array[Unit] = main_root.get_units()
	assert_eq(units.size(), 2, "Main scene must instantiate the two protagonists")
	var leader_a: Unit = units[0]
	var leader_b: Unit = units[1]
	assert_ne(leader_a.get_character_id(), leader_b.get_character_id(), "Protagonists must have distinct IDs")
	assert_ne(leader_a.get_definition().silhouette_kind, leader_b.get_definition().silhouette_kind, "Protagonists must differ in silhouette shape")
	assert_ne(leader_a.get_definition().primary_color, leader_b.get_definition().primary_color, "Protagonists must differ in primary color")
	assert_eq(leader_a.get_state(), Unit.State.IDLE)
	assert_eq(leader_b.get_state(), Unit.State.IDLE)
	assert_eq(leader_a.collision_mask & CollisionLayers.MASK_UNITS, 0, "Units must not physically collide with each other in T1.5")
	assert_eq(leader_b.collision_mask & CollisionLayers.MASK_UNITS, 0, "Units must not physically collide with each other in T1.5")

	var start_a: Vector3 = leader_a.global_position
	var start_b: Vector3 = leader_b.global_position
	var swap_a: MoveOrder = MoveOrder.new(start_b)
	var swap_b: MoveOrder = MoveOrder.new(start_a)
	leader_a.issue_order(swap_a)
	leader_b.issue_order(swap_b)

	var swap_frames: int = 0
	while (swap_a.is_active() or swap_b.is_active()) and swap_frames < MAX_MOVE_FRAMES:
		await wait_physics_frames(1)
		swap_frames += 1

	assert_eq(swap_a.status, UnitOrder.Status.SUCCEEDED, "LeaderA crossing path with LeaderB must succeed cleanly")
	assert_eq(swap_b.status, UnitOrder.Status.SUCCEEDED, "LeaderB crossing path with LeaderA must succeed cleanly")
	assert_lt(_distance_xz(leader_a.global_position, start_b), 0.5)
	assert_lt(_distance_xz(leader_b.global_position, start_a), 0.5)


func test_08_diagonal_wall_gap_to_ramp_plateau() -> void:
	var ctx: Dictionary = await _setup_map_and_unit(Vector3(2.5, 0.0, 2.5), LEADER_B_DEF)
	if ctx.is_empty():
		return
	var test_map: TestMap = ctx["map"] as TestMap
	var unit: Unit = ctx["unit"] as Unit
	var space_state: PhysicsDirectSpaceState3D = test_map.get_world_3d().direct_space_state

	var plateau_target: Vector3 = Vector3(18.0, 2.0, -14.0)
	var order: MoveOrder = MoveOrder.new(plateau_target)
	unit.issue_order(order)
	assert_eq(order.status, UnitOrder.Status.RUNNING)

	var max_vert_dev_interior: float = 0.0
	var max_vert_dev_all: float = 0.0
	var frames: int = 0
	while order.is_active() and frames < MAX_MOVE_FRAMES:
		await wait_physics_frames(1)
		frames += 1
		var p: Vector3 = unit.global_position
		var terrain_y: float = _raycast_terrain_y(space_state, p)
		if is_finite(terrain_y):
			var dy: float = absf(p.y - terrain_y)
			max_vert_dev_all = maxf(max_vert_dev_all, dy)
			var straddling_ramp_side_lip: bool = p.x >= 4.8 and p.x <= 7.5 and p.z >= -12.05 and p.z <= -11.5
			if not straddling_ramp_side_lip:
				max_vert_dev_interior = maxf(max_vert_dev_interior, dy)

	assert_eq(order.status, UnitOrder.Status.SUCCEEDED, "Diagonal route through wall gap and up ramp to plateau must succeed")
	assert_eq(unit.get_state(), Unit.State.IDLE)
	assert_true(max_vert_dev_interior <= 0.1, "Vertical deviation on supported ground/ramp/plateau must remain <= 0.1 m (got %.4f m; lip_max=%.4f m)" % [max_vert_dev_interior, max_vert_dev_all])
	assert_lt(_distance_xz(unit.global_position, plateau_target), 0.5)
	assert_near(unit.global_position.y, 2.0, 0.06)
	print("  [Test 08 DiagonalRamp] frames=%d, max_dy_interior=%.4f m, max_dy_lip=%.4f m" % [frames, max_vert_dev_interior, max_vert_dev_all])

