extends TestCase
## Integration tests for T1.2: greybox test map geometry, physics layers,
## raycast clearance/blocking, main scene composition, and DebugOverlay.

const TEST_MAP_SCENE: PackedScene = preload("res://levels/test_map/test_map.tscn")
const MAIN_SCENE: PackedScene = preload("res://src/main/main.tscn")


func test_01_test_map_loads_and_exposes_bounds() -> void:
	var level: Node = TEST_MAP_SCENE.instantiate()
	add_test_child(level)
	assert_true(level is TestMap, "Root of test_map.tscn must use TestMap script")

	var test_map: TestMap = level as TestMap
	var bounds: Rect2 = test_map.get_map_bounds()
	assert_vec2_near(bounds.position, Vector2(-32.0, -32.0), 0.001, "Map bounds origin must match 64x64 centered ground")
	assert_vec2_near(bounds.size, Vector2(64.0, 64.0), 0.001, "Map bounds size must be 64x64 m")

	var light: DirectionalLight3D = test_map.get_node_or_null("DirectionalLight3D") as DirectionalLight3D
	assert_not_null(light, "TestMap must include DirectionalLight3D")
	if light != null:
		assert_true(light.shadow_enabled, "DirectionalLight3D must have shadows enabled")


func test_02_colliders_assigned_to_expected_physics_layers() -> void:
	var test_map: TestMap = TEST_MAP_SCENE.instantiate() as TestMap
	add_test_child(test_map)

	var terrain_root: Node = test_map.get_node_or_null("Terrain")
	assert_not_null(terrain_root, "TestMap must have Terrain container")
	var terrain_bodies: Array[StaticBody3D] = _collect_static_bodies(terrain_root)
	assert_eq(terrain_bodies.size(), 3, "Terrain must contain Ground, Plateau, and Ramp")
	for body: StaticBody3D in terrain_bodies:
		assert_eq(body.collision_layer, CollisionLayers.MASK_TERRAIN, "%s must be on terrain layer" % body.name)
		assert_eq(body.collision_mask, 0, "%s static terrain should have empty collision_mask" % body.name)
		assert_true(_has_valid_shape(body), "%s must have a valid CollisionShape3D" % body.name)

	var obstacles_root: Node = test_map.get_node_or_null("Obstacles")
	assert_not_null(obstacles_root, "TestMap must have Obstacles container")
	var obstacle_bodies: Array[StaticBody3D] = _collect_static_bodies(obstacles_root)
	assert_gt(float(obstacle_bodies.size()), 10.0, "Obstacles must include wall, enclosure, rocks, and trees")
	for body: StaticBody3D in obstacle_bodies:
		assert_eq(body.collision_layer, CollisionLayers.MASK_OBSTACLES, "%s must be on obstacles layer" % body.name)
		assert_eq(body.collision_mask, 0, "%s static obstacle should have empty collision_mask" % body.name)
		assert_true(_has_valid_shape(body), "%s must have a valid CollisionShape3D" % body.name)


