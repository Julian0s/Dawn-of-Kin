extends TestCase
## Integration tests for T1.4 WorldNavigation:
## wall-with-gap routing, closed enclosure unreachability, ramp-to-plateau access,
## async readiness gate, map bounds clamping, and bake/sync timing metrics.

const TEST_MAP_SCENE: PackedScene = preload("res://levels/test_map/test_map.tscn")
const MAX_WAIT_FRAMES: int = 120


func _wait_for_navigation_ready(nav: WorldNavigation) -> bool:
	var frames: int = 0
	while not nav.is_navigation_ready() and frames < MAX_WAIT_FRAMES:
		await wait_physics_frames(1)
		frames += 1
	return nav.is_navigation_ready()


func _path_crosses_obstacle(space_state: PhysicsDirectSpaceState3D, path: PackedVector3Array) -> bool:
	for i: int in range(path.size() - 1):
		var a: Vector3 = path[i] + Vector3(0.0, 0.8, 0.0)
		var b: Vector3 = path[i + 1] + Vector3(0.0, 0.8, 0.0)
		if a.distance_squared_to(b) < 0.0001:
			continue
		var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(a, b, CollisionLayers.MASK_OBSTACLES)
		query.collide_with_bodies = true
		query.collide_with_areas = false
		if not space_state.intersect_ray(query).is_empty():
			return true
	return false


func test_01_path_routes_through_wall_gap_without_cutting_obstacles() -> void:
	var test_map: TestMap = TEST_MAP_SCENE.instantiate() as TestMap
	add_test_child(test_map)
	var nav: WorldNavigation = test_map.get_navigation()
	assert_not_null(nav, "TestMap must expose WorldNavigation")
	if nav == null:
		return

	var ready_ok: bool = await _wait_for_navigation_ready(nav)
	assert_true(ready_ok, "WorldNavigation must become ready within bounded physics frames")

	var start: Vector3 = Vector3(-4.0, 0.0, 2.0)
	var goal: Vector3 = Vector3(0.0, 0.0, -14.0)
	var result: WorldNavigation.PathResult = nav.find_path(start, goal)

	assert_true(result.is_ok(), "Path across wall gap must succeed")
	assert_true(result.reachable, "Goal beyond wall gap must be reachable")
	assert_gt(float(result.path.size()), 2.0, "Path around/through wall gap should contain intermediate waypoints")

	var crossed_gap: bool = false
	for i: int in range(result.path.size() - 1):
		var p0: Vector3 = result.path[i]
		var p1: Vector3 = result.path[i + 1]
		if (p0.z >= -6.0 and p1.z <= -6.0) or (p0.z <= -6.0 and p1.z >= -6.0):
			var t: float = 0.0 if is_equal_approx(p1.z, p0.z) else (-6.0 - p0.z) / (p1.z - p0.z)
			var cross_x: float = lerpf(p0.x, p1.x, clampf(t, 0.0, 1.0))
			if absf(cross_x) < 2.0:
				crossed_gap = true
	assert_true(crossed_gap, "Path must cross z=-6 inside the 4m central gap (|x| < 2)")

	var space_state: PhysicsDirectSpaceState3D = test_map.get_world_3d().direct_space_state
	assert_false(_path_crosses_obstacle(space_state, result.path), "Path segments must not intersect wall or obstacle colliders")
	print("  [Route WallGap] waypoints=%d, end=%s" % [result.path.size(), str(result.resolved_target)])


func test_02_closed_enclosure_is_unreachable_and_resolves_exterior_target() -> void:
	var test_map: TestMap = TEST_MAP_SCENE.instantiate() as TestMap
	add_test_child(test_map)
	var nav: WorldNavigation = test_map.get_navigation()
	assert_true(await _wait_for_navigation_ready(nav))

	var exterior_origin: Vector3 = Vector3(0.0, 0.0, 12.0)
	var interior_target: Vector3 = Vector3(-16.0, 0.0, 12.0)
	var result: WorldNavigation.PathResult = nav.find_path(exterior_origin, interior_target)

	assert_eq(result.status, WorldNavigation.QueryStatus.PARTIAL_UNREACHABLE, "Closed enclosure interior must report PARTIAL_UNREACHABLE")
	assert_false(result.reachable, "Interior of closed enclosure must not be reported reachable from outside")
	assert_false(nav.is_position_reachable(exterior_origin, interior_target))
	var enclosure_bounds: Rect2 = Rect2(-20.0, 8.0, 8.0, 8.0)
	var resolved_xz: Vector2 = Vector2(result.resolved_target.x, result.resolved_target.z)
	assert_false(enclosure_bounds.has_point(resolved_xz), "Fallback target must lie outside closed enclosure bounds [-20,-12]x[8,16]")
	assert_true(nav.is_position_reachable(exterior_origin, result.resolved_target), "Fallback target must be reachable from exterior origin")

	var space_state: PhysicsDirectSpaceState3D = test_map.get_world_3d().direct_space_state
	assert_false(_path_crosses_obstacle(space_state, result.path), "Fallback path to enclosure exterior must not pierce walls")
	print("  [Route Enclosure] status=%d, reason=%s, resolved=%s" % [result.status, result.reason, str(result.resolved_target)])


func test_03_ramp_connects_ground_to_elevated_plateau() -> void:
	var test_map: TestMap = TEST_MAP_SCENE.instantiate() as TestMap
	add_test_child(test_map)
	var nav: WorldNavigation = test_map.get_navigation()
	assert_true(await _wait_for_navigation_ready(nav))

	var ground_start: Vector3 = Vector3(0.0, 0.0, -14.0)
	var plateau_goal: Vector3 = Vector3(18.0, 2.0, -14.0)
	var result: WorldNavigation.PathResult = nav.find_path(ground_start, plateau_goal)

	assert_true(result.is_ok(), "Plateau must be reachable via ramp")
	assert_true(result.reachable)
	assert_gt(float(result.path.size()), 1.0)

	var end_point: Vector3 = result.path[result.path.size() - 1]
	assert_near(end_point.x, plateau_goal.x, 0.75)
	assert_near(end_point.z, plateau_goal.z, 0.75)
	assert_gt(end_point.y, 1.85, "Path end must reach elevated plateau height (~2.0 m)")

	var traversed_ramp: bool = false
	for wp: Vector3 in result.path:
		if wp.x >= 4.5 and wp.x <= 13.5 and absf(wp.z - (-14.0)) <= 2.2:
			traversed_ramp = true
	assert_true(traversed_ramp, "Path to plateau must traverse the ramp corridor")
	print("  [Route RampPlateau] waypoints=%d, end=%s" % [result.path.size(), str(end_point)])


func test_04_pre_ready_query_and_navigation_ready_signal() -> void:
	var test_map: TestMap = TEST_MAP_SCENE.instantiate() as TestMap
	add_test_child(test_map)
	var nav: WorldNavigation = test_map.get_navigation()
	assert_not_null(nav)
	if nav == null:
		return

	assert_false(nav.is_navigation_ready(), "WorldNavigation must not report ready before bake + server sync")
	var early_result: WorldNavigation.PathResult = nav.find_path(Vector3.ZERO, Vector3(4.0, 0.0, 4.0))
	assert_eq(early_result.status, WorldNavigation.QueryStatus.NOT_READY)
	assert_false(early_result.reachable)
	assert_eq(early_result.reason, "navigation_not_ready")

	var signal_counts: Array[int] = [0]
	nav.navigation_ready.connect(func() -> void: signal_counts[0] += 1)

	assert_true(await _wait_for_navigation_ready(nav), "navigation_ready must complete cleanly")
	assert_eq(signal_counts[0], 1, "navigation_ready signal must emit exactly once after sync")

	var post_result: WorldNavigation.PathResult = nav.find_path(Vector3.ZERO, Vector3(4.0, 0.0, 4.0))
	assert_true(post_result.is_ok(), "Queries after navigation_ready must succeed")
	assert_true(post_result.reachable)


func test_05_out_of_bounds_and_invalid_queries_are_safe() -> void:
	var test_map: TestMap = TEST_MAP_SCENE.instantiate() as TestMap
	add_test_child(test_map)
	var nav: WorldNavigation = test_map.get_navigation()
	assert_true(await _wait_for_navigation_ready(nav))

	var bounds: Rect2 = test_map.get_map_bounds()
	var outside_targets: Array[Vector3] = [
		Vector3(100.0, 0.0, 100.0),
		Vector3(-80.0, 0.0, -90.0),
	]
	for target: Vector3 in outside_targets:
		var result: WorldNavigation.PathResult = nav.find_path(Vector3.ZERO, target)
		assert_eq(result.status, WorldNavigation.QueryStatus.PARTIAL_UNREACHABLE, "Out-of-bounds target must not be reported reachable")
		assert_false(result.reachable)
		assert_true(result.resolved_target.is_finite())
		assert_true(bounds.has_point(Vector2(result.resolved_target.x, result.resolved_target.z)), "Clamped fallback must lie inside map_bounds")

	var invalid_result: WorldNavigation.PathResult = nav.find_path(Vector3.ZERO, Vector3(INF, 0.0, 0.0))
	assert_eq(invalid_result.status, WorldNavigation.QueryStatus.INVALID_QUERY)
	assert_false(invalid_result.reachable)