func test_03_terrain_and_obstacle_raycasts_match_greybox_layout() -> void:
	var test_map: TestMap = TEST_MAP_SCENE.instantiate() as TestMap
	add_test_child(test_map)
	await wait_physics_frames(2)

	var space_state: PhysicsDirectSpaceState3D = test_map.get_world_3d().direct_space_state
	assert_not_null(space_state, "World3D direct_space_state must be available")

	var ground_hit: Dictionary = _raycast(space_state, Vector3(0.0, 10.0, 0.0), Vector3(0.0, -5.0, 0.0), CollisionLayers.MASK_TERRAIN)
	assert_false(ground_hit.is_empty(), "Ground center raycast must hit terrain")
	if not ground_hit.is_empty():
		assert_near((ground_hit["position"] as Vector3).y, 0.0, 0.02, "Ground top surface must be at y=0")

	var plateau_hit: Dictionary = _raycast(space_state, Vector3(18.0, 10.0, -14.0), Vector3(18.0, -5.0, -14.0), CollisionLayers.MASK_TERRAIN)
	assert_false(plateau_hit.is_empty(), "Plateau center raycast must hit terrain")
	if not plateau_hit.is_empty():
		assert_near((plateau_hit["position"] as Vector3).y, 2.0, 0.02, "Plateau top surface must be at y=2")

	var ramp_hit: Dictionary = _raycast(space_state, Vector3(9.0, 10.0, -14.0), Vector3(9.0, -5.0, -14.0), CollisionLayers.MASK_TERRAIN)
	assert_false(ramp_hit.is_empty(), "Ramp midpoint raycast must hit terrain")
	if not ramp_hit.is_empty():
		assert_near((ramp_hit["position"] as Vector3).y, 1.0, 0.03, "Ramp midpoint surface must be at y=1")

	var enclosure_floor_hit: Dictionary = _raycast(space_state, Vector3(-16.0, 10.0, 12.0), Vector3(-16.0, -5.0, 12.0), CollisionLayers.MASK_TERRAIN)
	assert_false(enclosure_floor_hit.is_empty(), "Closed enclosure interior floor must be solid terrain")
	if not enclosure_floor_hit.is_empty():
		assert_near((enclosure_floor_hit["position"] as Vector3).y, 0.0, 0.02, "Enclosure interior floor must be at y=0")

	var gap_hit: Dictionary = _raycast(space_state, Vector3(0.0, 1.0, -10.0), Vector3(0.0, 1.0, -2.0), CollisionLayers.MASK_OBSTACLES)
	assert_true(gap_hit.is_empty(), "Central gap in wall must be unobstructed")

	var wall_west_hit: Dictionary = _raycast(space_state, Vector3(-8.0, 1.0, -10.0), Vector3(-8.0, 1.0, -2.0), CollisionLayers.MASK_OBSTACLES)
	assert_false(wall_west_hit.is_empty(), "West wall segment must block obstacles raycast")

	var wall_east_hit: Dictionary = _raycast(space_state, Vector3(8.0, 1.0, -10.0), Vector3(8.0, 1.0, -2.0), CollisionLayers.MASK_OBSTACLES)
	assert_false(wall_east_hit.is_empty(), "East wall segment must block obstacles raycast")

	var enclosure_center: Vector3 = Vector3(-16.0, 0.8, 12.0)
	var cardinal_targets: Array[Vector3] = [
		Vector3(-16.0, 0.8, 6.0),
		Vector3(-16.0, 0.8, 18.0),
		Vector3(-22.0, 0.8, 12.0),
		Vector3(-10.0, 0.8, 12.0),
	]
	for target: Vector3 in cardinal_targets:
		var wall_hit: Dictionary = _raycast(space_state, enclosure_center, target, CollisionLayers.MASK_OBSTACLES)
		assert_false(wall_hit.is_empty(), "Closed enclosure must block raycast toward %s" % str(target))


func test_04_main_scene_and_debug_overlay_behavior() -> void:
	var main_root: Node = MAIN_SCENE.instantiate()
	add_test_child(main_root)
	await wait_process_frames(3)

	var test_map: TestMap = main_root.get_node_or_null("TestMap") as TestMap
	assert_not_null(test_map, "Main scene must compose TestMap")

	var overlay: DebugOverlay = main_root.get_node_or_null("UiLayer/DebugOverlay") as DebugOverlay
	assert_not_null(overlay, "Main scene must compose UiLayer/DebugOverlay")
	if overlay == null:
		return

	assert_eq(overlay.mouse_filter, Control.MOUSE_FILTER_IGNORE, "DebugOverlay must not block mouse input")
	assert_true(overlay.visible, "DebugOverlay should start visible by default")

	var stats: String = overlay.get_stats_text()
	assert_string_contains(stats, "FPS:")
	assert_string_contains(stats, "Frame:")
	assert_string_contains(stats, "Nodes:")

	_send_debug_toggle_press()
	await wait_process_frames(1)
	assert_false(overlay.visible, "Pressing debug_overlay (F3) must hide DebugOverlay")

	_send_debug_toggle_press()
	await wait_process_frames(1)
	assert_true(overlay.visible, "Pressing debug_overlay (F3) again must show DebugOverlay even when hidden")


func _send_debug_toggle_press() -> void:
	var press_event: InputEventAction = InputEventAction.new()
	press_event.action = InputActions.DEBUG_OVERLAY
	press_event.pressed = true
	Input.parse_input_event(press_event)

	var release_event: InputEventAction = InputEventAction.new()
	release_event.action = InputActions.DEBUG_OVERLAY
	release_event.pressed = false
	Input.parse_input_event(release_event)


func _collect_static_bodies(root_node: Node) -> Array[StaticBody3D]:
	var bodies: Array[StaticBody3D] = []
	if root_node == null:
		return bodies
	for child: Node in root_node.get_children():
		if child is StaticBody3D:
			bodies.append(child as StaticBody3D)
		bodies.append_array(_collect_static_bodies(child))
	return bodies


func _has_valid_shape(body: StaticBody3D) -> bool:
	for child: Node in body.get_children():
		if child is CollisionShape3D:
			var col_shape: CollisionShape3D = child as CollisionShape3D
			if col_shape.shape != null:
				return true
	return false


func _raycast(space_state: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3, mask: int) -> Dictionary:
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, to, mask)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	return space_state.intersect_ray(query)