func test_06_bake_and_sync_timings_are_measured() -> void:
	var test_map: TestMap = TEST_MAP_SCENE.instantiate() as TestMap
	add_test_child(test_map)
	var nav: WorldNavigation = test_map.get_navigation()
	assert_true(await _wait_for_navigation_ready(nav))

	var metrics: Dictionary = nav.get_last_bake_metrics()
	var bake_ms: float = float(metrics.get("bake_ms", 0.0))
	var sync_ms: float = float(metrics.get("sync_ms", -1.0))
	var total_ms: float = float(metrics.get("total_ms", 0.0))
	var vert_count: int = int(metrics.get("vertex_count", 0))
	var poly_count: int = int(metrics.get("polygon_count", 0))

	assert_gt(bake_ms, 0.0, "Bake duration must be measured > 0 ms")
	assert_gt(sync_ms, -0.001, "Sync duration must be measured >= 0 ms")
	assert_gt(total_ms, 0.0)
	assert_gt(float(vert_count), 0.0, "Baked navmesh must have vertices")
	assert_gt(float(poly_count), 0.0, "Baked navmesh must have polygons")
	print("  [Metrics] bake=%.2f ms | sync=%.2f ms | total=%.2f ms | verts=%d | polys=%d" % [
		bake_ms, sync_ms, total_ms, vert_count, poly_count
	])


func test_07_navmesh_height_matches_physical_terrain_with_expected_voxel_offset() -> void:
	var test_map: TestMap = TEST_MAP_SCENE.instantiate() as TestMap
	add_test_child(test_map)
	var nav: WorldNavigation = test_map.get_navigation()
	assert_true(await _wait_for_navigation_ready(nav))

	var space_state: PhysicsDirectSpaceState3D = test_map.get_world_3d().direct_space_state
	var samples: Array[Dictionary] = [
		{"label": "ground_center", "xz": Vector2(0.0, 0.0), "expected_y": 0.0},
		{"label": "ground_south", "xz": Vector2(-4.0, 2.0), "expected_y": 0.0},
		{"label": "ground_wall_gap", "xz": Vector2(0.0, -6.0), "expected_y": 0.0},
		{"label": "ground_north_ramp_line", "xz": Vector2(0.0, -14.0), "expected_y": 0.0},
		{"label": "ramp_lower", "xz": Vector2(7.0, -14.0), "expected_y": 0.5},
		{"label": "ramp_mid", "xz": Vector2(9.0, -14.0), "expected_y": 1.0},
		{"label": "ramp_upper", "xz": Vector2(11.0, -14.0), "expected_y": 1.5},
		{"label": "plateau_center", "xz": Vector2(18.0, -14.0), "expected_y": 2.0},
		{"label": "plateau_corner", "xz": Vector2(21.0, -11.0), "expected_y": 2.0},
	]

	for sample: Dictionary in samples:
		var xz: Vector2 = sample["xz"] as Vector2
		var expected_y: float = float(sample["expected_y"])
		var label: String = str(sample["label"])

		var ray: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
			Vector3(xz.x, 10.0, xz.y),
			Vector3(xz.x, -5.0, xz.y),
			CollisionLayers.MASK_TERRAIN
		)
		var hit: Dictionary = space_state.intersect_ray(ray)
		assert_false(hit.is_empty(), "%s raycast must hit terrain" % label)
		if hit.is_empty():
			continue

		var phys_pos: Vector3 = hit["position"] as Vector3
		assert_near(phys_pos.y, expected_y, 0.03, "%s physical height must match geometry" % label)

		var nav_pt: Vector3 = nav.snap_to_navmesh(phys_pos)
		var delta_y: float = nav_pt.y - phys_pos.y
		assert_true(delta_y >= 0.0 and delta_y <= 0.75, "%s navmesh offset (%.3f m) must stay within voxelization bounds" % [label, delta_y])


func test_08_obstacle_tops_do_not_compromise_projection_or_reachability() -> void:
	var test_map: TestMap = TEST_MAP_SCENE.instantiate() as TestMap
	add_test_child(test_map)
	var nav: WorldNavigation = test_map.get_navigation()
	assert_true(await _wait_for_navigation_ready(nav))

	for v: Vector3 in nav.navigation_mesh.get_vertices():
		assert_lt(v.y, 2.6, "No isolated navmesh island should exist above plateau height (2.5 m)")

	var origin: Vector3 = Vector3(0.0, 0.0, 2.0)
	var obstacle_tops: Array[Vector3] = [
		Vector3(-8.0, 2.5, -6.0),
		Vector3(8.0, 2.5, -6.0),
		Vector3(-9.5, 1.4, -14.5),
		Vector3(-21.0, 1.7, -2.5),
		Vector3(-16.0, 1.6, 8.3),
	]
	for top_pos: Vector3 in obstacle_tops:
		var snapped: Vector3 = nav.snap_to_navmesh(top_pos)
		assert_lt(snapped.y, 1.0, "Projection from obstacle top %s must snap to ground navmesh, not obstacle top" % str(top_pos))

		var res: WorldNavigation.PathResult = nav.find_path(origin, top_pos)
		assert_eq(res.status, WorldNavigation.QueryStatus.PARTIAL_UNREACHABLE)
		assert_false(res.reachable, "Obstacle top %s must never be reported reachable" % str(top_pos))
		assert_lt(res.resolved_target.y, 1.0, "Resolved target for obstacle top %s must lie on ground" % str(top_pos))
